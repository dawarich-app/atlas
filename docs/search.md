# Map search

Search and Places share one Search panel. Type a name or address immediately,
choose an optional category, or do both. Category suggestions are explicitly
labelled **Category** and only apply when clicked; choosing one consumes the
category text. Quick chips toggle on/off, and **More categories** opens the full
catalog. Several categories match with OR semantics. If a filter gives no matches,
**Search all categories** removes it while keeping the query.

**All installed data** is the default scope. **This map area** captures a bounding
box; moving or zooming the map keeps those results until **Search here** is clicked.
The UI identifies results from the previous area. Query, categories and captured
bounds are stored in the URL. **Reset all** cancels loading and clears the query,
filters and markers, returning to the default scope.

Name/address queries use Photon with category tags forwarded to every subdivided
request. A category with no text uses the installed Overpass dataset, including
nodes, ways and relations, collected in pages of 500 with two requests in flight.
Its coverage can differ from Photon if different extracts or update dates were
installed. Overpass timeout remarks are treated as incomplete, even with HTTP 200.


In the default scope, search covers the installed dataset independently of the current map view.
The map displays all collected matches in numbered clusters; clicking one zooms
into its members. Zooming and panning change the presentation, not the result set.
**Show all** fits every match. Individual points retain their address/OSM popups.
The sidebar shows up to 40 ranked suggestions so thousands of matches do not create
thousands of HTML rows.

Photon normally caps each response at 50 results. Atlas asks for 50 with street
deduplication disabled, then splits every full bounding box until its children
return fewer results. Repeated OSM IDs on cell boundaries count once. This uses
only Photon's HTTP API and does not require Overpass or a new index. External
Photon instances must allow at least 50 results per request (the standard default).

Searching runs in a cancellable background task. Changing or clearing the query,
Escape, or selecting a suggestion cancels the previous task and discards its late
updates. Ranked suggestions remain usable while the rest of the map loads.

Counts describe matches in the installed geocoder, not a live inventory of
businesses: related names, old names, parking and other mapped objects may match.
Freshness and coverage follow the installed OSM/Photon dataset.

An upstream failure, an overflowing coincident location or an excessively broad
query is shown as **incomplete**, never as a full total. A query uses at most four
concurrent requests (two for Overpass), 4096 cells, 32 subdivision levels and approximately 60 seconds
(plus any in-flight HTTP timeout). More specific queries can finish sooner.

Cluster counts use accessible HTML buttons and the local application font, so
number labels do not require an external glyph server. MapLibre performs the
clustering in its worker; only visible clusters and points create DOM markers.

During progressive loading, visible markers stay in place until the worker has
indexed the next batch. Nearby clusters reuse their existing marker elements,
updating counts and click targets together. A soft halo pulses around clusters
and individual points while loading; their bodies and labels remain opaque.
The halo stops after the final batch is rendered, and reduced-motion preferences
show a static ring. Clearing a search still removes its markers immediately.
