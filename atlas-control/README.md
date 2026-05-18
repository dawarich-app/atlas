# atlas-control

Small Go sidecar that owns `docker compose` + `osmium` exec for the Dawarich Atlas admin panel.

## Endpoints

| Method | Path | Body | Returns |
|--------|------|------|---------|
| GET    | `/healthz`                              |   — | `ok\n` |
| GET    | `/status`                               |   — | JSON snapshot of every known service |
| POST   | `/actions/services/{name}/enable`       |   — | 202 |
| POST   | `/actions/services/{name}/disable`      |   — | 202 |
| POST   | `/actions/regions`                      | `{regions: ["berlin","vienna"]}` | 202 |
| POST   | `/actions/tiles`                        | `{url: "..."}` | 202 |

## Local development

```bash
cd atlas-control
go test ./...
go run . --addr :8090

# Or with mock mode
go run ./cmd/mock --scenario testdata/scenarios/photon-quick.yml --addr :8090
```

## Building the image

```bash
docker build -t atlas-control:dev .
```

## Architecture

- `internal/state/` — in-memory per-service state with RWMutex.
- `internal/parsers/` — one per upstream service; `Feed(line)` returns updated `Result{phase, progress, ready}`.
- `internal/dockerexec/` — `docker compose` wrapper through a `Runner` interface for mockable tests.
- `internal/osmium/` — `osmium-tool merge` wrapper.
- `internal/regions/` — minimal `regions/*.env` parser (mirrors the Rails side).
- `internal/server/` — chi router + handlers.

All non-config state is in-memory; persistence is Rails's job.
