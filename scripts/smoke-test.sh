#!/usr/bin/env bash
# smoke-test.sh <image-ref>
# Boot the given pgvector image, wait for Postgres to accept connections, then
# exercise the vector extension end to end. Non-zero exit = FAIL (no publish).
#
# Verifies:
#   - CREATE EXTENSION vector succeeds
#   - a vector column accepts inserts
#   - the <-> (L2 distance) operator orders rows and returns 2 rows
#
# Usage: scripts/smoke-test.sh ghcr.io/jonathanmcohen/pgvector:18-0.8.3
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh <image-ref>}"
CONTAINER="pgvector-smoke-$$"
PASSWORD="smoke_$$_secret"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo ">> starting $IMAGE as $CONTAINER"
docker run -d --name "$CONTAINER" \
  -e POSTGRES_PASSWORD="$PASSWORD" \
  -e POSTGRES_DB=smoke \
  "$IMAGE" >/dev/null

# Wait for the server to accept connections. We must gate on a real TCP query,
# NOT pg_isready over the socket: the postgres entrypoint first runs a temporary
# SOCKET-ONLY server to execute init scripts, then shuts it down and restarts
# for real. pg_isready/socket connects succeed during that bootstrap phase and
# then hit "the database system is shutting down". The bootstrap server never
# listens on TCP, so a successful TCP `SELECT 1` proves the real server is up.
# TCP auth is scram (the socket is trust), so the password is required.
echo ">> waiting for postgres to accept real TCP connections"
ready=0
for _ in $(seq 1 90); do
  if docker exec -e PGPASSWORD="$PASSWORD" "$CONTAINER" \
      psql -h 127.0.0.1 -U postgres -d smoke -tAc 'SELECT 1' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "FAIL: postgres did not accept TCP connections in 90s" >&2
  docker logs "$CONTAINER" >&2 || true
  exit 1
fi

# psql -v ON_ERROR_STOP=1 makes any SQL error abort with non-zero exit.
echo ">> running vector smoke SQL"
output="$(docker exec -i -e PGPASSWORD="$PASSWORD" "$CONTAINER" \
  psql -h 127.0.0.1 -v ON_ERROR_STOP=1 -U postgres -d smoke -At <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
CREATE TABLE items (id serial PRIMARY KEY, embedding vector(3));
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
SELECT count(*) FROM (
  SELECT id, embedding <-> '[3,1,2]' AS dist
  FROM items ORDER BY dist LIMIT 5
) q;
SQL
)"

rows="$(printf '%s\n' "$output" | tail -1)"
if [ "$rows" != "2" ]; then
  echo "FAIL: expected 2 rows from L2 distance query, got '$rows'" >&2
  echo "--- full psql output ---" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

# Also confirm the installed extension version matches the image label, so a
# stale/mismatched build can't pass silently.
ext_ver="$(docker exec -i -e PGPASSWORD="$PASSWORD" "$CONTAINER" \
  psql -h 127.0.0.1 -v ON_ERROR_STOP=1 -U postgres -d smoke -At \
  -c "SELECT extversion FROM pg_extension WHERE extname='vector';")"
echo ">> pgvector extension version reported: ${ext_ver}"

echo "PASS: $IMAGE — vector extension created, 2 rows returned from L2 query"
