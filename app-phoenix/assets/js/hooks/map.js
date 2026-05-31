import maplibregl from "../../vendor/maplibre-gl"

export default {
  mounted() {
    const tilesUrl = this.el.dataset.tilesUrl
    const theme = this.el.dataset.theme || "atlas-light"
    const initialCenter = JSON.parse(this.el.dataset.center || "[10.4515, 51.1657]")
    const initialZoom = parseFloat(this.el.dataset.zoom || "5")

    this.map = new maplibregl.Map({
      container: this.el,
      style: tilesUrl,
      center: initialCenter,
      zoom: initialZoom
    })

    this.map.addControl(new maplibregl.NavigationControl())
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
