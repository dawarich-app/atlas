# Changelog

All notable changes to Dawarich Atlas are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Changed
- **The shipped application is now the Phoenix app (`app-phoenix/`), replacing the Rails app.** `ghcr.io/dawarich-app/atlas/app` is now built from `app-phoenix/` and `compose.yml` runs it (Phoenix on port 4000; Caddy proxies `app:4000`).
- **The Go `atlas-control` sidecar is absorbed into the Phoenix app.** It is removed from `compose.yml`; the app now execs `docker compose` / `docker run` against the host daemon directly (requires the docker socket mount + `group_add` already wired in `compose.yml`). The `build-control` and `test-sidecar` CI jobs are retired.
- API responses are byte-for-byte equal to the Rails app, enforced by the `mix test --include parity` golden gate in CI.

### Added
- Auto-generated `SECRET_KEY_BASE` on first boot (persisted to `/data/.secret_key_base`, mode `600`) so `docker compose up -d` stays zero-config — matching the legacy Rails behavior.
- `Atlas.Release.migrate_from_rails/1` — one-shot importer for upgrades from a Rails install: `bin/atlas eval 'Atlas.Release.migrate_from_rails("/data/app.sqlite3")'` copies `services`, `region_selections`, and `settings` into the Phoenix DB (idempotent; backs the source up first).

### Migration notes (upgrading from 0.1.x / Rails)
- The Phoenix app uses a different SQLite file (`/data/atlas.sqlite3`) and schema. Settings/region selection/service state do **not** carry over automatically — run `Atlas.Release.migrate_from_rails/1` once against the old `/data/app.sqlite3` to preserve them. (User GPS data lives in Dawarich, not Atlas, and is unaffected.)
- Schema migrations run automatically on boot.

## [0.1.1] - 2026-05-21

### Added
- Server-rendered static map route (`GET /static_map`) with a MapLibre-based `static_map_controller.js` Stimulus controller, dedicated `layouts/static.html.erb`, and a `script/render_static_map.mjs` Playwright runner for producing PNG snapshots from the command line.

### Changed
- Quickstart is now zero-config: `git clone && docker compose up -d` is enough. `SECRET_KEY_BASE` is auto-generated on first boot (persisted to `data/app/.secret_key_base`, mode `600`) instead of being a hard requirement in `.env`. `compose.yml` no longer fails when `SECRET_KEY_BASE` is unset.
- `.env.example` rewritten: both `SECRET_KEY_BASE` and `DATABASE_URL` are now documented as optional overrides, with the actual defaults (SQLite at `/data/app.sqlite3`) made explicit.
- README quickstart updated to reflect the zero-config boot path; region-preset copy is now an optional follow-up rather than a prerequisite.

## [0.1.0] - 2026-05-18

### Added
- Initial release of Dawarich Atlas — a local-first, self-hostable maps stack built on OpenStreetMap data and FOSS components.
- Rails 8 application (`app/`) serving the map UI, admin Settings, and public + admin JSON APIs over MapLibre.
- Go sidecar (`atlas-control/`) orchestrating data ingest, region downloads, and per-service apply flows.
- Compose stack with optional profiles for Photon (search), Valhalla (routing), Overpass + Pelias Placeholder + libpostal (POIs), and OpenTripPlanner (transit).
- Region presets covering Berlin, Germany, Europe, DACH, multi-city, and planet builds.
- Caddy reverse proxy fronting the stack on port 8484 and serving offline basemap tiles when present.
- Multi-arch GitHub Actions CI publishing `ghcr.io/dawarich-app/atlas/app` and `ghcr.io/dawarich-app/atlas/atlas-control` on every push to `main`.

[0.1.1]: https://github.com/dawarich-app/atlas/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/dawarich-app/atlas/releases/tag/v0.1.0
