// Separate from search results: these two markers survive route/source updates.
export default class RouteEndpoints {
  constructor(map, maplibre) {
    this.map = map
    this.maplibre = maplibre
    this.points = []
    this.markers = new Map()
  }

  setPoints(points) {
    this.points = points
    const fields = new Set(points.map(point => point.field))
    for (const [field, marker] of this.markers) {
      if (!fields.has(field)) {
        marker.remove()
        this.markers.delete(field)
      }
    }
    for (const point of points) {
      let marker = this.markers.get(point.field)
      if (!marker) {
        const element = document.createElement("button")
        element.type = "button"
        element.className = `atlas-route-endpoint atlas-route-endpoint-${point.field}`
        element.dataset.field = point.field
        element.textContent = point.field === "from" ? "A" : "B"
        const caption = document.createElement("span")
        caption.className = "atlas-route-endpoint-caption"
        caption.textContent = point.field === "from" ? "From" : "To"
        element.appendChild(caption)
        marker = new this.maplibre.Marker({element})
          .setLngLat([point.lon, point.lat])
          .setPopup(new this.maplibre.Popup({offset: 24}).setText(point.label))
          .addTo(this.map)
        this.markers.set(point.field, marker)
      }
      const label = `${point.field === "from" ? "From" : "To"}: ${point.label}`
      marker.getElement().title = label
      marker.getElement().setAttribute("aria-label", label)
      marker.setLngLat([point.lon, point.lat])
      marker.getPopup().setText(point.label)
    }
    this.fit()
  }

  fit(routeCoordinates = []) {
    const coordinates = [...routeCoordinates, ...this.points.map(point => [point.lon, point.lat])]
    if (!coordinates.length) return
    const bounds = coordinates.reduce((bounds, point) => bounds.extend(point), new this.maplibre.LngLatBounds())
    // The padding includes the captions and keeps both ends clear of controls.
    // LiveView can resize the panel as itinerary details arrive. A map resize
    // stops camera animations, so apply the complete bounds in one step.
    this.map.fitBounds(bounds, {padding: 70, maxZoom: coordinates.length === 1 ? 14 : 16, duration: 0}, {atlasProgrammatic: true})
  }

  destroy() {
    for (const marker of this.markers.values()) marker.remove()
    this.markers.clear()
  }
}
