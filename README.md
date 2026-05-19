# Dawarich Atlas

A local-first, self-hostable maps stack. Built on OpenStreetMap data and FOSS components, designed to run on hardware you control with zero outbound API calls at runtime.

Atlas is the maps engine that powers Dawarich, packaged so it stands on its own — install it on your own box, plug your own clients into the API.

## Screenshots

| Search | Routing |
|---|---|
| ![Search panel with Photon results over MapLibre](images/atlas-search.png) | ![Routing panel with Valhalla directions](images/atlas-routing.png) |
| **POIs** | **Settings** |
| ![POI category picker over Overpass results](images/atlas-pois.png) | ![Admin Settings tab: regions, services, basemap](images/atlas-settings.png) |

## Quickstart

```bash
git clone https://github.com/dawarich-app/atlas.git
cd atlas
cp regions/berlin.env .env
docker compose up -d
```

Visit [http://localhost:8484](http://localhost:8484). The map page is live as soon as Caddy and Atlas come up. Open the **Settings** tab in the side panel to toggle Search / Routing / POIs / Transit and pick the active region. Save & apply — the sidecar handles downloads and ingest, with progress streaming back over Action Cable.

City scale boots in minutes; country takes hours of background ingest; planet takes days.

**[Full walkthrough →](https://atlas.dawarich.app/docs/quickstart)**

## Documentation

Every operational topic has a dedicated page on the website. The README is intentionally thin — anything that's not in the table below lives there.

| Topic | Where to read |
|---|---|
| What it is, capability list, response envelope | [Introduction](https://atlas.dawarich.app/docs/) |
| Clone → boot → data layers, admin panel auth, offline basemap | [Quickstart](https://atlas.dawarich.app/docs/quickstart) |
| Design principles, tech stack, topology, Go sidecar, Nominatim decision | [Architecture](https://atlas.dawarich.app/docs/architecture) |
| Region presets, multi-region auto-merge, scaling tables (Germany / France / USA / planet) | [Regions](https://atlas.dawarich.app/docs/regions) |
| Compose profiles, graceful degradation, ports | [Compose profiles](https://atlas.dawarich.app/docs/compose-profiles) |
| Full OpenAPI spec (Redoc-rendered) | [Public API](https://atlas.dawarich.app/api/v1/) · [Admin API](https://atlas.dawarich.app/api/admin/) |

Docs source: [`dawarich-app/atlas-website`](https://github.com/dawarich-app/atlas-website).

## CI / images

CI runs on GitHub Actions (`.github/workflows/`) and publishes four artifacts:

| Job | Trigger | Output |
|---|---|---|
| `test-rails` | push / PR touching `app/**` | RSpec suite |
| `test-sidecar` | push / PR touching `atlas-control/**` | `go test -race ./...` |
| `build-app` | push to `main` touching `app/**` | `ghcr.io/dawarich-app/atlas/app:latest` + `:<sha>` (multi-arch amd64+arm64) |
| `build-control` | push to `main` touching `atlas-control/**` | `ghcr.io/dawarich-app/atlas/atlas-control:latest` + `:<sha>` (multi-arch) |

Compose defaults consume those tags directly — `docker compose up -d` against a fresh checkout pulls from GHCR with no auth.

Override either image when iterating locally:

```bash
APP_IMAGE=atlas-app:dev docker compose build app
APP_IMAGE=atlas-app:dev APP_PULL_POLICY=never docker compose up -d
```

## Development

- Rails app: [`app/README.md`](app/README.md)
- Go sidecar: [`atlas-control/README.md`](atlas-control/README.md)

End-user documentation source lives in the separate [atlas-website repo](https://github.com/dawarich-app/atlas-website) — open PRs against the docs there.

## License

Dawarich Atlas is licensed under the **GNU Affero General Public License v3.0** ([LICENSE](./LICENSE)) — the same license as Dawarich. Anyone running Atlas as a service must publish their modifications under the same license.

Upstream components retain their own licenses: OSM data is ODbL; Protomaps and MapLibre are BSD-3; Valhalla is MIT; Photon, Overpass and OpenTripPlanner are LGPL-3.0 or AGPL-3.0; Rails is MIT.
