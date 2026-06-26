#!/usr/bin/env bash
# check-upstream.sh
# Query upstream for the current postgres:<major>-alpine digests and the latest
# pgvector release tag, compare against manifest.json, and (if anything drifted)
# rewrite manifest.json + re-render the variant Dockerfiles.
#
# Exit codes:
#   0  no drift  (manifest unchanged)
#   10 drift     (manifest.json + variants/ updated; caller should open a PR)
#   1  error
#
# Stdout: a human-readable summary of what changed (used as PR body).
# Requires: jq, curl, git (git only used by the caller, not here).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${REPO_ROOT}/manifest.json"

command -v jq   >/dev/null || { echo "error: jq is required" >&2; exit 1; }
command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 1; }

MAJORS="$(jq -r '.pg_majors[]' "$MANIFEST")"

# --- pgvector: latest stable tag (the project publishes lightweight tags, not
#     GitHub Release objects, so /releases/latest 404s — use the tags API). ---
gh_curl() {
  # Use GITHUB_TOKEN when present (CI) to avoid the low anonymous rate limit.
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$@"
  else
    curl -fsSL "$@"
  fi
}

latest_pgvector() {
  # Highest semver among v*.*.* tags, leading 'v' stripped.
  gh_curl "https://api.github.com/repos/pgvector/pgvector/tags?per_page=100" \
    | jq -r '.[].name' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed 's/^v//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -1
}

# --- postgres alpine: current multi-arch index digest per major. ---
alpine_digest() {
  local major="$1"
  local token
  token="$(curl -fsSL \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/postgres:pull" \
    | jq -r '.token')"
  curl -fsSL -o /dev/null -D - \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
    -I "https://registry-1.docker.io/v2/library/postgres/manifests/${major}-alpine" \
    | tr -d '\r' \
    | awk 'tolower($1) == "docker-content-digest:" { print $2 }'
}

# --- alpine release the bare <major>-alpine tag currently ships (informational
#     only; the digest above is the real lock). Resolved as the highest
#     <major>-alpineX.Y tag, which is what the bare -alpine tag points at. ---
alpine_version() {
  local major="$1"
  curl -fsSL "https://hub.docker.com/v2/repositories/library/postgres/tags?page_size=100&name=${major}-alpine3" \
    | jq -r '.results[].name' \
    | grep -oE "alpine3\.[0-9]+$" \
    | sed 's/^alpine//' \
    | sort -t. -k1,1n -k2,2n \
    | tail -1
}

cur_pgvector="$(jq -r '.pgvector' "$MANIFEST")"
new_pgvector="$(latest_pgvector)"
[ -n "$new_pgvector" ] || { echo "error: could not resolve latest pgvector tag" >&2; exit 1; }

changed=0
summary=""

if [ "$new_pgvector" != "$cur_pgvector" ]; then
  changed=1
  summary+="- pgvector: \`${cur_pgvector}\` → \`${new_pgvector}\`"$'\n'
fi

# Build the new digest + alpine-version maps and detect per-major drift.
digest_args=()
alpine_args=()
for major in $MAJORS; do
  cur="$(jq -r --arg m "$major" '.alpine_digests[$m]' "$MANIFEST")"
  new="$(alpine_digest "$major")"
  [ -n "$new" ] || { echo "error: could not resolve digest for postgres:${major}-alpine" >&2; exit 1; }

  cur_av="$(jq -r --arg m "$major" '.alpine_versions[$m] // ""' "$MANIFEST")"
  new_av="$(alpine_version "$major")"
  [ -n "$new_av" ] || { echo "error: could not resolve alpine version for postgres:${major}-alpine" >&2; exit 1; }

  if [ "$new" != "$cur" ]; then
    changed=1
    if [ "$new_av" != "$cur_av" ]; then
      summary+="- postgres:${major}-alpine: digest \`${cur:0:19}…\` → \`${new:0:19}…\` (alpine ${cur_av:-?} → ${new_av})"$'\n'
    else
      summary+="- postgres:${major}-alpine: digest \`${cur:0:19}…\` → \`${new:0:19}…\` (alpine ${new_av})"$'\n'
    fi
  fi
  digest_args+=(--arg "d${major}" "$new")
  alpine_args+=(--arg "a${major}" "$new_av")
done

if [ "$changed" -eq 0 ]; then
  echo "no upstream drift — manifest.json is current"
  exit 0
fi

# Rewrite manifest.json atomically.
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
tmp="$(mktemp)"
jq \
  --arg pgvector "$new_pgvector" \
  --arg now "$now" \
  "${digest_args[@]}" \
  "${alpine_args[@]}" \
  '
  .pgvector = $pgvector
  | .last_checked_utc = $now
  | .alpine_digests."15" = $d15
  | .alpine_digests."16" = $d16
  | .alpine_digests."17" = $d17
  | .alpine_digests."18" = $d18
  | .alpine_versions."15" = $a15
  | .alpine_versions."16" = $a16
  | .alpine_versions."17" = $a17
  | .alpine_versions."18" = $a18
  ' "$MANIFEST" > "$tmp"
mv "$tmp" "$MANIFEST"

# Re-render the variant Dockerfiles from the updated manifest.
"${REPO_ROOT}/scripts/render-dockerfiles.sh" >/dev/null

echo "UPSTREAM DRIFT DETECTED"
echo
echo "$summary"
exit 10
