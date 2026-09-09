#!/bin/sh
set -eu
trap 'code=$?; if [ "$code" -ne 0 ]; then echo "MOTIS error: import or startup failed" >&2; fi' EXIT
mkdir -p /data
if [ ! -s /input/region.osm.pbf ]; then
  echo 'MOTIS error: no street data. Select a region and apply it in Settings.' >&2
  exit 1
fi
set -- /input/*.gtfs.zip
if [ ! -f "$1" ] && [ ! -f /input/motis-datasets.yml ]; then
  echo 'MOTIS error: no GTFS timetable. Select a region with transit feeds.' >&2
  exit 1
fi
# Date is refreshed on restart; MOTIS reuses unchanged street artifacts.
cat > /data/config.yml <<EOF
server:
  host: 0.0.0.0
  port: 8080
  web_folder: /ui
  n_threads: ${MOTIS_THREADS:-4}
osm: /input/region.osm.pbf
street_routing: true
osr_footpath: true
geocoding: false
reverse_geocoding: false
timetable:
  first_day: $(date -u +%Y-%m-%d)
  num_days: 365
  with_shapes: true
EOF
if [ -f /input/motis-datasets.yml ]; then
  cat /input/motis-datasets.yml >> /data/config.yml
else
  printf '  datasets:\n' >> /data/config.yml
index=0
for feed in /input/*.gtfs.zip; do
  index=$((index + 1))
  # JSON quoting is also YAML quoting; reject uncommon filename characters.
  case "$feed" in *'"'*|*'\'*|*'
'*) echo 'MOTIS error: unsupported GTFS filename' >&2; exit 1;; esac
  printf '    feed%s:\n      path: "%s"\n' "$index" "$feed" >> /data/config.yml
done
fi
printf 'logging:\n  log_level: info\n' >> /data/config.yml
echo 'MOTIS importing street network and timetables'
/motis import --config /data/config.yml --data /data
/motis server --data /data &
server_pid=$!
trap 'trap - EXIT; kill "$server_pid" 2>/dev/null || true; wait "$server_pid" || true; exit 0' INT TERM
# Only declare readiness after the HTTP API answers, not merely after import.
while kill -0 "$server_pid" 2>/dev/null; do
  if wget -q -T 2 -O /dev/null http://127.0.0.1:8080/api/v1/map/initial; then
    echo 'MOTIS ready'
    break
  fi
  sleep 1
done
wait "$server_pid"
