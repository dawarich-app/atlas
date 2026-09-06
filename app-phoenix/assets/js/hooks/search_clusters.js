// Cluster the entire search dataset in MapLibre's worker. Only visible clusters
// and leaves need DOM markers; counts use local fonts, including offline styles
// without a glyph server.
const SOURCE = "search-results"
const LAYER = "search-results-source"

export default class SearchClusters {
  constructor(map, maplibre, makePointMarker) {
    this.map = map
    this.maplibre = maplibre
    this.makePointMarker = makePointMarker
    this.points = []
    this.markers = new Map()
    this.render = () => this.updateVisible()
    this.restore = () => this.restoreSource()
    map.on("render", this.render)
    map.on("style.load", this.restore)
    if (map.isStyleLoaded()) this.restoreSource()
  }

  setPoints(points) {
    this.points = points || []
    this.clearMarkers()
    const source = this.map.getSource(SOURCE)
    if (source) source.setData(this.geojson())
    else if (this.map.isStyleLoaded()) this.restoreSource()
  }

  geojson() {
    return {
      type: "FeatureCollection",
      features: this.points.map((p) => ({
        type: "Feature",
        geometry: { type: "Point", coordinates: [p.lon, p.lat] },
        properties: p
      }))
    }
  }

  restoreSource() {
    this.clearMarkers()
    if (this.map.getSource(SOURCE)) return
    this.map.addSource(SOURCE, {
      type: "geojson", data: this.geojson(), cluster: true,
      clusterRadius: 55, clusterMaxZoom: 20, maxzoom: 22
    })
    // A layer makes MapLibre load the source's visible tiles. The actual
    // markers are accessible HTML buttons and existing place popups.
    this.map.addLayer({
      id: LAYER, type: "circle", source: SOURCE,
      paint: { "circle-radius": 0, "circle-opacity": 0 }
    })
  }

  updateVisible() {
    if (!this.map.getSource(SOURCE) || !this.map.isSourceLoaded(SOURCE)) return
    const visible = new Set()
    const bounds = this.map.getBounds()
    const center = this.map.getCenter().lng

    for (const feature of this.map.querySourceFeatures(SOURCE)) {
      const p = feature.properties
      const [rawLon, lat] = p.cluster ? feature.geometry.coordinates : [Number(p.lon), Number(p.lat)]
      const lon = rawLon + 360 * Math.round((center - rawLon) / 360)
      if (!bounds.contains([lon, lat])) continue
      const key = p.cluster ? `cluster:${p.cluster_id}:${p.point_count}` : `point:${p.id}:${rawLon}:${lat}`
      if (visible.has(key)) continue // tile boundaries can return a feature twice
      visible.add(key)
      if (!this.markers.has(key)) {
        const marker = p.cluster
          ? this.clusterMarker(p, [lon, lat])
          : this.makePointMarker(p)
        marker.setLngLat([lon, lat]).addTo(this.map)
        this.markers.set(key, marker)
      } else {
        this.markers.get(key).setLngLat([lon, lat])
      }
    }

    for (const [key, marker] of this.markers) {
      if (!visible.has(key)) {
        marker.remove()
        this.markers.delete(key)
      }
    }
  }

  clusterMarker(properties, coordinates) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "atlas-search-cluster"
    button.dataset.count = properties.point_count
    button.textContent = Number(properties.point_count).toLocaleString()
    button.setAttribute("aria-label", `Zoom into ${properties.point_count} matches`)
    button.addEventListener("click", async (event) => {
      event.stopPropagation()
      try {
        const source = this.map.getSource(SOURCE)
        if (!source) return
        const zoom = await source.getClusterExpansionZoom(properties.cluster_id)
        this.map.easeTo({ center: coordinates, zoom: Math.min(zoom, this.map.getMaxZoom()) })
      } catch (_) {
        // A new query or style may have replaced the source while awaiting it.
      }
    })
    const marker = new this.maplibre.Marker({ element: button }).setLngLat(coordinates)
    // MapLibre installs its generic marker label in the constructor.
    button.setAttribute("aria-label", `Zoom into ${properties.point_count} matches`)
    return marker
  }

  fitBounds() {
    if (!this.points.length) return
    const bounds = this.points.reduce(
      (bounds, p) => bounds.extend([p.lon, p.lat]), new this.maplibre.LngLatBounds()
    )
    this.map.fitBounds(bounds, { padding: 45, maxZoom: 15 })
  }

  clearMarkers() {
    for (const marker of this.markers.values()) marker.remove()
    this.markers.clear()
  }

  destroy() {
    this.map.off("render", this.render)
    this.map.off("style.load", this.restore)
    this.clearMarkers()
  }
}
