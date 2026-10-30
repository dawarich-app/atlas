import maplibregl from "../vendor/maplibre-gl"
import { buildBasemapStyle, registerPmtiles } from "./lib/basemap"

const el = document.getElementById("static-map")

if (el) {
  registerPmtiles(maplibregl)

  let routeGeojson = null
  if (el.dataset.routeGeojson) {
    try { routeGeojson = JSON.parse(el.dataset.routeGeojson) } catch (_error) { /* invalid route */ }
  }

  const map = new maplibregl.Map({
    container: el,
    style: buildBasemapStyle(el.dataset.tilesUrl, el.dataset.theme),
    center: [parseFloat(el.dataset.lon), parseFloat(el.dataset.lat)],
    zoom: parseFloat(el.dataset.zoom),
    interactive: false
  })

  map.on("load", () => {
    if (!routeGeojson?.features?.length) return

    map.addSource("route", { type: "geojson", data: routeGeojson })
    map.addLayer({
      id: "route-line",
      type: "line",
      source: "route",
      paint: { "line-color": "#3b82f6", "line-width": 4 }
    })

    if (el.dataset.fit !== "1") return
    const coords = routeGeojson.features.flatMap(feature =>
      feature.geometry?.type === "LineString" ? feature.geometry.coordinates : [])
    if (coords.length < 2) return

    const bounds = coords.reduce((box, coord) => box.extend(coord),
      new maplibregl.LngLatBounds(coords[0], coords[0]))
    map.fitBounds(bounds, { padding: 40, animate: false })
  })

  map.on("idle", () => {
    window.__atlasStaticMapReady = true
    window.dispatchEvent(new CustomEvent("atlas:static-map-ready"))
  })
}
