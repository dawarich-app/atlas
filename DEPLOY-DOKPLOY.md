# Deploying Atlas on Dokploy

On Dokploy, Atlas runs as a normal compose app — services are declared in
`compose.dokploy.yml` and managed by Dokploy (no docker socket; the app reaches
upstreams via env URLs). As shipped it's **minimal**: just the map + your own
Photon. Add routing / POIs / transit later by uncommenting blocks.

> Self-hosters who want the click-to-enable **control panel** use the bundled
> `compose.yml` (`docker compose up -d`) instead.

## Minimal: Atlas + your existing Photon

This gets you the map and search, pointed at a Photon you already run.

### Connect to Photon over a shared Docker network (recommended)

If your Photon's public endpoint enforces an API key (a Caddy/proxy in front
of it), Atlas can't use that URL — its Photon client sends no key. Connect
straight to the `photon` container instead, which has no auth:

1. **On the host**, create the shared network once:
   ```bash
   docker network create photon-net
   ```
2. **In your Photon compose**, put the `photon` service on it:
   ```yaml
   services:
     photon:
       networks:
         - internal
         - photon-net        # add
   networks:
     internal: {}
     photon-net:             # add
       external: true
   ```
   Redeploy the Photon stack.
3. New Dokploy **Compose** app. Either **paste** `compose.dokploy.yml` in **raw**
   mode (the Caddyfile is carried inline via a `configs:` block — no repo file or
   File Mount needed), or point it at this repo with **Compose Path** =
   `compose.dokploy.yml`. It already joins `photon-net`.
4. **Environment**:

   | Variable | Value |
   |---|---|
   | `ATLAS_HOST` | `atlas.example.com` (domain; Traefik + `PHX_HOST`) |
   | `PHOTON_URL` | `http://photon:2322` (the container, over `photon-net`) |
   | `SECRET_KEY_BASE` | `openssl rand -hex 64` |
   | `ADMIN_USERNAME` / `ADMIN_PASSWORD` | for `/admin` |

5. Deploy. The app reaches `photon:2322` directly, bypassing the API-key proxy.

`PHOTON_URL` points at the Photon **root** — the app appends `/api`,
`/reverse`, … itself.

### Or a keyless public URL (no shared network)

If your Photon endpoint needs no key, skip the network: set
`PHOTON_URL=https://your-photon.example.com`, and remove the `photon-net`
network (top of the file + the `photon-net` line under `app.networks`).

### Expected: a "control plane degraded" notice in Settings
No docker socket → the in-app panel can't manage containers, so **Settings
shows a "Docker socket unreachable" banner and the service toggles are inert.**
Expected here — you manage services in Dokploy. (A clean "external services"
mode that hides this can be added behind an env flag — ask if you want it.)

## Later: add routing / POIs / transit

These build from OSM data, so there's an extra data step:

1. In `compose.dokploy.yml`, uncomment the service block(s) you want
   (`valhalla` = routing, `overpass` = POIs, `otp` = transit) and redeploy.
2. Map → **Settings** → pick a region → **Save & apply**. The app downloads +
   merges the OSM extract into the shared `atlas_osm` volume.
3. In Dokploy, **restart** the service so it rebuilds from that data. (They're
   heavy — a country extract is tens of GB; overpass/otp want several GB RAM
   during ingest.)

Need a **bundled** Photon instead of an external one? Uncomment the `photon`
block, add `atlas_photon:` under `volumes:`, and set `PHOTON_URL=http://photon:2322`.

## Notes

- SQLite by default (volume `atlas_app`). For Postgres set `DATABASE_URL` and
  use an image built with `ATLAS_DB_ADAPTER=postgres`.
- The basemap uses external tiles out of the box; Caddy serves downloaded tile
  packs from the `atlas_tiles` volume if you add one later.
- Plain VPS / `docker compose up`? Use `compose.yml` with the full control panel.
