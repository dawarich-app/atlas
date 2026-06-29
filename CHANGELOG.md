# Changelog

All notable changes to Dawarich Atlas are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-06-10

### Fixed
- **The shipped image can now actually drive the control plane**: the release Dockerfile installs `docker-ce-cli` + `docker-compose-plugin` from Docker's apt repo (Debian's `docker.io` ships CLI 20.10 without compose v2, so every service start/stop/logs/update call failed with `'compose' is not a docker command` — silently).
- **Region apply works end-to-end.** The Phoenix app now ports the Go sidecar's full apply pipeline: PBF download (streaming, skip-if-present, `.partial` + rename) → GTFS download (non-fatal) → `current.osm.pbf` (symlink for one source, native `osmium merge` for several) → `current.osm.bz2` for overpass → OTP staging (`region.osm.pbf` + GTFS zips, `graph.obj` dropped) → `docker compose restart` of the enabled ingest services. Previously no component downloaded PBFs at all and osmium ran via `docker run -v /data:/data` against a host path that doesn't exist.
- **Control-plane errors are no longer swallowed.** `docker compose` exit codes propagate into `services.last_error` and an `:error` status (a failed stop no longer pretends the service is "stopped"); region-apply failures broadcast `apply_error` and persist in `RegionApplier.status/0`, so the map page shows the real failure instead of "Applying N regions…" forever.
- Region selection no longer accumulates invisibly: the Settings Region tab shows a removable-chips tray of every selected region with "clear all"; the apply button counts only actual changes vs. the last applied selection, and the flash names the regions it applies.
- Tile-pack downloads are asynchronous (no 30-minute `GenServer.call` ceiling), report real byte progress from `Content-Length`, land in `data/tiles/` where Caddy serves them (`/tiles/*` — previously they were written to `data/app/tiles`, which nothing served), and require a size confirmation (HEAD probe) before multi-GB fetches.
- Log streaming works in both viewers: the map-page logs modal now streams real lines (was: a single `last_log` line) with waiting/EOF/error states; the admin viewer starts with 200 lines of history (`--tail=200`, was `--tail=0`) and announces stream end instead of freezing. Log tailers register uniquely (no duplicate `docker compose logs` processes per open viewer) and no longer restart in a loop when the CLI is broken.
- Settings panel boot race: a not-yet-ready control plane renders a "starting…" placeholder instead of a fake-empty "region: none" with a disabled button.
- Cosmetics: never-started services read "off" instead of "unknown"; the header region stat uses catalog labels ("Berlin +2") instead of raw `gf:`-prefixed slugs; admin error states render trimmed human messages instead of `inspect/1` terms.
- **The service logs modal overlays the whole page and actually closes.** It was confined to the side panel (`absolute` inside the panel container) and an `onclick="stopPropagation()"` handler swallowed every click — including the close button — before LiveView's delegated listener saw them. The modal now renders at the page root (`fixed`, full viewport) and closes via the ✕ button, clicking outside, or Escape.
- **"Save & apply" no longer freezes (or appears dead) while docker pulls an image.** Service enable/disable ran `docker compose up/stop` synchronously through GenServer calls (a 5-second LiveView call timeout against a multi-minute image pull). The compose op now runs in a background task: the click round-trips in milliseconds with an optimistic status, and the result (including failures) lands asynchronously in `last_error`/status.
- **Enabled services come back after `docker compose down` or a redeploy.** At boot every service reconciles desired state (the persisted `enabled` flag) against the actual containers: enabled-but-gone services are started again, stale statuses ("ready" with no container, "stopped" with a live one) are corrected.
- **Service status updates without anyone watching logs.** The status/progress parser was only fed while a logs viewer was open; a log tailer now attaches automatically to every running service. Tailers keep a 500-line ring buffer that's replayed into the logs modal and admin viewer when opened late — no more empty "Waiting for log output…" on a quiet, healthy service.
- Long-running operations are now visible in `docker logs atlas-app`: region applies log start/phase/finish/failure, tile-pack downloads log start, one line per percent, and the outcome — previously a 100 GB planet download produced zero log evidence.

### Added
- **Raw Photon passthrough API** under `/api/v1/photon/{api,reverse,lookup,status}`: forwards the query string verbatim (repeated keys like `osm_tag` preserved) to the internal Photon service and returns its status and body untouched — no normalization, no `{data, meta}` envelope. Lets external proxies (e.g. chibigeo) offer a byte-faithful Photon-compatible API on top of Atlas. Photon errors pass through verbatim; an unreachable Photon yields `503 UPSTREAM_UNAVAILABLE`.
- **Control-plane preflight diagnostics** (`Atlas.Control.Preflight`): docker CLI, compose plugin, socket access, data-dir writability, and osmium are probed at boot; failures render a "Control plane degraded" banner in Settings and `/admin/services` with the exact remedy (including per-OS `DOCKER_GID` guidance — macOS OrbStack/Docker Desktop needs `DOCKER_GID=0`).
- Live region-apply progress on the map page and `/admin/apply`: per-phase card (downloading with byte %, merging, converting, staging, restarting) on a stable `control:apply` PubSub topic; survives page refresh via `RegionApplier.status/0`.
- `GTFS_URL` / `GTFS_NAME` are now part of the region catalog (parsed from region `.env` presets) so transit feeds download during apply.
- Writable mounts for `data/gtfs`, `data/otp`, `data/tiles` in both compose files.
- **App version display** — `Atlas.Version` reads the canonical `mix.exs` version from the application spec (no separate version file to keep in sync) plus the git SHA baked in at image build time (`APP_REVISION` build arg, passed by CI). Shown in the side-panel footer and the admin sidebar (both link to GitHub releases) and served at `GET /api/v1/version` as `{"data": {"version": ..., "revision": ...}}`.
- **Dokploy deployment** (`compose.dokploy.yml` + `DEPLOY-DOKPLOY.md`) — Dokploy-managed services (no docker socket; the app reaches upstreams via env URLs), Caddy behind Traefik for TLS/domain, named volumes persisting across redeploys. Ships minimal — `app` + `caddy` pointed at an existing Photon via `PHOTON_URL` — with routing/POIs/transit (valhalla/overpass/otp) as uncomment-to-add blocks that build from OSM data staged by the map's region apply. Self-hosters keep the full click-to-enable control panel via `compose.yml`.
- **OneDev CI build spec** (`.onedev-buildspec.yml`) — builds the app image with buildx on pushes to `main` (`APP_REVISION` baked in via `moreOptions`) and pushes `latest` + commit-SHA tags to OneDev's built-in registry at `onedev.dwri.xyz/atlas/app`; requires an `onedev-access-token` job secret. Used for testing; the GHCR/production pipeline stays in `.github/workflows/`.

### Changed
- `HOST_PROJECT_DIR` is now consumed as `docker compose --project-directory` (it was previously set but read by nothing), so sidecar bind mounts (`./data/photon`, …) resolve against the host checkout. Region-data processing (download/merge/convert/staging) no longer needs host-path translation at all — osmium runs natively in the app container, replacing the amd64-only `stefda/osmium-tool` docker-run dependency.

## [0.2.0] - 2026-06-02

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
