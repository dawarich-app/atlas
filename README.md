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
docker compose up -d
```

That's it — no `.env` file required. The app auto-generates a `SECRET_KEY_BASE` on first boot (persisted to `data/app/.secret_key_base`) and stores its data in a local SQLite file under `data/app/`.

One knob you may need: the in-app control plane talks to the host docker
socket as the `nobody` user via the `DOCKER_GID` supplementary group
(default `999`). If the Settings panel shows a "Control plane degraded"
banner, set it to the socket's group and recreate the container:

```bash
# Linux
echo "DOCKER_GID=$(stat -c %g /var/run/docker.sock)" >> .env
# macOS (OrbStack / Docker Desktop) — the socket maps as gid 0
echo "DOCKER_GID=0" >> .env
docker compose up -d app
```

Visit [http://localhost:8484](http://localhost:8484). The map page is live as soon as Caddy and Atlas come up. Open the **Settings** tab in the side panel to toggle Search / Routing / POIs / Transit and pick the active region. Save & apply — the app downloads the region data, merges it with osmium, and restarts the ingest services, with live progress in the panel.

To pin a specific region preset up front (instead of picking in the UI), copy one into `.env` before booting:

```bash
cp regions/berlin.env .env
docker compose up -d
```

See [`.env.example`](./.env.example) for the optional overrides (custom `SECRET_KEY_BASE`, external Postgres via `DATABASE_URL`, admin credentials, basemap URL).

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

The app is the Phoenix application in [`app-phoenix/`](app-phoenix/). It serves
the map UI, admin Settings, the public + admin JSON APIs, and the control plane
(the former Go `atlas-control` sidecar is absorbed into it — Phoenix execs
`docker compose` against the host daemon directly). CI runs on GitHub Actions
(`.github/workflows/`):

| Job | Trigger | Output |
|---|---|---|
| `test-phoenix` | push / PR touching `app-phoenix/**` | `mix test --include parity` (incl. byte-diff parity gate against the Rails goldens) + `credo` |
| `build-app` | push to `main` touching `app-phoenix/**` | `ghcr.io/dawarich-app/atlas/app:latest` + `:<sha>` (multi-arch amd64+arm64) |
| `test-rails` | push / PR touching `app/**` | RSpec — the legacy Rails app (`app/`) is retained only as the parity reference for the golden capture; it is no longer built or shipped |

Compose defaults consume the `app` tag directly — `docker compose up -d` against a fresh checkout pulls from GHCR with no auth.

Override the image when iterating locally:

```bash
APP_IMAGE=atlas-app:dev docker compose build app
APP_IMAGE=atlas-app:dev APP_PULL_POLICY=never docker compose up -d
```

## Development

- Phoenix app (the shipped app): [`app-phoenix/README.md`](app-phoenix/README.md)
- Legacy Rails app (parity reference only): [`app/README.md`](app/README.md)

End-user documentation source lives in the separate [atlas-website repo](https://github.com/dawarich-app/atlas-website) — open PRs against the docs there.

## License

Dawarich Atlas is licensed under the **GNU Affero General Public License v3.0** ([LICENSE](./LICENSE)) — the same license as Dawarich. Anyone running Atlas as a service must publish their modifications under the same license.

Upstream components retain their own licenses: OSM data is ODbL; Protomaps and MapLibre are BSD-3; Valhalla is MIT; Photon, Overpass and OpenTripPlanner are LGPL-3.0 or AGPL-3.0; Rails is MIT.
