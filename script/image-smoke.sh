#!/usr/bin/env bash
# Test a built release with fresh data on the architecture that will run it.
set -euo pipefail
image=$1
revision=$2
name=atlas-image-smoke
trap 'docker logs "$name"; docker rm -f "$name" >/dev/null' EXIT
docker run -d --name "$name" -e PHX_SCHEME=http -p 127.0.0.1::4000 "$image"
port=$(docker port "$name" 4000/tcp | sed 's/.*://')
for attempt in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$port/up" >/dev/null; then break; fi
  sleep 1
done
curl -fsS "http://127.0.0.1:$port/" >/dev/null
curl -fsS "http://127.0.0.1:$port/api/v1/version" > /tmp/atlas-version.json
version=$(sed -n 's/.*version: "\([^"]*\)".*/\1/p' app-phoenix/mix.exs | head -1)
jq -e --arg version "$version" --arg revision "${revision:0:7}" '.data.version == $version and .data.revision == $revision' /tmp/atlas-version.json
docker exec "$name" /app/bin/docker-entrypoint docker compose version --short
docker exec "$name" /app/bin/docker-entrypoint sh -c 'test "$(id -u)" != 0; test -s /data/.secret_key_base; test -s /data/atlas.sqlite3'
