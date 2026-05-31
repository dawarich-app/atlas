import maplibregl from "../../vendor/maplibre-gl"

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
    const initialZoom = parseFloat(this.el.dataset.zoom || "5")

    const style = tilesUrl ? tilesUrl : OSM_RASTER_FALLBACK

    this.map = new maplibregl.Map({
      container: this.el,
      style: style,
      center: initialCenter,
      zoom: initialZoom
    })

    // Match Rails: controls bottom-right, scale bottom-left.
    this.map.addControl(new maplibregl.NavigationControl({
      showCompass: true,
      visualizePitch: true
    }), "bottom-right")
    this.map.addControl(new maplibregl.ScaleControl({
      maxWidth: 120,
      unit: "metric"
    }), "bottom-left")
    this.markers = {}

    this.handleEvent("map:fly_to", ({ lat, lon, zoom }) => {
      this.map.flyTo({ center: [lon, lat], zoom: zoom || 14 })
    })

    this.handleEvent("map:add_marker", ({ id, lat, lon, label }) => {
      const marker = new maplibregl.Marker()
        .setLngLat([lon, lat])
        .setPopup(new maplibregl.Popup().setHTML(`<strong>${label}</strong>`))
        .addTo(this.map)
      this.markers[id] = marker
    })

    this.handleEvent("map:clear_markers", () => {
      Object.values(this.markers).forEach(m => m.remove())
      this.markers = {}
    })

    this.routeGeoJSON = null

    this.handleEvent("map:draw_route", ({ geojson }) => {
      this.routeGeoJSON = geojson
      this._renderRoute()
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

      // Persist what we want to re-add on the new style.
      const savedMarkers = Object.entries(this.markers || {}).map(([id, m]) => {
        const lngLat = m.getLngLat()
        const popup = m.getPopup()
        return {
          id,
          lat: lngLat.lat,
          lon: lngLat.lng,
          html: popup ? popup.getElement()?.querySelector(".maplibregl-popup-content")?.innerHTML : null
        }
      })

      // Drop the live marker DOM; we re-create after styledata fires.
      Object.values(this.markers || {}).forEach(m => m.remove())
      this.markers = {}

      const onStyle = () => {
        // Re-add markers.
        savedMarkers.forEach(({ id, lat, lon, html }) => {
          const marker = new maplibregl.Marker().setLngLat([lon, lat])
          if (html) marker.setPopup(new maplibregl.Popup().setHTML(html))
          marker.addTo(this.map)
          this.markers[id] = marker
        })
        // Re-add the route source/layer if we had one.
        if (this.routeGeoJSON) this._renderRoute()
      }

      this.map.once("styledata", onStyle)
      this.map.setStyle(nextStyle)
    })
  },

  _renderRoute() {
    const geojson = this.routeGeoJSON
    if (!geojson) return

    if (this.map.getSource("route")) {
      this.map.getSource("route").setData(geojson)
      return
    }

    const addRoute = () => {
      this.map.addSource("route", { type: "geojson", data: geojson })
      this.map.addLayer({
        id: "route-line",
        type: "line",
        source: "route",
        paint: { "line-color": "#3b82f6", "line-width": 4 }
      })
    }

    if (this.map.isStyleLoaded()) {
      addRoute()
    } else {
      this.map.once("load", addRoute)
    }
  },

  destroyed() {
    if (this.map) this.map.remove()
  }
}
