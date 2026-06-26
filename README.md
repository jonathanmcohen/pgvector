# pgvector on Alpine

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)
[![build-and-publish](https://github.com/jonathanmcohen/pgvector/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/jonathanmcohen/pgvector/actions/workflows/build-and-publish.yml)
[![check-upstream](https://github.com/jonathanmcohen/pgvector/actions/workflows/check-upstream.yml/badge.svg)](https://github.com/jonathanmcohen/pgvector/actions/workflows/check-upstream.yml)
[![GHCR](https://img.shields.io/badge/ghcr.io-jonathanmcohen%2Fpgvector-blue?logo=docker)](https://github.com/jonathanmcohen/pgvector/pkgs/container/pgvector)

**Postgres on Alpine with [pgvector](https://github.com/pgvector/pgvector) pre-installed. Auto-updated daily from upstream.**

Multi-arch (`linux/amd64` + `linux/arm64`) images for Postgres **15, 16, 17, 18**, each built on `postgres:<major>-alpine` with pgvector compiled from source and pinned by Docker Hub digest. When either upstream (the Postgres alpine base or pgvector) releases, a bot opens a PR, the image is smoke-tested, and — if green — it auto-merges and republishes. No human in the loop.

## Image matrix

Current source of truth: [`manifest.json`](./manifest.json) — **pgvector `0.8.3`**, last checked `2026-06-26`.

| PG major | Moving tag | Pinned (recommended) | Arch | Alpine | pgvector |
|---|---|---|---|---|---|
| 15 | `ghcr.io/jonathanmcohen/pgvector:15` | `:15-0.8.3` | amd64, arm64 | 3.24 | 0.8.3 |
| 16 | `ghcr.io/jonathanmcohen/pgvector:16` | `:16-0.8.3` | amd64, arm64 | 3.24 | 0.8.3 |
| 17 | `ghcr.io/jonathanmcohen/pgvector:17` | `:17-0.8.3` | amd64, arm64 | 3.24 | 0.8.3 |
| 18 | `ghcr.io/jonathanmcohen/pgvector:18` | `:18-0.8.3` | amd64, arm64 | 3.24 | 0.8.3 |

> Alpine version is informational — the real lock is the pinned base-image digest in
> [`manifest.json`](./manifest.json). Bare `<major>-alpine` tracks the latest Alpine; an
> Alpine rebase changes the digest, which triggers an automatic bump.

`ghcr.io/jonathanmcohen/pgvector:latest` aliases the current stable major (**17** today; bumps to 18 ~30 days after upstream PG 18 GA).

### Tag scheme

| Tag form | Example | Meaning |
|---|---|---|
| `:{major}` | `:17` | latest pgvector on the latest patch of that major (moving) |
| `:{major}-{pgvector}` | `:17-0.8.3` | major + pinned pgvector (recommended for production) |
| `:{major}.{patch}-{pgvector}` | `:17.5-0.8.3` | fully pinned: exact PG patch + pgvector |
| `:latest` | — | alias of the current stable major |

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

Single major — [`examples/docker-compose.yml`](./examples/docker-compose.yml):

```bash
docker compose -f examples/docker-compose.yml up -d
docker compose -f examples/docker-compose.yml exec db \
  psql -U postgres -d app -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

All four majors side by side (ports `5415`–`5418`) —
[`examples/docker-compose.all-majors.yml`](./examples/docker-compose.all-majors.yml):

```bash
docker compose -f examples/docker-compose.all-majors.yml up -d
# psql straight in on the matching host port:
psql -h localhost -p 5418 -U postgres -d app -c "CREATE EXTENSION IF NOT EXISTS vector;"  # PG 18
```

## Pinning recommendation

Production deployments should pin **fully** — `:17-0.8.3` (or `:17.5-0.8.3`) — not the
moving `:17` tag. The moving tags advance automatically as upstream releases; a
pinned tag never changes under you. Pinned tags are immutable once published.

## How it works

```
 daily cron ─► check-upstream.sh ─► drift? ─► bump manifest.json + re-render variants
                                       │                     │
                                       │ no                  ▼
                                       ▼            bot/upstream-bump-<date> branch
                                    exit 0                    │
                                                              ▼
                                                  PR  "chore: bump postgres/pgvector"
                                                              │
                                                  build + multi-arch + SMOKE TEST
                                                              │  (green)
                                                              ▼
                                                  auto-merge (squash) ─► publish to GHCR
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
scripts/                check-upstream · render-dockerfiles · smoke-test
variants/{15..18}/      generated Dockerfiles (do not hand-edit)
examples/               docker-compose consumer example
.github/workflows/      CI: build-and-publish · check-upstream · release · auto-merge
```

## License

[MIT](./LICENSE) © 2026 Jonathan Cohen. Postgres and pgvector retain their own licenses.
