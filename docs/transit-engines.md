# Transit engines

Atlas supports MOTIS 2.11.2 (the default) and OpenTripPlanner for public transport.
Walking, cycling, driving and map matching continue to use Valhalla.

In **Settings → Services → Public transport → Transit engine**, choose
**OpenTripPlanner** or **MOTIS**. Selection applies immediately and is persisted.
The admin Services page offers the same exclusive choice. Only the selected
engine has a service card and enable/disable control.

Atlas serializes lifecycle operations. It stops the previous engine, checks that
its container is no longer running, then enables and starts the selected engine.
A failed stop blocks the switch. A failed start stays visible as an error; Atlas
does not silently fall back to the other engine. Imports may take longer than
container startup; wait for **Ready** before requesting routes. Selection survives
app restarts. Other service and region changes retain their usual Apply workflow.

## Shared data

Both engines consume the existing `data/otp/region.osm.pbf` and `*.gtfs.zip` input
files. The directory name is retained for compatibility. MOTIS stores its own
imported graph under `data/motis`, and OTP retains `data/otp/graph.obj`.
Switching engines does not delete either cache or download the region again.
Applying regions refreshes shared inputs and restarts only the selected transit
engine. Data files and Docker images can remain cached; only one engine is enabled
and running through Atlas.

The MOTIS wrapper generates a configuration with routed walking transfers and
route shapes enabled. Its import begins on the current UTC date and includes up
to 365 days; actual service still depends on the dates in the GTFS feed. Restarting
refreshes that date and lets MOTIS reuse unchanged import artifacts. Expired GTFS
feeds must be updated; service calendars are not extrapolated.

## Deployment

`compose.yml` and `compose.dev.yml` include MOTIS and its startup wrapper. Deploy
`scripts/motis/start.sh` along with the Compose file. MOTIS is excluded from the
`all` profile to avoid starting an extra transit engine on existing deployments.
Use Settings to switch engines. Do not manually start a second engine with Docker;
Atlas's lifecycle guard cannot intercept commands run outside Atlas.

Optional settings: `MOTIS_THREADS` (4), `MOTIS_MEMORY` (4g). The app's
`TRANSIT_BACKEND` sets the initial default (`otp` or `motis`); a saved UI choice
wins. For an externally managed MOTIS API, set `MOTIS_URL`, `MOTIS_TIMEOUT` and
`MOTIS_OPEN_TIMEOUT` as needed. Docker lifecycle switching requires the full
control-plane deployment; Dokploy's API-only deployment manages containers
externally and can choose its routing adapter via `TRANSIT_BACKEND`.

The public Atlas transit API retains its existing response shape. MOTIS legs carry
`shape_format: google_polyline6` (OTP uses `google_polyline5`), ISO timestamps,
route names and walking segments. Direct walking-only results are excluded from
public-transport itineraries. No routing request is sent to both engines.

## Transport data sources

Settings → **Transport data** (also linked from the setup wizard) manages
sources separately from street regions. The initial reviewed catalog contains
VBB for Berlin/Brandenburg. Search by country, region or operator, or add an
HTTP(S) GTFS ZIP and an optional matching GTFS-RT **TripUpdates** URL manually.
The catalog lives in `app-phoenix/priv/transit/providers.json`; entries include
coverage, attribution, commercial-use conditions and the date of verification.

Connecting saves a selection. **Download & apply** downloads selected feeds and
rebuilds only the selected, enabled transit engine, if its street input exists.
It does not download PBFs, change the Settings region draft, or enable both engines.
The wizard downloads connected feeds during its transit installation. Until a
source selection is configured, existing region-preset GTFS behavior is retained.
Once configured, that selection replaces the engine's automatic ZIP discovery;
old cache files remain on disk but disabled sources are excluded from both engines.

Static updates are manual by default. **Daily updates** opts into a 03:00 UTC
refresh, serialized with other regional installations. A source update can take
the transport engine offline while its graph rebuilds. Live updates are polled
by the selected engine every minute; no application API request is sent directly
to the provider by the browser.

Downloads use temporary files and check ZIP readability and required GTFS table
names before replacing a cached file. This is a structural check, not a full
semantic GTFS validator. An invalid or unavailable download preserves the prior
file for that source URL and records a warning. Engine import can still reject
semantically invalid data. Matching realtime trip IDs and actual realtime health
are not verified by the catalog UI: **Live updates enabled** describes the
configuration, not guaranteed realtime coverage. Separate scheduled/realtime
fields in Atlas's journey API and live vehicles remain separate work.

An optional HTTP header supports API keys, applied to this source's static and
realtime URLs. Credentials are held in the server Settings database and generated
engine configuration, never redisplayed in the form. Treat the database and
`data/otp` as sensitive. MOTIS/OTP must have permission to read the generated
configuration (default deployment uses the same runtime UID/GID). Keep the key
field blank while editing to preserve it; use **Remove saved API key** to clear it.

Managed files are `data/gtfs/atlas-feeds/*`, `data/otp/atlas-feeds/*`,
`motis-datasets.yml`, `atlas-sources.json` and managed sections of
`build-config.json` / `router-config.json`. Persistent source IDs namespace the
same feed in MOTIS and OTP. A changed GTFS URL gets a separate download cache,
so an old provider's ZIP is never mistaken for its replacement.

Catalog references:
- https://unternehmen.vbb.de/digitale-services/datensaetze/
- https://production.gtfsrt.vbb.de/
- https://github.com/motis-project/motis/blob/v2.11.2/docs/setup.md
- https://docs.opentripplanner.org/en/latest/GTFS-RT-Config/
