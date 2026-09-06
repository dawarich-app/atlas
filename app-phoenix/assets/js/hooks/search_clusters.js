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
    this.loading = false
    this.pendingData = false
    this.revision = 0
    this.renderedRevision = -1
    this.renderedZoom = null
    this.markers = new Map()
    this.render = () => this.updateVisible()
    this.restore = () => this.restoreSource()
    map.on("render", this.render)
    map.on("style.load", this.restore)
    if (map.isStyleLoaded()) this.restoreSource()
  }

  setPoints(points, loading = false) {
    this.points = points || []
    this.revision += 1
    this.pendingData = this.points.length > 0
    this.setLoading(loading)
    // Keep the currently drawn snapshot while the worker rebuilds its index.
    // Explicit clear/dismiss still removes everything immediately.
    if (!this.points.length) this.clearMarkers()
    const source = this.map.getSource(SOURCE)
    if (source) source.setData(this.geojson())
    else if (this.map.isStyleLoaded()) this.restoreSource()
  }

  setLoading(loading) {
    this.loading = Boolean(loading)
    for (const marker of this.markers.values()) this.updateLoading(marker)
  }

  updateLoading(marker) {
    const busy = this.loading || this.pendingData
    const element = marker.getElement()
    element.classList.toggle("atlas-marker-loading", busy)
    element.setAttribute("aria-busy", String(busy))
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
    // A queued source response must never resurrect explicitly cleared results.
    if (!this.points.length) return
    const bounds = this.map.getBounds()
    const center = this.map.getCenter().lng
    const zoom = this.map.getZoom()
    const updating = this.renderedRevision !== this.revision && this.renderedZoom === zoom
    const visible = new Map()

    for (const feature of this.map.querySourceFeatures(SOURCE)) {
      const p = feature.properties
      const [rawLon, lat] = p.cluster ? feature.geometry.coordinates : [Number(p.lon), Number(p.lat)]
      const lon = rawLon + 360 * Math.round((center - rawLon) / 360)
      if (!bounds.contains([lon, lat])) continue
      const key = p.cluster ? `cluster:${p.cluster_id}` : `point:${p.id}:${rawLon}:${lat}`
      if (!visible.has(key)) visible.set(key, {p, coordinates: [lon, lat]})
    }

    const remaining = new Map(this.markers)
    const next = new Map()
    // Reserve exact identities before matching clusters whose worker IDs changed.
    for (const [key, item] of visible) {
      const marker = remaining.get(key)
      if (marker && (!item.p.cluster || !updating || this.distance(marker, item.coordinates) <= 55)) {
        next.set(key, marker)
        remaining.delete(key)
      }
    }
    for (const [key, item] of visible) {
      if (next.has(key)) continue
      let marker
      if (updating && item.p.cluster) {
        const match = this.nearestCluster(remaining, item.coordinates)
        if (match) {
          marker = match[1]
          remaining.delete(match[0])
        }
      }
      if (!marker) {
        marker = item.p.cluster ? this.clusterMarker() : this.makePointMarker(item.p)
        marker.setLngLat(item.coordinates).addTo(this.map)
      }
      next.set(key, marker)
    }

    this.pendingData = false
    // Counts, positions and click targets update on the same DOM nodes. Never
    // animate the outer transform: MapLibre needs it for accurate map alignment.
    for (const [key, marker] of next) {
      const {p, coordinates} = visible.get(key)
      marker.setLngLat(coordinates)
      marker._atlasPosition = coordinates
      if (p.cluster) {
        marker._atlasCluster = {id: p.cluster_id, coordinates}
        const element = marker.getElement()
        if (element.dataset.count !== String(p.point_count)) {
          element.dataset.count = String(p.point_count)
          element.textContent = Number(p.point_count).toLocaleString()
        }
        element.setAttribute("aria-label", `Zoom into ${p.point_count} matches`)
      }
      this.updateLoading(marker)
    }
    // Add/update the new snapshot before retiring obsolete markers.
    for (const marker of remaining.values()) marker.remove()
    this.markers = next
    this.renderedRevision = this.revision
    this.renderedZoom = zoom
  }

  distance(marker, coordinates) {
    const from = this.map.project(marker._atlasPosition)
    const to = this.map.project(coordinates)
    return Math.hypot(from.x - to.x, from.y - to.y)
  }

  nearestCluster(markers, coordinates) {
    let nearest = null, distance = 55
    for (const entry of markers) {
      if (!entry[1]._atlasCluster) continue
      const candidate = this.distance(entry[1], coordinates)
      if (candidate < distance) { nearest = entry; distance = candidate }
    }
    return nearest
  }

  clusterMarker() {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "atlas-search-cluster"
    const marker = new this.maplibre.Marker({ element: button })
    button.addEventListener("click", async (event) => {
      event.stopPropagation()
      try {
        const source = this.map.getSource(SOURCE)
        const info = marker._atlasCluster
        const revision = this.revision
        if (!source || !info || this.pendingData) return
        const zoom = await source.getClusterExpansionZoom(info.id)
        // Do not zoom to a stale cluster after a new batch, query or style change.
        if (revision !== this.revision || source !== this.map.getSource(SOURCE)) return
        if (marker._atlasCluster?.id !== info.id) return
        this.map.easeTo({ center: info.coordinates, zoom: Math.min(zoom, this.map.getMaxZoom()) })
      } catch (_) {
        // A new query or style may have replaced the source while awaiting it.
      }
    })
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
