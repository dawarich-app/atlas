// DOM badges also work with offline/raster basemaps that have no glyph endpoint.
export default class RouteLabels {
  constructor(map, maplibre) {
    this.map = map
    this.maplibre = maplibre
    this.markers = new Map()
  }

  setRoute(geojson) {
    const active = new Set()
    for (const [index, feature] of (geojson?.features || []).entries()) {
      const {route_label: label, color} = feature.properties || {}
      if (!label || feature.geometry?.type !== "LineString") continue
      const position = lineMidpoint(feature.geometry.coordinates)
      if (!position) continue
      active.add(index)
      let marker = this.markers.get(index)
      if (!marker) {
        const element = document.createElement("div")
        element.className = "atlas-route-label"
        const badge = document.createElement("span")
        badge.className = "atlas-route-badge"
        element.appendChild(badge)
        marker = new this.maplibre.Marker({element}).setLngLat(position).addTo(this.map)
        this.markers.set(index, marker)
      }
      const element = marker.getElement()
      element.firstChild.textContent = label
      element.firstChild.style.backgroundColor = color || "#2563eb"
      element.setAttribute("aria-label", `Route ${label}`)
      element.title = `Route ${label}`
      marker.setLngLat(position)
    }
    for (const [index, marker] of this.markers) {
      if (!active.has(index)) {
        marker.remove()
        this.markers.delete(index)
      }
    }
  }

  destroy() {
    for (const marker of this.markers.values()) marker.remove()
    this.markers.clear()
  }
}

// Interpolate halfway along the path, rather than picking the middle vertex:
// unevenly spaced vertices otherwise put labels next to a stop or off the line.
export function lineMidpoint(coordinates) {
  if (!coordinates || coordinates.length < 2) return null
  const lengths = coordinates.slice(1).map(([lon, lat], index) => {
    const [prevLon, prevLat] = coordinates[index]
    const dx = longitudeDelta(lon - prevLon) * Math.cos((lat + prevLat) * Math.PI / 360)
    return Math.hypot(dx, lat - prevLat)
  })
  let remaining = lengths.reduce((sum, length) => sum + length, 0) / 2
  for (const [index, length] of lengths.entries()) {
    if (length > 0 && remaining <= length) {
      const [lon, lat] = coordinates[index], next = coordinates[index + 1]
      const fraction = remaining / length
      return [lon + longitudeDelta(next[0] - lon) * fraction, lat + (next[1] - lat) * fraction]
    }
    remaining -= length
  }
  return coordinates[0]
}

function longitudeDelta(value) {
  return ((value + 540) % 360) - 180
}
