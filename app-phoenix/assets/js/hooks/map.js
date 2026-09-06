import maplibregl from "../../vendor/maplibre-gl"
import SearchClusters from "./search_clusters"
import RouteEndpoints from "./route_endpoints"
import RouteLabels from "./route_labels"

// Hardcoded OSM raster fallback — used when no TILES_URL is configured.
// Matches the Rails JS controller's OSM_RASTER_FALLBACK byte-for-byte.
const OSM_RASTER_FALLBACK = {
  version: 8,
  sources: {
    osm: {
      type: "raster",
      tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      tileSize: 256,
      attribution: "© OpenStreetMap contributors"
    }
  },
  layers: [{ id: "osm", type: "raster", source: "osm" }]
}

export default {
  mounted() {
    const tilesUrl = this.el.dataset.tilesUrl
    const theme = this.el.dataset.theme || "forest-patina"
    const initialCenter = JSON.parse(this.el.dataset.center || "[10.4515, 51.1657]")
    const initialBounds = this.el.dataset.bounds ? JSON.parse(this.el.dataset.bounds) : null
    const initialZoom = parseFloat(this.el.dataset.zoom || "5")

    const style = tilesUrl ? tilesUrl : OSM_RASTER_FALLBACK

    this.map = new maplibregl.Map({
      container: this.el,
      style: style,
      center: initialCenter,
      zoom: initialZoom,
      ...(initialBounds ? {bounds: [[initialBounds[0], initialBounds[1]], [initialBounds[2], initialBounds[3]]]} : {})
    })

    this.resizeObserver = new ResizeObserver(() => this.map.resize())
    this.resizeObserver.observe(this.el)

    // Match Rails: controls bottom-right, scale bottom-left.
    this.map.addControl(new maplibregl.NavigationControl({
      showCompass: true,
      visualizePitch: true
    }), "bottom-right")
    this.map.addControl(new maplibregl.ScaleControl({
      maxWidth: 120,
      unit: "metric"
    }), "bottom-left")
    this.searchClusters = new SearchClusters(this.map, maplibregl, resultMarker)

    this.handleEvent("map:fly_to", ({ lat, lon, zoom }) => {
      this.map.flyTo({ center: [lon, lat], zoom: zoom || 14 }, { atlasProgrammatic: true })
    })

    this.handleEvent("map:fit_results", () => this.searchClusters.fitBounds())

    this.handleEvent("map:set_results", ({ points, loading = false }) => {
      this.searchClusters.setPoints(points, loading)
    })
    this.handleEvent("map:search_loading", ({ loading }) => this.searchClusters.setLoading(loading))

    const reportViewport = () => {
      const bounds = this.map.getBounds()
      const west = bounds.getWest(), east = bounds.getEast()
      // A wrapped view spans the antimeridian; use a valid encompassing box.
      const bbox = [Math.max(-180, west), Math.max(-90, bounds.getSouth()),
        Math.min(180, east), Math.min(90, bounds.getNorth())]
      if (bbox[0] >= bbox[2]) { bbox[0] = -180; bbox[2] = 180 }
      this.pushEvent("viewport_changed", { bbox })
    }
    this.map.on("load", reportViewport)
    this.map.on("moveend", reportViewport)

    this.routeGeoJSON = null
    this._renderedRoute = null
    this.map.on("idle", () => {
      if (this.routeGeoJSON &&
          (this._renderedRoute !== this.routeGeoJSON || !this.map.getSource("route"))) {
        this._renderRoute()
      }
    })
    this.routeLabels = new RouteLabels(this.map, maplibregl)
    this.routeEndpoints = new RouteEndpoints(this.map, maplibregl)
    this.handleEvent("map:set_route_endpoints", ({points}) => this.routeEndpoints.setPoints(points))

    this.handleEvent("map:draw_route", ({ geojson }) => {
      this.routeGeoJSON = geojson
      this.routeLabels.setRoute(geojson)
      this._renderRoute()
      const coordinates = (geojson.features || []).flatMap((feature) => feature.geometry.coordinates)
      if (coordinates.length > 0) {
        this.routeEndpoints.fit(coordinates)
      }
    })

    // Pick-point flow: when the user clicks the pin button next to From/To,
    // the LiveView pushes `map:enter_picker` with `{field}`. We arm a one-shot
    // click listener; on next map click we push `point_picked` back with the
    // coords and reset cursor.
    this.activePicker = null
    this._pickerClickHandler = null
    this._tilesUrl = this.el.dataset.tilesUrl || null

    this.handleEvent("map:enter_picker", ({ field }) => {
      if (!field) return

      // If already arming, replace the field but reuse the same handler.
      this.activePicker = field
      this.map.getCanvas().style.cursor = "crosshair"

      if (this._pickerClickHandler) return

      this._pickerClickHandler = (e) => {
        const field = this.activePicker
        if (!field) return
        const { lng, lat } = e.lngLat
        this.activePicker = null
        this.map.getCanvas().style.cursor = ""
        this.map.off("click", this._pickerClickHandler)
        this._pickerClickHandler = null
        this.pushEvent("point_picked", { field, lat, lon: lng })
      }

      this.map.on("click", this._pickerClickHandler)
    })

    this.handleEvent("map:set_style", ({ url }) => {
      this._tilesUrl = url || null
      const nextStyle = url ? url : OSM_RASTER_FALLBACK

      // The cluster source restores itself from its current dataset on style.load.
      this.map.once("style.load", () => {
        if (this.routeGeoJSON) this._renderRoute()
      })
      this.map.setStyle(nextStyle)
    })
  },

  _renderRoute() {
    const geojson = this.routeGeoJSON
    if (!geojson) return

    if (this.map.getSource("route")) {
      this.map.getSource("route").setData(geojson)
      this._renderedRoute = geojson
      return
    }

    const addRoute = () => {
      this.map.addSource("route", { type: "geojson", data: geojson })
      this.map.addLayer({
        id: "route-casing", type: "line", source: "route",
        filter: ["!=", ["get", "mode"], "WALK"],
        layout: {"line-cap": "round", "line-join": "round"},
        paint: {"line-color": "#ffffff", "line-width": 9, "line-opacity": 0.8}
      })
      this.map.addLayer({
        id: "route-line",
        type: "line",
        source: "route",
        filter: ["!=", ["get", "mode"], "WALK"],
        layout: {"line-cap": "round", "line-join": "round"},
        paint: { "line-color": ["coalesce", ["get", "color"], "#2563eb"], "line-width": 6 }
      })
      this.map.addLayer({
        id: "route-walk",
        type: "line",
        source: "route",
        filter: ["==", ["get", "mode"], "WALK"],
        layout: {"line-cap": "round", "line-join": "round"},
        paint: { "line-color": "#475569", "line-width": 7, "line-dasharray": [0, 1.8] }
      })
      this._renderedRoute = geojson
    }

    if (this.map.isStyleLoaded()) {
      addRoute()
    }
    // isStyleLoaded can be false while raster tiles load after a pan, long
    // after the one-time map load event. The idle handler retries the latest
    // route and also restores it after a style change.
  },

  destroyed() {
    if (this.resizeObserver) this.resizeObserver.disconnect()
    if (this.searchClusters) this.searchClusters.destroy()
    if (this.routeEndpoints) this.routeEndpoints.destroy()
    if (this.routeLabels) this.routeLabels.destroy()
    if (this.map) this.map.remove()
  }
}

// A search pin, styled like the Rails POI marker: an accent dot that reacts to
// the cursor. MapLibre's default marker has no hover affordance at all, so
// nothing told you a pin could be clicked.
// One builder for both paths, so a marker rebuilt after a style swap is
// identical to the one first drawn — same pin, same popup, same OSM link.
// `_atlasPoint` is what makes that rebuild possible without reading DOM.
function resultMarker(p) {
  const marker = new maplibregl.Marker({ element: resultPin(p.label) })
    .setLngLat([p.lon, p.lat])
    .setPopup(
      new maplibregl.Popup({ offset: 14, maxWidth: "320px", className: "apo-poi-popup" })
        .setHTML(resultPopupHTML(p))
    )
  marker._atlasPoint = p
  return marker
}

function resultPin(label) {
  // Two elements on purpose: MapLibre positions a marker by writing
  // `transform: translate(...)` onto the element it is given, so any hover
  // transform there would replace the translate and fling the pin to the map
  // origin. The outer div stays MapLibre's; the inner dot is ours to animate.
  const el = document.createElement("div")
  el.className = "apo-poi-marker"
  el.title = label || ""

  const dot = document.createElement("span")
  dot.className = "apo-poi-marker-dot"
  el.appendChild(dot)

  return el
}

function escapeAttr(value) {
  return String(value == null ? "" : value).replace(/"/g, "&quot;").replace(/</g, "&lt;")
}

function escapeText(value) {
  const div = document.createElement("div")
  div.textContent = value == null ? "" : String(value)
  return div.innerHTML
}

// A search result knows less than an Overpass POI: Photon returns no tag block,
// so there are no opening hours, phone or website rows to show. The popup lists
// what this result actually carries and omits the rest, rather than rendering a
// scaffold of empty fields.
function infoRow(value) {
  return `<div class="apo-popup-row"><span class="apo-popup-row-value">${escapeText(value)}</span></div>`
}

function resultPopupHTML(p) {
  const rows = []
  if (p.address) rows.push(infoRow(p.address))
  if (p.region) rows.push(infoRow(p.region))
  rows.push(infoRow(`${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}`))

  const footer = p.osm_url
    ? `<footer class="apo-popup-actions">
         <a class="apo-popup-secondary" target="_blank" rel="noopener" href="${escapeAttr(p.osm_url)}">
           <span>View on OpenStreetMap</span>
         </a>
       </footer>`
    : ""

  return `
    <div class="apo-popup">
      <header class="apo-popup-header">
        <div class="apo-popup-name">${escapeText(p.label)}</div>
        <div class="apo-popup-meta">
          <span class="apo-popup-category">${escapeText(p.category)}</span>
        </div>
      </header>
      <div class="apo-popup-rows">${rows.join("")}</div>
      ${footer}
    </div>
  `
}
