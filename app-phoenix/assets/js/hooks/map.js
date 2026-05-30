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

    this.handleEvent("map:draw_route", ({ geojson }) => {
      if (this.map.getSource("route")) {
        this.map.getSource("route").setData(geojson)
      } else {
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
      }
    })
  },

  destroyed() {
    if (this.map) this.map.remove()
  }
}
