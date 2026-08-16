#!/usr/bin/env bash
# prune-ghcr.sh
# Delete orphaned GHCR versions for the pgvector package, keeping everything that
# any live tag still references.
#
# Why this is needed: builds are not bit-reproducible, so every same-version
# republish mints new digests and strands the previous ones. The package
# accumulates untagged versions indefinitely.
#
# Why it is NOT wired into CI: deleting versions of a USER-scoped package hits
# /user/packages/... which requires a user token carrying delete:packages.
# GITHUB_TOKEN cannot do it, and adding a PAT would violate the token-only
# constraint (E7). So this is run by hand:
#
#   gh auth refresh -h github.com -s read:packages,delete:packages
#   scripts/prune-ghcr.sh            # dry run, prints what WOULD go
#   scripts/prune-ghcr.sh --apply    # actually delete
#
# DANGER this script exists to avoid: GitHub's "delete untagged versions" button
# removes the per-arch CHILD manifests of a multi-arch image. They are untagged
# but referenced by the tagged index, so deleting them breaks the published tags.
# The keep-set below is built from what each tag actually references.
#
# STATUS 2026-08-16: --apply has been run for real against this package once,
# AT 36 ORPHANS, deleting 36 versions with 0 failures. Read that as "validated at
# 36 orphans", not "validated end-to-end" - a review immediately afterwards found
# two defects the run was too small to reach, both now fixed below. What the run
# does cover:
#
#   1. The orphan set was recomputed independently, without using this script's
#      keep-set logic: list every untagged version from the API, list every child
#      digest referenced by every real-tagged index via
#      `imagetools inspect --raw <image>@<digest>`, and subtract. Both methods
#      produced the same 36 digests, diff empty.
#   2. Of 116 untagged versions, 80 were child manifests of live tag indexes.
#      That is the danger in the header, measured: GitHub's "delete untagged"
#      button would have broken 80 manifests behind published tags.
#   3. All 41 real tags were resolved with `imagetools inspect` after the delete.
#      0 broken.
#
# TWO DEFECTS FOUND BY REVIEW ON 2026-08-16, BOTH FIXED HERE, both invisible at
# 36 orphans:
#
#   a. The child-manifest lookup used to end in `2>/dev/null || true`. A rate
#      limit or network blip therefore produced an empty child list and dropped
#      that tag's live manifests out of the keep-set, reporting them as orphans.
#      It now aborts the run instead. A prune script must fail closed.
#   b. `head -40` under `set -o pipefail` returns 141 once jq's output exceeds the
#      pipe buffer, and `set -e` then killed the script before --apply. Only
#      reachable above roughly 40 orphans, which is why the 36-orphan run passed.
#
# A CHECK THIS SCRIPT STILL DOES NOT MAKE, and you should: an untagged digest can
# be orphaned on GHCR and still be the image a container is running right now.
# Deleting it means that container can never be re-pulled. Before --apply, collect
# the RepoDigests of anything running the image and confirm none appear in the
# orphan list:
#
#   docker inspect <container> --format '{{range .RepoDigests}}{{.}}{{end}}'
#
# On 2026-08-16 `parchment-db` on Carin was running sha256:ed54f8cc..., which was
# still tagged 17.10-0.8.3 and therefore safe. That was luck, not design.
#
# Exit codes: 0 ok, 1 error.

set -euo pipefail

OWNER="${OWNER:-jonathanmcohen}"
PACKAGE="${PACKAGE:-pgvector}"
IMAGE="ghcr.io/${OWNER}/${PACKAGE}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker (with buildx) is required" >&2; exit 1; }

echo "==> Collecting versions for ${IMAGE}"
versions_json="$(gh api "/users/${OWNER}/packages/container/${PACKAGE}/versions?per_page=100" --paginate)"
total="$(echo "$versions_json" | jq -s 'add | length')"
echo "    ${total} versions on GHCR"

tags="$(echo "$versions_json" | jq -sr 'add | .[].metadata.container.tags[]?' | sort -u)"
echo "    $(echo "$tags" | grep -c . || true) tags live"

# Keep-set: every digest any live tag resolves to, plus every manifest that index
# references, including the unknown/unknown buildx attestation manifests.
#
# The cosign .sig/.att names are pushed into the keep-set below but nothing ever
# matches against them. Those objects survive because they CARRY TAGS, and the
# orphan filter only ever considers versions with zero tags. Do not read the
# keep-set as the thing protecting them.
#
# The index digest is taken from the GHCR API itself (version .name), NOT computed
# locally: `imagetools inspect --raw` normalises the JSON, so sha256sum of its
# output does NOT match the registry's stored digest. Computing it that way marks
# live indexes as orphans and would delete published tags.
echo "==> Building keep-set from what each tag references"
keep=""

# tagged versions: the digest is authoritative from the API
while IFS=$'\t' read -r digest tagcsv; do
  [ -z "$digest" ] && continue
  keep="${keep}${digest}
"
  idxhex="${digest#sha256:}"
  keep="${keep}sha256-${idxhex}.sig
sha256-${idxhex}.att
"
  first_tag="${tagcsv%%,*}"
  [ -z "$first_tag" ] && continue
  # This lookup MUST fail loudly. It used to end in `2>/dev/null || true`, which
  # meant a rate limit, an expired token or a network blip produced an empty
  # `children` and silently dropped that tag's live child manifests out of the
  # keep-set - so they were reported as orphans and, under --apply, deleted.
  # One simulated transient failure on :17.11-0.8.6 turned "0 orphaned versions"
  # into 4, and those 4 were the manifests backing :17, :17-0.8.6 and :latest.
  # A prune script that fails open is worse than no prune script.
  if ! raw="$(docker buildx imagetools inspect --raw "${IMAGE}:${first_tag}")"; then
    echo "FATAL: could not inspect ${IMAGE}:${first_tag}." >&2
    echo "       Aborting rather than treating its children as orphans." >&2
    exit 1
  fi
  children="$(printf '%s' "$raw" | jq -r '.manifests[]?.digest // empty')"
  [ -n "$children" ] && keep="${keep}${children}
"
done < <(echo "$versions_json" | jq -sr 'add | .[] | select((.metadata.container.tags|length)>0)
          | [.name, (.metadata.container.tags|join(","))] | @tsv')

keep="$(printf '%s' "$keep" | sort -u)"
echo "    $(printf '%s' "$keep" | grep -c . || true) digests/objects protected"

# Anything whose name (digest) and tags are both outside the keep-set is orphaned.
echo "==> Determining orphans"
orphans="$(echo "$versions_json" | jq -s --arg keep "$keep" '
  ($keep | split("\n") | map(select(length>0))) as $k
  | add
  | map(select(
      (.name as $n | ($k | index($n)) | not)
      and ((.metadata.container.tags // []) | length) == 0
    ))
  | map({id, name, created: .created_at[0:10]})')"

count="$(echo "$orphans" | jq 'length')"
echo "    ${count} orphaned versions"

if [ "$count" -eq 0 ]; then echo "==> Nothing to prune."; exit 0; fi
# `|| true` is required: under `set -o pipefail`, `head -40` closes the pipe once
# it has its 40 lines, jq dies on SIGPIPE, and the pipeline returns 141. With
# `set -e` that killed the whole script before it ever reached --apply. It only
# bites when jq's output exceeds the pipe buffer, so it never fired during the
# 36-orphan validation run - reproduced at 500 and 5000 orphans, survived at 100.
echo "$orphans" | jq -r '.[] | "    \(.created)  \(.name[0:24])"' | head -40 || true
[ "$count" -gt 40 ] && echo "    ... and $((count-40)) more"

if [ "$APPLY" -eq 0 ]; then
  echo
  echo "==> DRY RUN. Re-run with --apply to delete these ${count} versions."
  exit 0
fi

echo "==> Deleting ${count} versions"
fail=0
while IFS= read -r id; do
  gh api -X DELETE "/user/packages/container/${PACKAGE}/versions/${id}" >/dev/null 2>&1 \
    || { echo "    FAILED id=${id}" >&2; fail=$((fail+1)); }
done < <(echo "$orphans" | jq -r '.[].id')
echo "==> Done. ${fail} failures."
[ "$fail" -eq 0 ] || exit 1
