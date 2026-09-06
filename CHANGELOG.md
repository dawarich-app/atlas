# Changelog

All notable changes to Dawarich Atlas are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Unified Search and Places: one always-available input, optional category filters and suggestions, category-only discovery, explicit map-area scope, URL state and a complete reset.
- Search collects matches across the installed Photon dataset, subdividing full spatial pages instead of silently showing only 40 results. Numbered map clusters expand on click, and Show all fits the entire result set. Zooming no longer replaces results. Loading, cancellation and incomplete coverage are explicit; the sidebar keeps 40 ranked suggestions while the map receives all collected matches.

## [0.4.0] - 2026-09-06

### Fixed
- Directions now has a **Get directions** button, including for endpoints selected on the map. Transit dispatches to OpenTripPlanner and decodes its polyline5 geometry; empty or failed routes clear the old line instead of displaying a misleading "Route ready" message (#45, #47).
- Directions preserves typed endpoints when changing travel mode and fits the map to the resulting route. Trips outside the loaded region show a coverage hint. On mobile screens the controls and map share the viewport, keeping the map and point picker accessible.
- Placeholder installs its official prebuilt database automatically on first start. Its data directory honours `PUID`/`PGID`; downloads stream to a temporary file, are checked against the pinned service's schema, and only then replace the database. Invalid previous databases are backed up; valid databases are reused offline. This removes the manual WhosOnFirst import from normal Search setup (#26).
- The catalog generator runs without starting the database or control plane, fixing the monthly refresh on a clean CI checkout.
- **The docker socket group was read from the wrong place.** `compose.yml` exports `DOCKER_GID` into the app container, defaulting to 999, while the socket on macOS is gid 0 — so preferring that variable granted a group the daemon does not answer on and left the control plane degraded anyway. The socket's own gid now decides; `DOCKER_GID` is honoured as an additional group, which is the only lever available when the socket is not visible from inside the container.
- **Dokploy deployments never gave Valhalla its region.** `/work/data/valhalla` had no volume there, so the staged PBF landed in the container's ephemeral layer and Valhalla crash-looped exactly as it did elsewhere.
- **Service status ignored every parser.** The status guards matched atom phases while all parsers emit strings, so `downloading`, `building` and `error` were unreachable and any enabled service that was not ready collapsed to "starting" — a crashed geocoder reported itself as still starting up, and a multi-GB index download showed no phase for its whole run.
- **An apply announced itself finished while its sidecars were still ingesting.** A sidecar that had not logged in the seconds before the applier returned was written off as absent. Services the apply actually restarts now hold the timeline open until they report; only ones it deliberately skipped settle early.
- **Failures during the restart step went unrecorded**: a `docker compose restart` that failed was discarded and reported as a successful apply, and when it followed a failed conversion it vanished entirely — leaving the sidecar rows to turn green on log lines from the containers that never received the new data. Every service is now attempted, and every failure is named.
- **A finished apply stayed on screen forever** — the Region tab and `/admin/apply` kept rendering the last run until another one started. It can now be dismissed.
- A failed restart no longer reports the Overpass conversion as broken, a completed stage is no longer reddened by a later crash, and a progress bar can no longer exceed 100% when an upstream under-reports its `Content-Length`.
- **The control plane came up permanently degraded.** The entrypoint re-added `DOCKER_GID` after dropping to uid 65534, but compose's `group_add:` never exports that value into the container, so the dropped process ran with an empty supplementary group list and could not reach the docker socket; the socket's own gid is now read instead. Separately, `HOME=/root` is unreadable by 65534, which made the docker CLI abort plugin discovery and report `unknown flag: --short` rather than a permission error — `DOCKER_CONFIG` now points somewhere readable.
- **Valhalla crash-looped after every apply, and lost its tiles on restart.** The gis-ops image scans its own `/custom_files` for `*.osm.pbf` and exits with "No local PBF files... Nothing to do" without one, but the applier only ever wrote to `osm/`. The region PBF is now staged where Valhalla actually looks, and its tile directory has a bind mount, so a rebuilt graph survives `docker compose restart`.
- **Applying more than one region always failed, in milliseconds.** `osmium` infers its output format from the file extension, and the applier merges to `current.osm.pbf.partial` so an interrupted run leaves a file the partial sweep can recognise; osmium rejects that name outright without an explicit `-f pbf`.
- **OpenTripPlanner never reported itself ready.** The log parser watched for four phrases OTP does not emit — it logs `Started listener bound to`, not `Started listening`, and `Grizzly server running`, not `Grizzly server started` — so transit sat at `saving-graph 90%` until something happened to call the API and a fallback pattern rescued it. The fixture that covered this was written to match the regex rather than the program; it is now a verbatim capture, alongside an unedited full container start that the phase-order test runs against.
- **OTP silently discarded every time-based restriction.** Without `osmDefaults.timeZone` it logs "time-restricted entities will not be created" and drops opening hours and conditional access from the street graph. Atlas wrote no OTP config at all; it now pins the zone when the selected regions agree on one, and removes a stale config when they do not, since a zone outliving its extract shifts every restriction by whole hours without saying so. The country table is generated from the IANA database: a country qualifies only when all of its zones hold the same UTC offset all year, so Berlin + Vienna resolve while Berlin + London stay ambiguous, and the US, Canada, Australia, Brazil and Russia are excluded by construction.
- **Region subdivisions had no country.** Geofabrik publishes `country_code` only at country level, so `gf:berlin` and two thirds of the shipped catalog arrived as `nil`. The catalog now inherits it up the parent chain (523 of 796 regions resolve a zone, up from 265).
- **The apply progress bar sat at exactly 50% for the whole Valhalla build.** `building-tiles` was treated as a measured phase, but the parser assigns it a flat `0.5` on sight of "Running valhalla_build_tiles" and its only real-progress pattern matches OpenTripPlanner's wording. Sidecar stages for services that never started now settle as skipped with a reason instead of spinning indefinitely.
- **Search answered every failure with an empty panel**, so a geocoder that was never installed, one that had crashed, and a misspelt place name were indistinguishable from a dead button. The panel now names the service and the reason — "Photon is not installed" is actionable where "unavailable" is not, and it is the ordinary state of a fresh instance — and separates *not installed* from *still downloading its dataset* from *installed but not responding*.
- Hovering and keyboard-highlighting a search result had no visible effect: both painted the row `bg-base-200`, the colour the panel already sits on.
- A malformed value in any upstream tuning knob (`PHOTON_TIMEOUT`, `VALHALLA_TIMEOUT`, `*_OPEN_TIMEOUT`, …) no longer takes down every request that reads it. `env_int/2` used `String.to_integer/1`, so `VALHALLA_TIMEOUT=10s` raised on each call; it now falls back to the default and logs a warning naming the variable.
- The Protomaps daily-planet basemap targets the previous day’s build, which is already published, instead of a build that may not exist yet (#2)
- Transit planning now uses OpenTripPlanner's GraphQL API instead of the removed legacy REST endpoint (#25).
- Region apply no longer stalls or silently serves stale POI data: the PBF→bz2 convert is no longer bounded by a 30-minute wall-clock timeout (a genuinely hung osmium is now caught by a stall watchdog instead), orphaned `.partial` files are swept from `osm/`, `osm/sources/` and `gtfs/`, and a failed conversion fails the apply loudly instead of leaving overpass on a weeks-old snapshot (#34, #28). The convert now runs after OTP staging, so a broken overpass source no longer withholds fresh data from valhalla and OTP.
- Reverse-proxy deployments no longer loop on HTTPS redirects when TLS terminates before Caddy (#20)
- The app no longer crash-loops when the data dir is owned by another uid: `PUID`/`PGID` are honoured, the entrypoint takes ownership before dropping privileges, and an unwritable dir reports a clear error instead of a bare `Permission denied` (#23)
- Headless LAN deployments work over plain HTTP on a non-standard port: `PHX_SCHEME`, `PHX_PORT`, `FORCE_SSL` and `PHX_CHECK_ORIGIN` are now configurable, and `PHX_SCHEME=http` turns the HTTPS redirect off by default (#19)
- The in-app control plane now reads the project `.env`, so region, UID/GID and heap settings reach control-plane-launched services instead of silently falling back to compose defaults (#22). Note: if your `.env` sets a different `COUNTRY_CODE` than the compose default, the next service start will now honour it and re-download that region's data.
- Valhalla now starts with a safe default worker cap and file-descriptor limit on multi-core hosts (#24)
- Overpass diff updates are now opt-in so POIs can serve after an initial import without waiting on Geofabrik catch-up (#27)
- Dokploy's minimal compose file no longer starts or exposes Overpass by default; the Overpass service and `/overpass` proxy are now commented out together as optional poster-sidecar configuration.

### Added
- **Search markers, dismissal and shareable queries behave as one thing.** Picking a result, pressing Escape and clearing the box all clear the pins with the list; flying to a result no longer re-runs the query that put it there; and a shared `?q=` link reproduces the sender's results instead of being re-scoped to wherever the viewer's map happened to open.
- **Type-as-you-go search.** Results now arrive while typing (200 ms debounce, two-character minimum) instead of only on Enter, with arrow-key navigation, Enter to pick the highlighted result and Escape to dismiss. Search is scoped to the visible map again and asks for up to 40 results, re-querying as you pan — so searching a chain name answers "which of these can I see" rather than returning a handful from across the country.
- **Every search result is now a marker**, not just the one you click, so you can see where the matches are before choosing. Clicking a pin opens a popup with the place's category, a one-line address, its coordinates and a link to the OpenStreetMap object. Results carry a category icon and label in the list as well.
- **Searches are shareable.** The query lives in the URL as `?q=…` and is applied when such a link is opened, so a search reproduces what the sender saw. The same path serves typing, a pasted link and the back button.
- **A copy button on both log viewers**, so reading a crash-looping sidecar no longer means selecting hundreds of lines by hand. It reports failure inline rather than silently succeeding, because clipboard writes are blocked on insecure origins — which a LAN deployment over plain HTTP is.
- **The region-apply timeline reports what it is actually doing**: which file is downloading, from which URL, and how many bytes of how many; which stage is running and which are still pending; and it continues past the applier's return through Valhalla, Overpass and OTP ingest, since an apply that finished but left Valhalla hours from serving a route has not finished in any sense that matters. Stages whose progress nothing measures show their phase rather than an invented percentage.
- **Map matching** — `POST /api/v1/map-match` snaps a recorded GPS trace onto the road network via Valhalla's Meili matcher, the inverse of `/api/v1/route`: routing invents a path between two points, matching takes a path you already walked and decides which edges you were on. Post a `shape` of `{lat, lon}` points (optionally with `time` and `accuracy`); `mode`, `shape_match` and Valhalla's `search_radius` / `gps_accuracy` / `breakage_distance` are accepted. `format=polyline6` (default) returns Valhalla's legs verbatim, matching what `/api/v1/route` already returns; `format=geojson` stitches them into one decoded `LineString`, so callers need no polyline decoder of their own. A trace Valhalla rejects is reported as invalid input rather than as an upstream failure, relaying Valhalla's own reason and `error_code` — whether the trace fell outside the loaded region, was too sparse or noisy, or exceeded a service limit such as the 200 km `max_distance`. Trace length is capped by `MAP_MATCH_MAX_POINTS` (default 10000), and matching gets its own `VALHALLA_MATCH_TIMEOUT` (default 60000 ms) separate from the routing timeout, since it is superlinear in point count and holds a Valhalla worker for the whole request. Both knobs are read from `.env`.

### Changed
- Release publication and image builds now run Phoenix and deployment tests first, then build and boot the actual image on native amd64 and arm64 runners. Stable image tags are published only after both architectures pass. Release notes must match the application version; `Unreleased` cannot accidentally select an older release, and an interrupted publication can be resumed on the same commit.
- **`ghcr.io/dawarich-app/atlas/app:latest` now means "newest stable release", not "tip of `main`".** Images are cut from published GitHub releases; pushing to `main` no longer publishes one. Pin a version tag if you were relying on `latest` tracking every merge — and note that a fresh `docker compose pull` will now hold at the last release rather than moving with development.
- Releases are tagged and published automatically from this file: when the top heading is a version with a date (rather than `Unreleased`), CI tags it, creates the GitHub release, and builds the image. Per-commit builds continue on the OneDev registry for testing.
- `mix credo --strict` is clean and enforced in CI, with the project's ruleset checked in at `app-phoenix/.credo.exs`. It previously failed on `main` and ran ahead of the test step, so the test suite had never actually executed for a pull request.
- The deployment-config assertions in `test/deployment_config.test.mjs` now run in CI, on a workflow that triggers when `Caddyfile` or a `compose*.yml` changes. They had no runner, so the reverse-proxy and sidecar defaults they guard could regress silently.

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

[0.4.0]: https://github.com/dawarich-app/atlas/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/dawarich-app/atlas/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/dawarich-app/atlas/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/dawarich-app/atlas/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/dawarich-app/atlas/releases/tag/v0.1.0
