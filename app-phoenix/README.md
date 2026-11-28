# Atlas

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## MOTIS transport map API

The mobile transport layer uses four read-only endpoints, with the usual
`{data, meta}` envelope. They require `TRANSIT_BACKEND=motis` (OTP returns 501).

- `GET /api/v1/transport/stops?bbox=west,south,east,north` returns MOTIS platform
  stops with timetable IDs, coordinates, names, and modes. No optional grouped
  stop/geocoding index is needed. Results are capped at 1,000 stops.
- `GET /api/v1/transport/lines?bbox=west,south,east,north&zoom=14` returns service
  segments for the next hour with polyline5 geometry, colors and trip IDs. Zoom
  must be 11..18. Repeated shapes for the same service are deduplicated and
  capped at 600. If MOTIS rejects a dense area as containing too many trips,
  returns an empty list with `meta.truncated=true` and `meta.zoom_in=true`, so
  clients can keep displaying stops while asking the user to zoom in.
- `GET /api/v1/transport/departures?stop_id=...` requests the next 20 departures
  at that exact platform, including schedule/live times and cancellation flags.
- `GET /api/v1/transport/trip?trip_id=...` returns the service and intermediate
  stops. Stop and trip IDs are opaque, URL-encoded values from MOTIS.

Bounding boxes must have ordered, valid coordinates and cover at most 0.04
square degrees, with neither side exceeding 0.5 degrees. Responses include
`meta.timestamp`; capped responses set `meta.truncated`. Times sent to MOTIS use
whole seconds to avoid its fractional-timestamp parsing bug. Upstream failures
retain the API's existing structured 502/503 behavior. No arbitrary upstream
paths or URLs are accepted.

### Live departure timetables

Transport departure boards preserve MOTIS scheduled and predicted departure times, realtime flags, cancellations, and scheduled/current platforms. Responses use `Cache-Control: no-store`; the response metadata timestamp is the API retrieval time, not the last provider update. Live predictions require matching static GTFS and GTFS-Realtime feeds.

Keep connected timetables current using the transport sources refresh action and optional daily automatic refresh. If MOTIS logs many `trip_resolve_error` events, refresh static GTFS before troubleshooting live predictions. Set `HOST_PROJECT_DIR` in the project `.env` to the absolute **Atlas backend checkout** path, then recreate the app service after changing it. An incorrect path can select an empty Compose project; restart commands now report missing containers as errors. A timetable download only takes effect after the transit engine restarts and finishes importing.
