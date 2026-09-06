# MOTIS comparison prototype

Isolated MOTIS 2.11.2 service for comparing Berlin/VBB routing with the existing
Atlas OTP service. This experiment does not switch Atlas to MOTIS. Its input
mount is read-only and its graph is stored separately. No real-time feeds are
configured; route requests use locally imported data.

The image is pinned to the official multi-platform release digest. The tested
host was Apple Silicon / OrbStack (Linux ARM64).

## Run

From the repository root, with Atlas and its OTP container already running:

```sh
export ATLAS_DATA_DIR="$PWD/.worktrees/local-integration/data"
export ATLAS_NETWORK=local-integration_default
export LOCAL_UID="$(id -u)"
export LOCAL_GID="$(id -g)"
mkdir -p data/motis-benchmark/graph

docker compose -f experiments/motis/compose.yml run --rm motis \
  /motis import --config /config.yml --data /data
docker compose -f experiments/motis/compose.yml up -d
python3 experiments/motis/benchmark.py --output data/motis-benchmark/results
```

Adjust `ATLAS_DATA_DIR` and `ATLAS_NETWORK` for another installation. The expected
inputs are `otp/region.osm.pbf` and `gtfs/vbb.gtfs.zip`. `config.yml` deliberately
pins the timetable period of the tested feed, 2026-08-04 through 2026-12-12.
When replacing the input feed, update this period and benchmark query dates,
then import into a fresh `MOTIS_DATA_DIR` directory. Geocoding and map tiles are
disabled because this experiment compares routing only.

The service API is bound to **127.0.0.1:8485**. Example:

```sh
curl --get 'http://127.0.0.1:8485/api/v6/plan' \
  --data-urlencode 'fromPlace=52.4884438,13.4703145' \
  --data-urlencode 'toPlace=52.4548738,13.5092508' \
  --data-urlencode 'time=2026-09-07T08:00:00Z' \
  --data-urlencode 'transitModes=TRANSIT' \
  --data-urlencode 'useRoutedTransfers=true'
```

The benchmark uses `curl` inside `atlas-app` so both engines are reached from
the same Docker network. It records curl's HTTP duration, excluding Docker exec
startup. Requires host Python 3.11+, Docker, and curl inside the client container;
Python dependencies are all in the standard library. Optional flags:
`--client-container`, `--otp-url`, `--motis-url`, `--samples`, `--output`,
`--direct-only`.

Seven scenarios run against both engines, with one per-scenario warmup and five
measured sequential requests, alternating engine order. Both request a one-hour
window and up to 100 alternatives. The script checks transit presence/absence,
polyline decoding and Berlin-area bounds, and departure/arrival constraints.
Three additional MOTIS smoke checks cover WALK, BIKE and CAR with a two-hour
`maxDirectTime`. These direct checks are not comparative latency benchmarks.
Raw responses and timings remain in the ignored `data/motis-benchmark/` folder.

To stop only the experiment (preserving its data):

```sh
docker compose -f experiments/motis/compose.yml down
```

## Results

See [the assessment](../../docs/motis-evaluation.md) and
[the recorded measurements](results-2026-09-06.json).

Sources: [MOTIS release](https://github.com/motis-project/motis/releases/tag/v2.11.2),
[configuration](https://github.com/motis-project/motis/blob/v2.11.2/docs/setup.md),
[API schema](https://github.com/motis-project/motis/blob/v2.11.2/openapi.yaml).
