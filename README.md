# Dawarich Atlas

A local-first, self-hostable maps stack. Built on OpenStreetMap data and FOSS components, designed to run on hardware you control with zero outbound API calls at runtime.

Atlas is the maps engine that powers Dawarich, packaged so it stands on its own — install it on your own box, plug your own clients into the API.

## Design principles

1. **Local-first.** Every layer runs on your hardware. No outbound API calls at runtime.
2. **Open data only.** OSM, SRTM, GTFS — all freely downloadable.
3. **MapLibre GL** as the renderer. Vector-first.
4. **PMTiles** as the tile format. Static files, no tile server process.
5. **Minimal overlap, minimal resource consumption.** Each service owns a distinct query type.
6. **Single compose file.** One `compose.yml`, bind mounts under `./data/`, region selected via `.env`.
7. **Caddy as the edge.** Auto-HTTPS-ready, ergonomic config, range requests + compression out of the box.
8. **Rails for the app.** One full-stack codebase. Simple for contributors, easy to extend.

## Tech stack

| Layer | Pick |
|-------|------|
| App framework | Rails 8 (Ruby 3.4.x) |
| Frontend | Hotwire (Turbo + Stimulus) + MapLibre GL JS (Stimulus controller) |
| Styling | Tailwind CSS v4 + DaisyUI v5 |
| Asset bundling | `jsbundling-rails` + esbuild |
| ORM | ActiveRecord |
| Default DB | SQLite (Rails 8 production-ready: Solid Queue/Cache/Cable) |
| Optional DB | PostgreSQL (`DATABASE_URL=postgres://…`) |
| Auth | Rails 8 built-in `rails g authentication` + OmniAuth providers |
| Authorization | Pundit (scoped collections / shared places) |
| Tests | RSpec |
| E2E | Playwright (lives in sibling `e2e/` dir per dawarich convention) |
| Edge | Caddy (TLS + static tiles + reverse proxy to Rails) |
| Map services | Photon, Placeholder, libpostal, Valhalla, Overpass, OpenTripPlanner |

## Stack overview

```
                    ┌────────────────────────┐
                    │  Browser (MapLibre)    │
                    └───────────┬────────────┘
                                │
                                ▼
                        ┌──────────────┐
                        │    Caddy     │  TLS + /tiles/* static
                        └───┬────────┬─┘
                            │        │
                  /tiles/*  │        │  /*
                            ▼        ▼
                      ┌────────┐  ┌──────────────────┐
                      │  PMTiles│  │   Rails app      │
                      │  static │  │ ── views + API ──│
                      │         │  │   /api/search    │
                      └────────┘  │   /api/whats-here│
                                  │   /api/route     │
                                  └────────┬─────────┘
                                           │
            fan-out (internal Docker network only):
                                           │
       ┌────────┬─────────────┬────────────┼────────────┬────────┐
       ▼        ▼             ▼            ▼            ▼        ▼
    photon  placeholder   libpostal    valhalla     overpass    otp
```

## Layer status

Legend: `done` / `wip` / `planned`

| # | Layer | Status | Component | Data source | Downloadable | MapLibre integration |
|---|-------|--------|-----------|-------------|--------------|---------------------|
| 1 | Base map tiles | planned | Protomaps PMTiles | OSM planet | Yes — `planet.pmtiles` (~100 GB) via [maps.protomaps.com/builds](https://maps.protomaps.com/builds/) or self-built via Planetiler | Native — `pmtiles://` source in style.json |
| 2 | Tile serving | scaffolded (`caddy`) | Caddy static + range + CORS | n/a | Yes | Native — HTTP range requests |
| 3 | Map style | planned | Protomaps Basemap styles | github.com/protomaps/basemaps | Yes — JSON style files | Native — `style.load()` |
| 4 | Geocoding (forward + reverse) | scaffolded | Photon + Placeholder + libpostal | OSM + Who's on First | Yes — Photon prebuilt index from Komoot mirror (~70 GB planet, smaller for `COUNTRY_CODE`) | Stimulus controller → Rails `/api/search` → fan-out |
| 5 | Routing | scaffolded (`valhalla`) | Valhalla | OSM PBF + SRTM DEM | Yes — Valhalla builds graph from PBF on first boot | Stimulus controller → Rails `/api/route` → LineString GeoJSON |
| 6 | Elevation | scaffolded (`valhalla`) | Bundled with Valhalla | SRTM 1-arcsec | Yes — Valhalla downloads on demand if `build_elevation=True` | Server-side helper, queried per trip |
| 7 | Terrain / hillshade | planned | Terrain-RGB raster tiles | SRTM → `rio-rgbify` → PMTiles | Yes — prebuilt at [registry.opendata.aws/terrain-tiles](https://registry.opendata.aws/terrain-tiles/) (Mapzen archive) | Native — `raster-dem` source + `setTerrain()` + `hillshade` layer |
| 8 | Contour lines | planned | Generated from SRTM via `phyghtmap` → PMTiles | SRTM | Yes | Native — vector layer in style |
| 9 | POI lookup ("what's here") | scaffolded (`overpass`) | Overpass API self-hosted | OSM PBF | Yes — Geofabrik extract ingested via `wiktorn/overpass-api` Docker image | Stimulus controller → Rails `/api/whats-here` → GeoJSON |
| 10 | Time zone lookup | planned | `timezone_resolver` gem or `tzinfo` + `rgeo` | OSM-derived tz boundaries | Yes — bundled | Server-side helper, no map layer |
| 11 | Transit | scaffolded (`otp`) | OpenTripPlanner 2 (multimodal journey planner combining OSM road graph + GTFS schedules) | GTFS feeds + OSM | Yes — [transitous.org](https://transitous.org/) aggregates worldwide GTFS | Custom — fetch route, render GeoJSON |

### Architectural decision: Nominatim dropped

Originally the geocoding stack included Nominatim for structured address hierarchies. **Dropped** in favor of:

- **Photon** (prebuilt index from Komoot, ~70 GB planet vs Nominatim's ~1 TB PG) — handles forward autocomplete and reverse geocoding.
- **Placeholder** — handles admin-hierarchy queries (country/region/city) via Who's on First.
- **libpostal** — handles query normalization.

Trade-off: lose Nominatim's fine-grained structured-address API (`address.house_number`, `address.road`, etc.). Photon still returns these as OSM tags, just less polished. If we later need true structured addresses, Nominatim can be added back without disturbing the other services.

## Ports

Only Caddy is published. Everything else is reachable inside the Docker network only.

| Port | Exposed | Service |
|------|---------|---------|
| 8484 | yes | Caddy (fronts Atlas + serves PMTiles) |
| 3000 (internal) | no | Rails app |
| 2322 (internal) | no | Photon |
| 3000 (internal) | no | Placeholder |
| 4400 (internal) | no | libpostal |
| 8002 (internal) | no | Valhalla |
| 80 (internal)   | no | Overpass |
| 8080 (internal) | no | OpenTripPlanner |

For debugging, add a `compose.override.yml` that publishes the backend ports you need.

## Directory layout

```
atlas/
├── README.md
├── compose.yml
├── Caddyfile
├── .env.example
├── .gitignore
├── app/                 # Rails 8 app (see app/README.md to scaffold)
│   ├── README.md
│   ├── Dockerfile       # multi-stage, Ruby 3.4.x (pre-written; preserve when running `rails new`)
│   ├── Gemfile
│   ├── config/
│   ├── app/
│   │   ├── controllers/api/
│   │   ├── models/
│   │   ├── policies/
│   │   ├── services/    # photon_client.rb, valhalla_client.rb, …
│   │   ├── views/
│   │   └── javascript/controllers/   # Stimulus
│   ├── db/
│   └── spec/
└── data/                # bind-mounts (see Data bootstrap for sizing per directory)
    ├── app/             # Rails SQLite + Active Storage
    ├── photon/          # prebuilt Photon index
    ├── whosonfirst/     # raw WOF SQLite (Placeholder's input)
    ├── placeholder/     # built Placeholder store.sqlite3
    ├── valhalla/        # routing tiles + admins
    ├── overpass/        # Overpass index (the disk hog)
    ├── otp/             # OpenTripPlanner graph
    ├── tiles/           # .pmtiles files (basemap, terrain, contours)
    ├── osm/             # shared OSM PBF input
    ├── srtm/            # DEM tiles for Valhalla
    ├── gtfs/            # GTFS feeds for OpenTripPlanner
    ├── caddy/           # Caddy state (certs, etc.)
    └── caddy-config/    # Caddy runtime config
```

All `data/` subdirectories are bind-mounted into containers. Move them to a fast NVMe disk and symlink if needed.

## Quickstart

Everything is automated via the `Makefile` — run `make help` to see all targets.

```bash
# 1. Pick a region (controls PBF, Photon scope, PMTiles default URL, map center)
make region NAME=berlin       # city — ~30 MB PBF, smallest viable footprint
make region NAME=germany      # country — ~4 GB PBF
make region NAME=europe       # continent — ~30 GB PBF
make region NAME=planet       # full Earth — ~75 GB PBF
make region NAME=multi-dach   # multi-country example (DE+AT+CH via osmium merge)
make region-list              # see all presets

# 2. (Optional) download a PMTiles basemap for true offline tiles
make tiles-download URL=https://build.protomaps.com/<YYYYMMDD>.pmtiles
make tiles-local              # point app at /tiles/basemap.pmtiles

# 3. Bare stack
make up           # caddy + app only, no data services
                  # Visit http://localhost:8484 — map loads immediately

# 4. Add data layers (each can run for hours on first boot)
make geocoding    # Photon + Placeholder + libpostal (includes WOF download + Placeholder build)
make routing      # Valhalla (downloads PBF + SRTM; rebuilds graph)
make pois         # Overpass (long PBF ingest)
make transit      # OpenTripPlanner (needs GTFS in data/gtfs/ — see "Data bootstrap" section)

# Or boot everything (except transit) in one go:
make full

# 5. Inspect
make status
make logs
make smoke        # curl every public endpoint and print status codes
make disk         # du -sh data/*/
```

Only `caddy` and `app` start by default. Every other service lives behind a Docker Compose **profile** so heavy services are opt-in. See **[Compose profiles](#compose-profiles)** below.

### Building the app locally instead of pulling from GHCR

```bash
APP_IMAGE=atlas-app:dev docker compose build app
APP_IMAGE=atlas-app:dev APP_PULL_POLICY=never docker compose up -d
```

### What `make full` actually does

`make full` is the closest thing to "run everything with data". The sequence:

1. **Placeholder data prep** (one-shot, ~2 min for Germany)
   - Spawns `whosonfirst` container → downloads WOF SQLite filtered by `WHOSONFIRST_COUNTRY_CODE`
   - Spawns `placeholder` container → runs `extract.sh && build.sh` → writes `data/placeholder/store.sqlite3`
2. **`docker compose --profile all up -d`** — starts every map service in parallel
3. **Status check** — prints `docker compose ps`

After step 3 the **map page is live immediately** at `http://localhost:8484`, but the data services take hours on first boot to be query-ready. Watch the progress with `make logs` or `docker compose logs -f photon valhalla overpass`.

### Realistic first-boot timings for Germany (`COUNTRY_CODE=de`)

| Service | Phase | Time |
|---------|-------|------|
| Photon | Download index | 5–15 min |
| Photon | Extract + ready | ~5 min |
| Placeholder (`make placeholder-data`) | WOF download | <1 min |
| Placeholder (`make placeholder-data`) | extract + build | ~1 min |
| libpostal | Ready | <30 s |
| Valhalla | Download PBF | ~5 min |
| Valhalla | Build admins | ~5 min |
| Valhalla | Build graph tiles | 20–40 min |
| Valhalla | Download SRTM tiles (if `BUILD_ELEVATION=True`) | 10–30 min |
| Overpass | Download PBF | ~5 min |
| Overpass | Initial ingest | **2–4 hours** |

Total disk for Germany with all defaults: **~70 GB** under `data/`. Planet: **~1.5 TB**.

`make disk` shows the live footprint per subdirectory.

## Configuring for any city or country

Atlas is region-agnostic — the same compose stack serves Berlin, Germany, Europe, or the entire planet depending on the data you point it at. Configuration is **one preset file per region** under `regions/`.

### Scenario A: a single city

For city-scale, BBBike publishes prebuilt PBF extracts for ~200 cities. Pattern: `https://download.bbbike.org/osm/bbbike/<CityName>/<CityName>.osm.pbf` (~30–200 MB each).

```bash
# (1) Use a built-in preset
make region NAME=berlin

# OR (2) Generate one from BBBike for any supported city
make region-create-city NAME=tokyo BBBIKE=Tokyo COUNTRY=jp LAT=35.68 LON=139.69 ZOOM=11
make region NAME=tokyo

# Browse BBBike's list: https://download.bbbike.org/osm/bbbike/
```

**What scales down**: Valhalla PBF/tiles + Overpass index + OTP graph + PMTiles (if you self-build) — all use only the city extract.
**What doesn't**: Photon — Komoot only publishes country/continent bundles, so a Tokyo-only deployment still downloads Japan's ~3 GB Photon bundle. Placeholder still pulls the global WOF.

### Scenario B: a single country

Geofabrik publishes country-scale PBFs with hourly diffs.

```bash
# (1) Use a built-in preset
make region NAME=germany

# OR (2) Generate one from Geofabrik for any country
make region-create-country NAME=france CODE=fr GEOFABRIK=europe/france LAT=46.0 LON=2.5
make region NAME=france

# Browse Geofabrik: https://download.geofabrik.de/
# CODE = ISO-2 country code (used by Photon)
# GEOFABRIK = the path under download.geofabrik.de/ without the .osm.pbf suffix
```

**Scales down cleanly** for all services except Placeholder (which is always global WOF).

### Scenario C: multiple countries (or cities)

When you want a few countries together — say DE+AT+CH for German-speaking-Europe — Atlas downloads each PBF separately and merges them with [osmium-tool](https://osmcode.org/osmium-tool/) before the data services see it.

```bash
# (1) Use a built-in multi-region preset
make region NAME=multi-dach          # Germany + Austria + Switzerland
make region NAME=multi-cities        # Berlin + Vienna

# OR (2) Create your own
cp regions/multi-dach.env regions/multi-nordic.env
# Edit the file:
#   PBF_URLS="https://download.geofabrik.de/europe/denmark-latest.osm.pbf
#             https://download.geofabrik.de/europe/sweden-latest.osm.pbf
#             https://download.geofabrik.de/europe/norway-latest.osm.pbf"
#   PBF_NAME=nordic-merged.osm.pbf
#   PBF_URL=local://data/osm/nordic-merged.osm.pbf
#   DEFAULT_LAT=63.0
#   DEFAULT_LON=15.0

make region NAME=multi-nordic
make merge-pbf                         # downloads + merges → data/osm/nordic-merged.osm.pbf
# Then manually point Valhalla/Overpass at the merged file:
cp data/osm/nordic-merged.osm.pbf data/valhalla/
# Edit .env so PBF_URL=file:///custom_files/nordic-merged.osm.pbf (Valhalla's container view)
make routing
```

> **Caveat — work in progress**: the merged-PBF auto-wiring into Valhalla/Overpass is not yet fully scripted. The TODO list tracks it. For now, multi-region requires the manual copy step shown above.

### Scenario D: continent or planet

```bash
make region NAME=europe       # Geofabrik continent extract — ~30 GB PBF
make region NAME=planet       # planet.openstreetmap.org — ~75 GB PBF
```

These trigger the longest first-boot times. See the **Planet-scale operations** section for sizing.

### After switching regions

The Makefile updates `.env` in place. To actually boot data layers:

```bash
make geocoding    # Photon + Placeholder + libpostal
make routing      # Valhalla
make pois         # Overpass
make tiles-download URL=<see "Custom PMTiles" section>
```

If you switch regions on a stack that already has data, `make clean-photon`, `make clean-valhalla`, etc. wipe each layer so it rebuilds against the new PBF.

## Region presets

Every preset is a `regions/<name>.env` that controls — in one place — the PBF URL, Photon's `REGION` knob, the PMTiles basemap URL, and the default map view.

```
regions/
├── berlin.env           # city (BBBike Berlin)        — ~30 MB PBF, ~5 GB total
├── germany.env          # country (Geofabrik DE)      — ~4 GB PBF, ~70 GB total
├── europe.env           # continent (Geofabrik EU)    — ~30 GB PBF, ~280 GB total
├── planet.env           # planet                       — ~75 GB PBF, ~1.5 TB total
├── multi-dach.env       # DE + AT + CH (merged)
└── multi-cities.env     # Berlin + Vienna (merged)
```

Switch via `make region NAME=<preset>`. The preset replaces region-specific env vars in `.env` while preserving `SECRET_KEY_BASE` and `DATABASE_URL`.

### Multi-region (merged extracts)

Multi-region presets list `PBF_URLS=` and a derived merged file path. `make merge-pbf` downloads each source PBF and runs `osmium merge` inside a one-shot container, producing one `.osm.pbf` for Valhalla/Overpass/OTP to consume.

```bash
make region NAME=multi-dach
make merge-pbf                   # downloads 3 PBFs + merges into data/osm/dach-merged.osm.pbf
# point Valhalla/Overpass at the merged file by symlinking or editing PBF_URL
# (auto-wiring of the merged file into services is on the TODO list)
```

> **Caveats**: Photon still operates at country granularity — for a Berlin-only deployment, Photon will download the full Germany bundle. Placeholder still always pulls the global WOF. Per-city/per-country savings are real for Valhalla/Overpass/PMTiles, partial for the rest.

## Custom PMTiles basemap

The Rails app reads `TILES_URL` and synthesizes a Protomaps-style MapLibre style client-side via [`protomaps-themes-base`](https://github.com/protomaps/basemaps).

### Verified working PMTiles sources (2026-05)

| Source | URL | Size | Stability | Notes |
|--------|-----|------|-----------|-------|
| **Protomaps daily build** | `https://build.protomaps.com/<YYYYMMDD>.pmtiles` (e.g. `20260514.pmtiles`) | ~105 GB | Rolls daily; older builds purged after ~30 days | The standard Protomaps planet basemap |
| **Mapterhorn mirror** | `https://download.mapterhorn.com/planet.pmtiles` | ~700 GB | **Permanently stable URL**, monthly refresh | Larger superset with terrain at high zooms |
| **Self-built regional** | `data/tiles/basemap.pmtiles` after Planetiler | varies | controlled by you | See below |

### Three setup modes

```bash
# Option A — TRULY OFFLINE: download once, serve locally via Caddy
make tiles-protomaps-latest          # fetches today's Protomaps build to data/tiles/basemap.pmtiles
make tiles-local                     # writes TILES_URL=/tiles/basemap.pmtiles into .env

# Equivalent manual form:
make tiles-download URL=https://build.protomaps.com/20260514.pmtiles
make tiles-local

# Option B — REMOTE: point directly at any HTTPS PMTiles URL (uses HTTP range requests)
echo 'TILES_URL=https://download.mapterhorn.com/planet.pmtiles' >> .env
# Map fetches tiles directly from the URL on demand — no local download needed

# Option C — DEV FALLBACK: leave TILES_URL empty
# Map renders via OSM raster CDN. Good for first-day work; NOT offline.
```

### Regional PMTiles (city or country only)

For a single-country or single-city deployment, use Planetiler to build a small custom PMTiles from your region's PBF:

```bash
# Assuming you already ran `make region NAME=germany` so data/osm/germany-latest.osm.pbf exists
mkdir -p data/tiles
docker run --rm \
  -v $PWD/data/osm:/data \
  -v $PWD/data/tiles:/out \
  ghcr.io/onthegomap/planetiler:latest \
  --osm_path=/data/germany-latest.osm.pbf \
  --output=/out/basemap.pmtiles

make tiles-local                     # point app at the new file
```

Sizes: Germany ~3 GB, a single city ~50-200 MB, planet ~100 GB (matches Protomaps' build).

### Theme

```bash
TILES_THEME=light       # default
TILES_THEME=dark
TILES_THEME=white
TILES_THEME=black
TILES_THEME=grayscale
```

All five are bundled in `protomaps-themes-base` — switching is a one-env-var change, no rebuild.

### How the client uses it

The map renders the configured tiles through MapLibre's `pmtiles://` protocol (auto-prepended for `*.pmtiles` URLs). HTTP range requests fetch only the visible tiles, so even an "online but pointing at remote URL" setup uses ~50 KB per pan rather than downloading the full file.

## Compose profiles

Each map-service group is gated by a profile so you only spin up (and download data for) what you need.

| Profile | Services | Affects |
|---------|----------|---------|
| _(default — no flag)_ | `caddy`, `app` | The map page and API. Search / routing / POIs return graceful `upstream:unavailable` until their profile is started. |
| `geocoding` | `photon`, `placeholder`, `libpostal` | `/api/search` returns real candidates; `/api/whats-here` resolves a label. |
| `routing` | `valhalla` | `/api/route` returns walking/biking/driving routes + elevation. |
| `pois` | `overpass` | `/api/whats-here` returns POIs in a radius (cafes, shops, transit stops…). |
| `transit` | `otp` | Multimodal journey planning (needs GTFS feeds — see Data bootstrap). |
| `data-setup` | `whosonfirst` | One-shot WOF data download for Placeholder. |
| `all` | every map service | Everything except `data-setup`. |

Activate with `--profile` (repeatable) or the `COMPOSE_PROFILES` env var:

```bash
docker compose --profile geocoding up -d
docker compose --profile geocoding --profile routing up -d
COMPOSE_PROFILES=all docker compose up -d
```

## Data bootstrap

Every layer is a downloadable dataset. **Die Reihenfolge** (the order) doesn't matter — services are independent — but heavy bootstraps run for hours on first start. Each downloads automatically when its container first boots; if you want to fetch data ahead of time or to a different disk, the commands below do exactly that.

### Quick overview

| Service | What it downloads | Region knob | Size (Germany) | Size (planet) | First-boot time |
|---------|-------------------|-------------|-----------------|----------------|-----------------|
| **Photon** | Prebuilt Lucene index from Komoot CDN | `COUNTRY_CODE` (ISO-2 or empty for planet) | ~5 GB → ~8 GB extracted | ~75 GB → ~110 GB extracted | 5 min (DE) – several hours (planet) |
| **Placeholder** | WOF SQLite via `whosonfirst` + builds `store.sqlite3` | `WHOSONFIRST_COUNTRY_CODE` (comma-separated, or empty for planet) | ~200 MB → ~50 MB store | ~5 GB → ~3 GB store | 2 min (DE) – 30 min (planet) |
| **libpostal** | Statistical address-parsing models baked into the image | none — global | 0 (in image) | 0 (in image) | <30 s |
| **Valhalla** | OSM PBF + optional SRTM elevation tiles, builds routing graph | `PBF_URL`, `BUILD_ELEVATION` | PBF ~4 GB + graph ~8 GB + DEM ~3 GB ≈ **~15 GB** | PBF ~75 GB + graph ~80 GB + DEM ~100 GB ≈ **~250 GB** | 30 min (DE) – 2 days (planet) |
| **Overpass** | OSM PBF + minute/hourly diff stream | `PBF_URL`, `OVERPASS_DIFF_URL` | ~40 GB | ~500–800 GB | 4 h (DE) – ~1 week (planet) |
| **OpenTripPlanner** | GTFS .zip(s) + OSM .pbf, builds graph | files dropped into `data/gtfs/` + `data/osm/` | varies — a few GB per region | n/a (built per region) | 10 min – 2 h depending on feed count |
| **PMTiles (base map)** | Protomaps planet PMTiles or self-built regional via Planetiler | URL of the .pmtiles file | ~3 GB regional | ~100 GB | manual download (single file) |

Disk numbers are after build, not peak; transient peaks can be 1.5× during ingest.

---

### 1. Photon (search autocomplete + reverse geocode)

Photon ships a prebuilt index from komoot's CDN, region-selectable via `COUNTRY_CODE`.

```bash
# Germany only (default in .env.example)
COUNTRY_CODE=de docker compose --profile geocoding up -d photon

# Wider region: edit .env to e.g. COUNTRY_CODE=fr (one country at a time)
# Planet: leave COUNTRY_CODE empty
```

**What it affects:** `/api/search?q=…` — without Photon, search results are always empty.

**Sizing notes:** index size scales roughly with OSM POI density. Germany ~8 GB extracted; a single small country (Belgium, Netherlands) ~2–4 GB.

**Watch progress:**

```bash
docker compose logs -f photon
```

Status moves through `downloading` → `extracting` → `serving`. The container's healthcheck flips to `healthy` once the Photon HTTP API answers on :2322.

---

### 2. Placeholder (admin-hierarchy enrichment)

Placeholder needs Who's on First SQLite files (admin boundaries: country → region → county → locality → neighbourhood). The `whosonfirst` data-setup container downloads them; Placeholder then builds its FTS-indexed `store.sqlite3`.

```bash
# Easy path — Makefile handles both steps idempotently:
make placeholder-data
docker compose --profile geocoding up -d placeholder
```

Or the raw equivalent:

```bash
# 2a. Download WOF SQLite
docker compose --profile data-setup run --rm whosonfirst

# 2b. Build Placeholder's store from the downloaded WOF data
docker compose run --rm placeholder bash -c "./cmd/extract.sh && ./cmd/build.sh"

# 2c. Start the Placeholder service
docker compose --profile geocoding up -d placeholder

# 2d. (Recommended) Reclaim transient disk
rm -rf data/whosonfirst/* data/placeholder/wof.extract
```

**What it affects:** `admin` chain enrichment on `/api/v1/{search,reverse,geocode,whats_here}` results — fills in missing country/state/city/neighbourhood when Photon's OSM tags are thin.

**Reality check — measured on a real run**:

| Setting | WOF raw (transient) | wof.extract (transient) | Placeholder `store.sqlite3` |
|---------|--------------------|--------------------------|------------------------------|
| **Always planet** | **~68 GB** | ~3.7 GB | ~3–6 GB |

> **Important gotcha (measured, not theoretical):** `pelias/whosonfirst:latest` **ignores** the `WHOSONFIRST_COUNTRY_CODE` env var (the country-filter knob in older Pelias images was removed). It always downloads two **global** SQLite files (`whosonfirst-data-admin-latest.db` ~62 GB + `whosonfirst-data-postalcode-latest.db` ~6 GB). There's currently no way to scope this to a single country without rebuilding the WOF bundle ourselves from `pelias/whosonfirst-data-extracts` (TODO).

**Memory note:** the final `optimize` step in `build.sh` is RAM-hungry. On Docker Desktop with the default 8 GB limit it gets **OOM-killed** at the very end. Symptom: `node load.js` exits with `Killed` after `optimize...`. The store is **still queryable** (FTS index is fully built before that step), just larger than it would be optimized:

| Outcome | `store.sqlite3` |
|---------|------------------|
| optimize succeeded (clean run) | ~3–4 GB |
| optimize OOM-killed (Docker Desktop default RAM) | ~5–6 GB (un-vacuumed) |

To get the optimized size: raise Docker Desktop's memory limit to ≥16 GB, then `make placeholder-data-rebuild`.

After step 2b succeeds, the **~71 GB of transient build files** (`data/whosonfirst/*` + `data/placeholder/wof.extract`) can be deleted — Placeholder only reads `data/placeholder/store.sqlite3` at runtime.

---

### 3. libpostal (address parsing)

Nothing to download. The model files are baked into the image (~1.8 GB image, parsed in-memory).

```bash
docker compose --profile geocoding up -d libpostal
```

**What it affects:** when the orchestrator routes long structured strings through libpostal first, parsed components (`road`, `house_number`, `city`) feed cleaner queries into Photon.

---

### 4. Valhalla (routing + elevation)

Valhalla builds its routing graph from an OSM PBF + (optionally) SRTM elevation tiles, both downloaded by the container on first boot.

```bash
# Default region (Germany, defined in .env)
docker compose --profile routing up -d valhalla

# Different region — edit .env:
#   PBF_URL=https://download.geofabrik.de/europe/france-latest.osm.pbf
# then:
docker compose --profile routing up -d valhalla

# Skip elevation to save ~3–100 GB (no ascent/descent in route summaries)
BUILD_ELEVATION=False docker compose --profile routing up -d valhalla
```

**What it affects:** `/api/route` — without Valhalla, `502 UPSTREAM_ERROR`. With `BUILD_ELEVATION=False`, ascent/descent are zero in route summaries.

**Sizing knobs:** the `PBF_URL` is the dominant factor.

| `PBF_URL` | PBF | Graph tiles | DEM (if `BUILD_ELEVATION=True`) | Total |
|-----------|-----|-------------|----------------------------------|-------|
| Germany | ~4 GB | ~8 GB | ~3 GB | **~15 GB** |
| Europe | ~30 GB | ~60 GB | ~25 GB | **~115 GB** |
| Planet | ~75 GB | ~80 GB | ~100 GB | **~250 GB** |

**Watch progress:**

```bash
docker compose logs -f valhalla
```

Phases: `downloading PBF` → `building admin DB` → `downloading SRTM` → `building tiles` → `serve`.

---

### 5. Overpass (POIs / "what's here")

Overpass ingests an OSM PBF into its own indexed DB. The image's `init` mode downloads the PBF and ingests on first start.

```bash
docker compose --profile pois up -d overpass
```

**What it affects:** `/api/whats-here?lat=&lon=&radius=` — without Overpass, nearby POIs come back as `502 UPSTREAM_ERROR` (the reverse-geocode label from Photon still resolves).

**Sizing notes:** Overpass is **die Festplattenhure** (the disk hog / прожорливое до диска) — its index is much bigger than the source PBF.

| `PBF_URL` | PBF | Overpass index | Total |
|-----------|-----|-----------------|-------|
| Germany | ~4 GB | ~40 GB | **~45 GB** |
| Europe | ~30 GB | ~250 GB | **~280 GB** |
| Planet | ~75 GB | ~700 GB | **~800 GB** |

Diff updates pull continuously from `OVERPASS_DIFF_URL`. For a regional setup, point this at the matching Geofabrik `-updates/` path.

**Watch progress:**

```bash
docker compose logs -f overpass
# Look for: "compiled 1000000 blocks", then "ready"
```

---

### 6. OpenTripPlanner (transit)

OTP doesn't download anything by itself — you drop GTFS feeds and an OSM PBF into `data/gtfs/` and `data/osm/`, then OTP builds its graph on boot.

```bash
# Pick a GTFS feed (Transitous aggregates worldwide)
mkdir -p data/gtfs data/osm

# Example: Berlin's VBB feed
curl -L https://example.transit.feed/vbb-latest.zip -o data/gtfs/vbb.zip

# Example: Germany OSM PBF for the routing graph
curl -L https://download.geofabrik.de/europe/germany-latest.osm.pbf -o data/osm/germany.osm.pbf

# Build + serve
docker compose --profile transit up -d otp
```

**What it affects:** future `/api/transit` endpoint (not yet implemented — currently OTP runs but isn't surfaced).

**Sizing notes:** small GTFS feeds are ~10–200 MB each; OTP's built graph is ~3–10 GB per region. Memory at runtime is 4–16 GB.

For feed discovery: [transitous.org](https://transitous.org/) lists ~1500 worldwide GTFS feeds with a permissive license.

---

### 7. PMTiles base map

The base map is a single `.pmtiles` file served as a static asset by Caddy from `data/tiles/`.

```bash
# Option A: Protomaps planet (~100 GB, daily updated)
curl -L https://build.protomaps.com/$(date +%Y%m%d).pmtiles \
  -o data/tiles/basemap.pmtiles

# Option B: regional via Protomaps web builder
# Visit https://app.protomaps.com/dashboard, box a region, download the resulting .pmtiles

# Option C: self-built from OSM PBF via Planetiler
docker run --rm \
  -v $PWD/data/osm:/data \
  -v $PWD/data/tiles:/out \
  ghcr.io/onthegomap/planetiler:latest \
  --osm_path=/data/germany-latest.osm.pbf --output=/out/basemap.pmtiles
```

**What it affects:** the visible map. Without a `.pmtiles` file present, MapLibre falls back to OSM raster tiles fetched from `tile.openstreetmap.org` (works but slower, no offline, and against OSM's tile-usage policy for production).

**Sizing notes:**

| Source | Size |
|--------|------|
| Protomaps daily planet | ~100 GB |
| Region (Germany) via Planetiler | ~3 GB |
| Single metro area | ~50–200 MB |

Once present, the map style at `data/frontend/style.json` (TBD) references it as `pmtiles:///tiles/basemap.pmtiles` and MapLibre serves it via Caddy + HTTP range requests.

---

### 8. Optional: terrain + hillshade

Terrain-RGB raster tiles for 3D terrain and computed hillshade.

```bash
# Mapzen terrain-tiles archive on AWS Open Data (free, no auth)
# Tile range depends on region; example for a continent-scale subset:
aws s3 cp --recursive --no-sign-request \
  s3://elevation-tiles-prod/v2/terrarium/ data/tiles/terrarium-staging/

# Repack to PMTiles (see Planetiler / pmtiles CLI)
```

**What it affects:** `setTerrain()` + hillshade layer in MapLibre. Without it, the map is flat.

**Sizing notes:** terrain-RGB at z0-z12 is ~50 GB. z0-z10 (continent-scale visible) is ~5 GB.

---

## Tearing down + reclaiming disk

```bash
# Stop a profile but keep its data
docker compose --profile pois down

# Drop a service's data (irreversible — rebuilds on next start)
docker compose down overpass
rm -rf data/overpass/*
```

Per-service disk: `du -sh data/*` for a quick overview.

## Planet-scale operations

The numbers below assume a single dedicated box (NVMe SSD, 64 GB RAM, 16+ CPU cores) and a fast network. Treat all times as **order-of-magnitude** — real-world variance from 0.5× to 2× is normal.

### Total disk for a full-planet deployment

| Layer | Compressed transient | Final on-disk | Notes |
|-------|---------------------|----------------|-------|
| Photon | 56 GB tar.bz2 | **~110 GB** | Lucene index, no diffs — full re-download on update |
| WOF (raw) | 5 GB | 68 GB during build → **0 after cleanup** | Drop `data/whosonfirst/` once Placeholder has built |
| Placeholder store | — | **~3–4 GB** | FTS-indexed final |
| libpostal | 0 (baked in image) | 0 | model loaded in RAM, ~2 GB working set |
| Valhalla PBF input | 75 GB | **~75 GB** | also reused by Overpass + OTP |
| Valhalla routing tiles | — | **~80 GB** | built from PBF |
| Valhalla DEM (SRTM) | 100 GB | **~100 GB** | skip with `BUILD_ELEVATION=False` to save it all |
| Overpass index | — | **~700 GB** | the disk hog; index is ~10× the source PBF |
| PMTiles basemap | 100 GB | **~100 GB** | static file, served as-is |
| Rails SQLite + state | — | <1 GB initially | grows with users + collections |
| **Subtotal** | **~336 GB transient** | **~1.15 TB after WOF cleanup** | |
| + Terrain-RGB tiles (optional) | 50 GB | 50 GB | for `setTerrain()` + hillshade |
| + OTP planet graph (optional) | depends on GTFS | 30–80 GB | not recommended at planet scale — region better |
| **All-on total** | — | **~1.3–1.5 TB** | |

`make disk` shows the live footprint per `data/` subdirectory.

### First-start times (planet, 100 Mbps home connection)

Assume parallel execution where possible. The critical path is Overpass; everything else fits inside that window.

| Component | Download | Build/extract/index | Cumulative wall-clock |
|-----------|----------|---------------------|------------------------|
| libpostal | 0 | <1 min | <1 min |
| WOF | ~7 min | n/a | ~7 min |
| Placeholder build | 0 | ~1.5 hours | ~1.5 hours after WOF |
| Photon | ~75 min | ~30 min | ~2 hours |
| PMTiles | ~135 min | 0 | ~2.5 hours |
| Valhalla PBF | ~100 min | parse + admins + DEM + tiles ≈ 1–2 days | **~1–2 days** |
| Overpass | ~100 min PBF download | ingest **~5–7 days** | **~1 week** |
| OTP (per-region only) | seconds | 10 min – 2 hours per region | n/a for planet |

On **1 Gbps**: every download row drops ~10× (e.g., Photon download = ~7 min). On a Hetzner AX52-class box, the critical path becomes pure CPU: ~5 days total for Overpass, ~1 day for Valhalla, hours for everything else.

### Update strategy per component

OSM publishes minute/hour/day diffs at [planet.openstreetmap.org/replication](https://planet.openstreetmap.org/replication/). Geofabrik publishes regional diffs too. Each component handles updates differently:

| Component | Mechanism | Bytes per update | Frequency | Time |
|-----------|-----------|------------------|-----------|------|
| **Photon** | Full re-download of Komoot's prebuilt index — no diff support | ~56 GB (planet) | Whenever Komoot publishes (~weekly) | ~2 hours |
| **WOF / Placeholder** | Re-run `make placeholder-data-rebuild` (download fresh WOF SQLite, rebuild store) | ~5 GB raw, builds to ~3 GB | Quarterly (WOF data is slow-moving) | ~1.5 hours |
| **libpostal** | Image re-pull (model rarely changes) | ~1.8 GB image | Years | <1 min |
| **Valhalla** | Built-in **replication from OSM diffs** (continuous) OR full rebuild from latest PBF | KB/min of diffs OR ~75 GB full | Continuous diffs OR weekly full rebuild | seconds per diff OR ~1 day rebuild |
| **Overpass** | **Continuous diffs** from `OVERPASS_DIFF_URL` (auto-pulled minutely) | KB/min | Real-time | negligible per tick |
| **PMTiles basemap** | Full re-download from Protomaps daily build | ~100 GB | Daily ideal, weekly fine | ~2.5 hours |
| **OTP** | New GTFS feed → rebuild graph (in-place) | varies per feed | When GTFS publisher updates | 10 min – 2 hours |
| **App image** | CI rebuilds on push → `make pull && make restart` | ~500 MB image, multi-arch | On every `app/**` change | ~5 min CI + ~30 s pull |

**Die ehrliche Wahrheit** (the honest truth / честная правда):

- **Overpass + Valhalla** have the cleanest update stories — set them up once, they self-update from diffs forever.
- **Photon + PMTiles** have the worst — full re-download every time. Bandwidth-heavy. Schedule them weekly during off-hours.
- **WOF/Placeholder** is the slowest to refresh per change (~1.5h rebuild) but rarely needs to (admin boundaries don't move much).

### Realistic maintenance cadence

```
Continuous:   Overpass diffs, Valhalla diffs            (auto, ~0 effort)
Weekly:       Photon refresh, PMTiles refresh           (~5 hours of bandwidth, scheduled cron)
Quarterly:    WOF + Placeholder rebuild                 (~1.5 hours)
On code push: App image                                 (~5 min CI)
```

Total monthly maintenance bandwidth at planet scale: ~1 TB (4× Photon + 4× PMTiles). Plan accordingly if you're on a metered link.

## Admin panel

The map page (/) lazy-loads an admin panel in the corner. Auth is HTTP Basic, configured via env vars:

```bash
echo 'ADMIN_USERNAME=admin' >> .env
echo 'ADMIN_PASSWORD=use-a-real-password' >> .env
docker compose --profile all up -d
```

Open the panel via the cog icon → toggle services and pick regions from the dropdown → click Save → confirm. Live progress streams through Turbo Streams over Action Cable.

A Go sidecar (`atlas-control`) owns docker socket access; Rails talks to it over HTTP. Both ship as separate images: `ghcr.io/dawarich-app/atlas/app:latest` (Rails) and `ghcr.io/dawarich-app/atlas/atlas-control:latest` (sidecar). The sidecar source lives at `atlas-control/`.

OpenAPI for the admin endpoints: `http://localhost:8484/api-docs/admin/swagger.yaml`.

## TODO

### Infrastructure
- [x] Pick name (Dawarich Atlas)
- [x] Define layer architecture
- [x] Pick tech stack (Rails 8 + Hotwire + Tailwind v4 + DaisyUI v5 + MapLibre)
- [x] Create directory structure
- [x] Write `compose.yml` with all services
- [x] Add bind mounts for local storage
- [x] Write `Caddyfile` (range, CORS, PMTiles MIME, reverse proxy to Rails)
- [x] Unpublish backend service ports (Docker-network-only)
- [ ] Test `compose.yml` boots cleanly on a small region (e.g., Liechtenstein PBF)
- [ ] Document expected first-boot timings per service

### Rails app scaffold
- [x] Run `rails new app --css=tailwind --javascript=esbuild --database=sqlite3 --skip-test --skip-system-test --skip-kamal`
- [x] Install DaisyUI v5 via bun + `@plugin "daisyui"` in Tailwind CSS
- [x] Add MapLibre + PMTiles to `app/javascript/` via esbuild
- [x] Service clients: `PhotonClient`, `ValhallaClient`, `OverpassClient`, `SearchOrchestrator`, `UpstreamService` base
- [x] API controllers: `/api/search`, `/api/whats-here`, `/api/route` with structured errors (VALIDATION_ERROR / UPSTREAM_UNAVAILABLE / UPSTREAM_ERROR)
- [x] `HomeController#index` renders full-screen MapLibre map + DaisyUI search bar overlay
- [x] Stimulus controllers: `map_controller.js` (mounts MapLibre + PMTiles, OSM fallback style), `search_controller.js` (debounced, keyboard nav, dropdown)
- [x] Health check endpoint `/up` (Rails 8 default)
- [x] Verified end-to-end: rails server boots, `/` renders, search input triggers `/api/search`, graceful "No results" when upstream unavailable
- [ ] Add RSpec, Pundit, OmniAuth providers (deferred — not blocking MVP)
- [ ] Generate Rails 8 built-in auth (`bin/rails g authentication`) — deferred
- [ ] Define core models: `User`, `Session`, `Collection`, `CollectionShare`, `Place` — deferred
- [ ] Pundit policies: `CollectionPolicy`, `PlacePolicy` — deferred
- [ ] Add `PlaceholderClient` + `LibpostalClient` and wire into `SearchOrchestrator` — deferred
- [ ] Add `/api/health` service-ping endpoint that probes each upstream — deferred

### Geocoding (Photon + Placeholder + libpostal)
- [x] Wire `/api/search` controller → `PhotonClient` (Placeholder + libpostal enrichment deferred)
- [x] Stimulus `search_controller.js` with debounce + dropdown UI + keyboard nav
- [ ] Boot Photon (internal port 2322), verify autocomplete via `docker compose exec app curl http://photon:2322`
- [ ] Boot Placeholder, verify admin-hierarchy query
- [ ] Boot libpostal, verify address parsing
- [ ] Extend `SearchOrchestrator` to also fan-out to Placeholder for admin enrichment

### Base map (Protomaps + Caddy)
- [ ] Download `planet.pmtiles` (or regional extract) into `data/tiles/`
- [ ] Pick a Protomaps Basemap style (light + dark)
- [ ] Register `pmtiles://` protocol in MapLibre Stimulus controller
- [ ] Render the map page at `/`

### Routing (Valhalla)
- [ ] Boot Valhalla, verify `/route` endpoint via `docker compose exec app curl http://valhalla:8002`
- [ ] Verify elevation tiles downloaded
- [ ] Wire `/api/route` to ValhallaClient
- [ ] Stimulus route panel: mode selector, from/to, draw `LineString` on map
- [ ] Support modes: auto, bicycle, pedestrian

### Terrain + hillshade
- [ ] Download Mapzen Terrain-RGB tiles for region
- [ ] Repackage as PMTiles → `data/tiles/terrain.pmtiles`
- [ ] Add `raster-dem` source + `setTerrain()` in MapLibre style
- [ ] Add hillshade layer

### Contour lines
- [ ] Run `phyghtmap` over regional SRTM to generate contour shapefile
- [ ] Convert to MBTiles, repackage as PMTiles
- [ ] Add contour vector layer to style

### POI lookup (Overpass)
- [ ] Boot Overpass, verify `/api/interpreter` via internal network
- [ ] Wire `/api/whats-here?lat=&lon=&radius=` to OverpassClient
- [ ] "Click to reveal POIs in 200m radius" with category icons
- [ ] Tag-aware popups (opening_hours, website, phone)

### Transit (OpenTripPlanner) — optional
- [ ] Download GTFS feeds for target region (Transitous)
- [ ] Drop GTFS .zip files + OSM .pbf into `data/gtfs/` and `data/osm/`
- [ ] Boot OTP, verify graph build succeeded
- [ ] Add transit-routing UI

### Time zone
- [ ] Add `tzinfo` + `rgeo` (or `timezone_resolver` gem) to Rails app
- [ ] Expose `/api/tz?lat=&lon=`

### Auth + scoped collections
- [ ] Rails 8 built-in auth working (email + password)
- [ ] OAuth: Google, GitHub via OmniAuth
- [ ] `Collection` model with `visibility` enum: `private | unlisted | link | public`
- [ ] `CollectionShare` for per-user sharing with `view | edit` permission
- [ ] `CollectionPolicy` (Pundit) enforces visibility rules
- [ ] CRUD UI: create collection, add/remove places, share via link or invite

### Productionization
- [ ] Healthcheck endpoints per service in compose (`healthcheck:` blocks)
- [ ] Logging/metrics — Prometheus exporters where available
- [ ] Backup strategy for `data/` (rsync to cold storage)
- [ ] Replication strategy — minute/hourly diff updaters for Overpass, Photon, Valhalla
- [ ] TLS (Caddy auto-provisions Let's Encrypt — add `tls iamfrey@gmail.com` to Caddyfile when domain is set)
- [ ] Decide license

### Ideas borrowed from Headway
- [ ] **Per-metro builds (BBBike-style)** — `make build-city CITY=berlin` that uses a city-sized PBF (~50–200 MB) instead of a country extract. Drops total disk for hobbyists from ~70 GB to ~5 GB per city.
- [ ] **Multi-modal transit multiplexer (Travelmux-pattern)** — once OTP is wired, add a router service that fuses `Valhalla` (walk/bike/drive) with `OTP` (transit + walk-leg) for true multi-modal queries.
- [ ] **Pelias alongside Photon** — for US/AU/CA address quality (OpenAddresses dataset that Photon lacks). Keep Photon as the default fast path; route to Pelias when locale heuristics suggest it. Same orchestrator pattern, new client.

## API

All endpoints live under `/api/v1/` and follow a single shape:

```json
{ "data": …, "meta": { "timestamp": "…", "upstream": "ok|unavailable|error", "count": … } }
```

Errors are uniform:

```json
{ "error": { "code": "VALIDATION_ERROR | UPSTREAM_UNAVAILABLE | UPSTREAM_ERROR", "message": "…" } }
```

| Method | Path | Sources fanned out (sequential) | Purpose |
|--------|------|----------------------------------|---------|
| `GET` | `/api/v1/search` | libpostal → Photon → Placeholder | Forward autocomplete with admin enrichment |
| `GET` | `/api/v1/reverse` | Photon reverse → Placeholder | Point → label + admin chain |
| `POST` | `/api/v1/reverse/batch` | Same as `reverse`, looped + cached + grid-snapped | **Batch reverse** for trip-scale geocoding (dawarich-style) |
| `GET` | `/api/v1/whats_here` | `ReverseOrchestrator` + Overpass | Label + nearby POIs in a radius |
| `GET` | `/api/v1/route` | Valhalla | Routing + elevation summary |
| `GET` | `/api/v1/geocode` | auto: forward or reverse | Combined endpoint — supply `q=` or `lat=&lon=` |

### Batch reverse geocoding

```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{
    "coords": [
      {"id": "p1", "lat": 52.5163, "lon": 13.3777},
      {"id": "p2", "lat": 48.1374, "lon": 11.5755}
    ],
    "lang": "en"
  }' \
  http://localhost:8484/api/v1/reverse/batch
```

Response:

```json
{
  "data": [
    { "id": "p1", "coord": { "lat": 52.5163, "lon": 13.3777 },
      "here": { ... }, "admin": { "country": "Germany", "state": "Berlin", "city": "Berlin", ... } },
    { "id": "p2", ... }
  ],
  "meta": {
    "count": 2,
    "cache_hits": 0,
    "cache_misses": 2,
    "upstream_errors": 0,
    "grid_precision": 4,
    "max_coords": 500
  }
}
```

Semantics:

- **Hard cap**: 500 coords per request (HTTP-friendly; for larger inputs page client-side).
- **Grid snap**: each coord's cache key is rounded to 4 decimal places (~11 m). Two phone-GPS readings of the same intersection collide on the cache key and return identical data — saving Photon load.
- **Cache TTL**: 30 days, in **Solid Cache** (Rails 8 default — uses the `cache` SQLite database in production).
- **Optional `id`**: caller-supplied identifier, echoed back per result; clients use it to correlate the response order with their own data structures.
- **Per-coord errors are non-fatal**: a single bad coord gets `{error: "…"}` while the rest of the batch processes normally.

Each request returns gracefully when an upstream is unreachable: forward/reverse return empty data + `meta.upstream: "unavailable"`; whats_here/route bubble the underlying 503/502 so clients can detect missing services.

### Interactive docs

OpenAPI 3.0 spec is generated from rswag integration specs in `app/spec/integration/api/v1/`. Mounted at:

- `/api-docs` → Swagger UI (browse + try endpoints)
- `/api-docs/v1/swagger.yaml` → raw OpenAPI YAML

### Regenerating the OpenAPI spec

After editing an rswag spec:

```bash
cd app
bundle exec rake rswag:specs:swaggerize
```

The output writes to `app/swagger/v1/swagger.yaml`, which is checked into git so the UI works without re-generating in production.

## CI / images

CI runs on GitHub Actions (config under `.github/workflows/`, TBD) and publishes four artifacts:

| Job | Trigger | Output |
|-----|---------|--------|
| `app-image` | push to `main` touching `app/**` | `ghcr.io/dawarich-app/atlas/app:latest` + `:@commit_hash@` (multi-arch: amd64 + arm64) |
| `control-plane-image` | push to `main` touching `atlas-control/**` | `ghcr.io/dawarich-app/atlas/atlas-control:latest` + `:@commit_hash@` (multi-arch) |
| `test-rails` | push / PR touching `app/**` | RSpec suite |
| `test-sidecar` | push / PR touching `atlas-control/**` | `go test ./...` |

Compose defaults consume those tags:

- `APP_IMAGE` defaults to `ghcr.io/dawarich-app/atlas/app:latest`
- `ATLAS_CONTROL_IMAGE` defaults to `ghcr.io/dawarich-app/atlas/atlas-control:latest`

Override either with `APP_IMAGE=<local>:dev APP_PULL_POLICY=never docker compose up -d` when iterating locally before pushing.

## License

Dawarich Atlas is licensed under the **GNU Affero General Public License v3.0** ([LICENSE](./LICENSE)) — the same license as Dawarich. Anyone running Atlas as a service must publish their modifications under the same license.

Upstream components retain their own licenses: OSM data is ODbL; Protomaps and MapLibre are BSD-3; Valhalla is MIT; Photon, Overpass and OpenTripPlanner are LGPL-3.0 or AGPL-3.0; Rails is MIT.
