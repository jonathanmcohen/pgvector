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
  (`last_checked_utc`), and which major `:latest` points at (`latest_alias_target`).
  The pgvector and last-checked badges at the top of this page read it live.
- The [latest release](https://github.com/jonathanmcohen/pgvector/releases/latest) is
  named `<date>-pgvector<version>` and is cut on every published bump.
- The [GHCR package page](https://github.com/jonathanmcohen/pgvector/pkgs/container/pgvector)
  lists every published tag, including the exact Postgres patch (`:{major}.{patch}-{pgvector}`).

| PG major | Moving tag | Pinned tag | Arch |
|---|---|---|---|
| 15 | `ghcr.io/jonathanmcohen/pgvector:15` | `:15-<pgvector>` | amd64, arm64 |
| 16 | `ghcr.io/jonathanmcohen/pgvector:16` | `:16-<pgvector>` | amd64, arm64 |
| 17 | `ghcr.io/jonathanmcohen/pgvector:17` | `:17-<pgvector>` | amd64, arm64 |
| 18 | `ghcr.io/jonathanmcohen/pgvector:18` | `:18-<pgvector>` | amd64, arm64 |

To print the pgvector version currently published from `main`:

```bash
curl -fsSL https://raw.githubusercontent.com/jonathanmcohen/pgvector/main/manifest.json | jq -r .pgvector
```

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

Pinned tags narrow what can change, but they are not frozen. Every publish re-applies
`:{major}-{pgvector}` and `:{major}.{patch}-{pgvector}` to the new build. So
`:17-0.8.6` moves to a new Postgres 17 patch, and both forms move to a new image when
the Alpine base digest changes. To freeze an exact image, pin by digest
(`ghcr.io/jonathanmcohen/pgvector@sha256:...`).

## How it works

```
 daily cron -> check-upstream.sh -> drift? -> bump manifest.json + re-render variants
                                       |                     |
                                       | no                  v
                                       v            bot/upstream-bump-<date> branch
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

## Repo layout

```
Dockerfile.template     parameterised base for all variants
manifest.json           source of truth: pgvector version + alpine digests
scripts/                check-upstream, render-dockerfiles, smoke-test
variants/{15..18}/      generated Dockerfiles (do not hand-edit)
examples/               docker-compose consumer example
.github/workflows/      CI: build-and-publish, check-upstream, release, auto-merge
```

## License

[MIT](./LICENSE). Copyright (c) 2026 Jonathan Cohen. Postgres and pgvector retain their own licenses.
