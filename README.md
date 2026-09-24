# pgvector on Alpine

[![build-and-publish](https://github.com/jonathanmcohen/pgvector/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/jonathanmcohen/pgvector/actions/workflows/build-and-publish.yml)
[![check-upstream](https://github.com/jonathanmcohen/pgvector/actions/workflows/check-upstream.yml/badge.svg)](https://github.com/jonathanmcohen/pgvector/actions/workflows/check-upstream.yml)
[![pgvector](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjonathanmcohen%2Fpgvector%2Fmain%2Fmanifest.json&query=%24.pgvector&label=pgvector&color=blue)](https://github.com/pgvector/pgvector/releases)
[![last upstream check](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjonathanmcohen%2Fpgvector%2Fmain%2Fmanifest.json&query=%24.last_checked_utc&label=last%20checked)](https://github.com/jonathanmcohen/pgvector/actions/workflows/check-upstream.yml)
[![latest release](https://img.shields.io/github/v/release/jonathanmcohen/pgvector?label=release&sort=date)](https://github.com/jonathanmcohen/pgvector/releases/latest)
[![GHCR](https://img.shields.io/badge/ghcr.io-jonathanmcohen%2Fpgvector-blue?logo=docker)](https://github.com/jonathanmcohen/pgvector/pkgs/container/pgvector)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

**Postgres on Alpine with [pgvector](https://github.com/pgvector/pgvector) pre-installed. Auto-updated daily from upstream.**

Multi-arch (`linux/amd64` + `linux/arm64`) images for Postgres **15, 16, 17, 18**, each built on `postgres:<major>-alpine` with pgvector compiled from source and pinned by Docker Hub digest. When either upstream (the Postgres alpine base or pgvector) releases, a bot opens a PR, the image is smoke-tested, and, if green, it auto-merges and republishes. No human in the loop.

## Image matrix

This table lists only what stays the same from one bump to the next. The version
numbers change with every upstream bump, so they are not written here. Read them from
these sources:

- [`manifest.json`](./manifest.json) is the source of truth. It holds the pgvector
  version (`pgvector`), the pinned base-image digest and informational Alpine version
  per major (`alpine_digests`, `alpine_versions`), the time of the last upstream check
  that found drift (`last_checked_utc`; a check that finds nothing new does not update
  it), and which major `:latest` points at (`latest_alias_target`).
  The pgvector and last-checked badges at the top of this page read it live.
- The [latest release](https://github.com/jonathanmcohen/pgvector/releases/latest) is
  named `<date>-pgvector<version>`, with a `.1`, `.2`, ... suffix for a repeat on the
  same UTC day. A release is cut after a successful publish from `main` whenever the
  published commit changed `manifest.json`. That covers upstream bumps, but also
  manifest-only changes such as moving `:latest`, so a new release does not always
  mean new versions.
- The [GHCR package page](https://github.com/jonathanmcohen/pgvector/pkgs/container/pgvector)
  lists every published tag, including the Postgres patch tags (`:{major}.{patch}-{pgvector}`).

| PG major | Moving tag | Pinned tag | Arch |
|---|---|---|---|
| 15 | `ghcr.io/jonathanmcohen/pgvector:15` | `:15-<pgvector>` | amd64, arm64 |
| 16 | `ghcr.io/jonathanmcohen/pgvector:16` | `:16-<pgvector>` | amd64, arm64 |
| 17 | `ghcr.io/jonathanmcohen/pgvector:17` | `:17-<pgvector>` | amd64, arm64 |
| 18 | `ghcr.io/jonathanmcohen/pgvector:18` | `:18-<pgvector>` | amd64, arm64 |

To print the pgvector version in `manifest.json` on `main`:

```bash
curl -fsSL https://raw.githubusercontent.com/jonathanmcohen/pgvector/main/manifest.json | jq -r .pgvector
```

GHCR can lag behind `main`. The bot merges a bump to `main` first and publishes
afterwards, so if the last build-and-publish run failed (see the badge at the top),
GHCR can still be on the previous version.

> The Alpine version is informational. The real lock is the pinned base-image digest in
> [`manifest.json`](./manifest.json). Bare `<major>-alpine` tracks the latest Alpine; an
> Alpine rebase changes the digest, which triggers an automatic bump.

`ghcr.io/jonathanmcohen/pgvector:latest` aliases the current stable major: **18** (previously 17; set by `latest_alias_target` in [`manifest.json`](./manifest.json)).
If you ran `:latest` on PG 17 with persistent data, pin `:17` instead: a PG 17 data directory
will not start under PG 18, and PG 18's image keeps PGDATA at `/var/lib/postgresql/18/docker`
rather than `/var/lib/postgresql/data`.
For a new PG 18 volume, mount `/var/lib/postgresql`, not `/var/lib/postgresql/data`: the PG 18
entrypoint refuses to start when `.../data` is itself a mount.

### Tag scheme

Example tags below are real published tags; newer ones may exist.

| Tag form | Example | Meaning |
|---|---|---|
| `:{major}` | `:17` | latest pgvector on the latest patch of that major (moving) |
| `:{major}-{pgvector}` | `:17-0.8.6` | major + pinned pgvector (recommended for production) |
| `:{major}.{patch}-{pgvector}` | `:17.11-0.8.6` | exact PG patch + pgvector |
| `:latest` | `:latest` | alias of the current stable major |

## Usage

```bash
docker run --name pg -e POSTGRES_PASSWORD=secret -p 5432:5432 -d \
  ghcr.io/jonathanmcohen/pgvector:17

psql -h localhost -U postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

```sql
CREATE TABLE items (id serial PRIMARY KEY, embedding vector(3));
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
SELECT id, embedding <-> '[3,1,2]' AS dist FROM items ORDER BY dist LIMIT 5;
```

### docker compose

Single major, [`examples/docker-compose.yml`](./examples/docker-compose.yml):

```bash
docker compose -f examples/docker-compose.yml up -d
docker compose -f examples/docker-compose.yml exec db \
  psql -U postgres -d app -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

All four majors side by side (ports `5415` to `5418`),
[`examples/docker-compose.all-majors.yml`](./examples/docker-compose.all-majors.yml):

```bash
docker compose -f examples/docker-compose.all-majors.yml up -d
# psql straight in on the matching host port:
psql -h localhost -p 5418 -U postgres -d app -c "CREATE EXTENSION IF NOT EXISTS vector;"  # PG 18
```

## Pinning recommendation

Production deployments should pin a pgvector version, for example `:17-0.8.6` (or
`:17.11-0.8.6`), not the moving `:17` tag. The moving tags advance automatically as
upstream releases.

Pinned tags narrow what can change, but they are not frozen. Every publish rebuilds
every major and moves both `:{major}-{pgvector}` and the current patch's
`:{major}.{patch}-{pgvector}` to the new build, which gets a new digest. That happens
on any publish, not only on an upstream bump. A CI or script change merged to `main`,
a manual re-run of the workflow, and a change that only moves `:latest` can all
trigger one. On top of that, `:17-0.8.6` moves to a new Postgres 17 patch when one
ships.

A new digest does not always mean new contents. The build steps in
`.github/workflows/build-and-publish.yml` use the GitHub Actions build cache
(`cache-from: type=gha`, one cache per major and arch). The cache follows each arch's
own base image, not the multi-arch index digest that `manifest.json` records. While
that per-arch base image, the pgvector version and the Dockerfile build steps are
unchanged and the cache entry still exists, the build reuses the cached layers. The
images inside are then byte-identical to the previous publish, and only the build
attestations change. That includes a bump that moves only the index digest: the
2026-09-21 bump (#23) moved all four digests in `manifest.json`, and all four majors
published byte-identical images. The contents change when one of those inputs changes,
or when the cache misses (for example, after GitHub evicts the entry). On a miss the
build re-runs `apk upgrade` (see `Dockerfile.template`) and picks up whatever Alpine
packages are current at that moment, so the contents can change even with the same
Postgres patch and base image. A publish with a warm cache, including a bot bump, does
not pick up new Alpine fixes.

Pinning by digest (`ghcr.io/jonathanmcohen/pgvector@sha256:...`) fixes the image
contents, but old digests are not guaranteed to stay pullable. Once a publish moves
every tag off an image, no tag references it any more, and those are the images the
maintainer's cleanup script (`scripts/prune-ghcr.sh --apply`) deletes. After a prune,
a digest pin to a superseded image fails to pull. If you need an image you can always
pull again, copy it to a registry you control and pin that copy.

## How it works

```
 daily cron -> check-upstream.sh -> drift? -> bump manifest.json + re-render variants
                                       |                     |
                                       | no                  v
                                       v            bot/upstream-bump branch
                                    exit 0                    |
                                                              v
                                                  PR  "chore: bump postgres/pgvector"
                                                              |
                                                  build + multi-arch + SMOKE TEST
                                                              |  (green)
                                                              v
                                                  auto-merge (squash) -> publish to GHCR
```

- **`scripts/render-dockerfiles.sh`** generates `variants/<major>/Dockerfile` from
  [`Dockerfile.template`](./Dockerfile.template) + `manifest.json`. Generated files are
  committed so every published image is reproducible from the repo.
- **`scripts/check-upstream.sh`** resolves the latest pgvector tag (the project ships
  lightweight git tags, not GitHub Releases) and the current `postgres:<major>-alpine`
  multi-arch digests, rewriting `manifest.json` on drift.
- **`scripts/smoke-test.sh`** boots each built image and runs `CREATE EXTENSION vector`
  plus an L2-distance query before any publish. **No smoke = no push.**

## Issue / failure policy

Bot-opened bump PRs auto-merge only when CI is green. A failed bump (build or
smoke-test failure) opens a GitHub Issue tagging the maintainer instead of merging.
Humans close those Issues after fixing the root cause. All bot changes are auditable
in PR history.

## Maintenance

A push to `main` republishes all four majors (new digests, signatures and SBOMs,
plus a release when `manifest.json` changed) unless every file it touches is in the
`paths-ignore` list of
[`build-and-publish.yml`](./.github/workflows/build-and-publish.yml): `**.md`,
`examples/**`, `LICENSE`, `.github/dependabot.yml`. Edits under `.github/workflows/`
or `scripts/` are not on that list.

- **Use `[skip ci]` when a change should not republish.** Put it in the squash-merge
  subject of any PR that changes no image content, such as action bumps (except the
  two below), workflow edits and script fixes. GitHub skips push-triggered workflows
  for a commit whose message contains it.
- **Dependabot adds it, but check it.** [`.github/dependabot.yml`](./.github/dependabot.yml)
  groups the action updates from a weekly run into one PR and prefixes the commit and
  the PR title with `ci: [skip ci] `. The squash subject comes from the commit when the
  PR has one commit and from the PR title when it has more, so it should carry the
  marker either way. Dependabot drops a prefix without warning if building it fails,
  so before you squash-merge, confirm `[skip ci]` is in the squash subject, and add it
  if it is missing. Do not remove it from a Dependabot PR.
- **Exception: `sigstore/cosign-installer` and `anchore/sbom-action` are manual
  bumps.** Both run in `build-and-publish` only after the tags are moved, so a new
  version must be proven by a publish you watch, not first run unattended on the next
  upstream bump, where a failure would leave the new tags unsigned or without an SBOM
  attestation. Dependabot cannot set a prefix per dependency, so the config ignores
  both, and Dependabot never opens a PR for either. Their new releases are surfaced by
  the tag-pin sweep in the maintainer's Upstream Version Watch
  (`gh api repos/<owner>/<action>/releases/latest --jq .tag_name`). To bump one:
  - Move its `uses:` pin to the exact release tag in a PR of its own and merge it
    WITHOUT `[skip ci]`. Remove the marker from the whole squash message, subject AND
    body: GitHub skips on the marker anywhere in the message, and the squash body
    lists every commit message in the PR.
  - Watch the publish that merge starts: `Cosign sign (keyless)`, `Generate SBOM` and
    `Attest SBOM` must pass for all four majors, and each new index must carry its
    `.sig` and `.att` tags. (cosign-installer v4 installs cosign v3, which writes a
    new bundle format; for that upgrade check with `cosign verify` and
    `cosign verify-attestation` instead of looking for the tags.)
- **A skipped action bump runs on the next publish**: the next upstream bump that
  `check-upstream` merges, or a manual run of `build-and-publish`.
- **Leave the marker off when you want the republish**, for example a change to
  `manifest.json`, `Dockerfile.template` or `variants/`.

## Repo layout

```
Dockerfile.template     parameterised base for all variants
manifest.json           source of truth: pgvector version + alpine digests
scripts/                check-upstream, render-dockerfiles, smoke-test
variants/{15..18}/      generated Dockerfiles (do not hand-edit)
examples/               docker-compose consumer example
.github/workflows/      build-and-publish.yml (build, smoke, publish; release is a job in it)
                        check-upstream.yml (daily drift check, bump PR, auto-merge)
```

## License

[MIT](./LICENSE). Copyright (c) 2026 Jonathan Cohen. Postgres and pgvector retain their own licenses.
