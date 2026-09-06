# Map search

Search covers the data installed in Photon, independently of the current map view.
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
concurrent requests, 4096 cells, 32 subdivision levels and approximately 60 seconds
(plus any in-flight HTTP timeout). More specific queries can finish sooner.

Cluster counts use accessible HTML buttons and the local application font, so
number labels do not require an external glyph server. MapLibre performs the
clustering in its worker; only visible clusters and points create DOM markers.
