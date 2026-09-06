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
