#!/usr/bin/env bash
set -euo pipefail

# Captures byte-stable JSON responses from the running Rails app for use as
# regression fixtures against Phoenix. Run with the Rails app and its sidecars up.
#
# Usage (from the atlas repo root):
#   (cd app && bin/rails server) &
#   bash app-phoenix/scripts/capture_rails_goldens.sh http://localhost:3000

RAILS_BASE="${1:-http://localhost:3000}"
OUT_DIR="$(dirname "$0")/../test/fixtures/goldens"
mkdir -p "$OUT_DIR"

capture() {
  local name="$1" method="$2" path="$3" body="${4:-}"
  if [[ "$method" == "GET" ]]; then
    curl -s -G "$RAILS_BASE$path" | jq -S . > "$OUT_DIR/$name.json"
  else
    curl -s -X "$method" -H "content-type: application/json" -d "$body" "$RAILS_BASE$path" | jq -S . > "$OUT_DIR/$name.json"
  fi
  echo "captured $name"
}

capture "search-berlin"          GET  "/api/v1/search?q=berlin&limit=5"
capture "search-with-bbox"       GET  "/api/v1/search?q=cafe&limit=10&bbox=13.0,52.0,14.0,53.0"
capture "reverse-brandenburg"    GET  "/api/v1/reverse?lat=52.5163&lon=13.3777"
capture "reverse-batch-two"      POST "/api/v1/reverse/batch" '{"coords":[{"lat":52.5,"lon":13.4},{"lat":48.1,"lon":11.5}]}'
capture "route-auto"             GET  "/api/v1/route?from=52.5,13.4&to=52.6,13.5&mode=auto"
capture "transit-default"        GET  "/api/v1/transit?from=52.5,13.4&to=52.6,13.5"
capture "whats-here-default"     GET  "/api/v1/whats-here?lat=52.5&lon=13.4"
capture "pois-food"              GET  "/api/v1/pois?lat=52.5&lon=13.4&radius=300&category=food"
capture "pois-categories"        GET  "/api/v1/pois/categories"
capture "geocode-berlin"         GET  "/api/v1/geocode?q=berlin"
