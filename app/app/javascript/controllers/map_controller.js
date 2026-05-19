import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { Protocol } from "pmtiles"
import { layers as protomapsLayers } from "protomaps-themes-base"
import { decodePolyline6, decodePolyline5 } from "../lib/polyline6"
import { lucide } from "../lib/lucide_icons"

const themeColor = (token, fallback) => {
  if (typeof document === "undefined") return fallback
  const v = getComputedStyle(document.documentElement).getPropertyValue(token).trim()
  return v || fallback
}

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

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    tilesUrl: String,
    theme:    { type: String, default: "light" },
    lat:      Number,
    lon:      Number,
    zoom:     Number
  }

  connect() {
    if (!maplibregl.protocolRegistered) {
      maplibregl.addProtocol("pmtiles", new Protocol().tile)
      maplibregl.protocolRegistered = true
    }

    this.map = new maplibregl.Map({
      container: this.canvasTarget,
      style: this.buildStyle(),
      center: [this.lonValue || 10.4515, this.latValue || 51.1657],
      zoom: this.zoomValue || 5,
      attributionControl: { customAttribution: this.attribution() }
    })

    this.projection = "globe"
    this.map.on("load", () => this.map.setProjection({ type: this.projection }))

    // Broadcast bbox changes (debounced) so listeners like the Places panel
    // can re-query for the new viewport.
    this.map.on("moveend", () => {
      clearTimeout(this.moveTimer)
      this.moveTimer = setTimeout(() => {
        const b = this.map.getBounds()
        window.dispatchEvent(new CustomEvent("atlas:map:moved", {
          detail: { south: b.getSouth(), west: b.getWest(), north: b.getNorth(), east: b.getEast() }
        }))
      }, 400)
    })

    this.map.addControl(new maplibregl.NavigationControl({ visualizePitch: true }), "bottom-right")
    this.map.addControl(new maplibregl.ScaleControl({ unit: "metric" }), "bottom-left")

    this.markers = []
    this.routeEndpoints = {}
    // Cross-controller events come from sibling panels (search/routing/places)
    // and bubble up to window. Listening on this.element (a sibling, not an
    // ancestor) would silently miss every event. Store refs so disconnect()
    // can clean them up across Turbo reloads.
    this.crossControllerHandlers = {
      "atlas:flyto":                  (e) => this.flyTo(e.detail),
      "atlas:setresults":             (e) => this.renderResults(e.detail),
      "atlas:routing:endpoint":       (e) => this.setRouteEndpoint(e.detail),
      "atlas:routing:clearendpoint":  (e) => this.clearRouteEndpoint(e.detail.role),
      "atlas:routing:show":           (e) => this.showRoute(e.detail),
      "atlas:routing:transit":        (e) => this.showTransit(e.detail),
      "atlas:routing:clear":          ()  => this.clearRoute(),
      "atlas:places:show":            (e) => this.showPlaces(e.detail.features),
      "atlas:places:clear":           ()  => this.clearPlaces(),
    }
    for (const [name, handler] of Object.entries(this.crossControllerHandlers)) {
      window.addEventListener(name, handler)
    }

    // Swap to a dark map variant on global theme change. For OpenFreeMap we
    // know the style URLs; for pmtiles we toggle the protomaps theme.
    window.addEventListener("atlas:theme:changed", (e) => {
      const newTheme = e.detail?.isDark ? "dark" : "light"
      this.themeValue = newTheme
      const url = this.tilesUrlValue
      if (url.includes("openfreemap.org/styles/")) {
        const variants = {
          light: ["liberty", "bright"],
          dark:  ["dark", "fiord"]
        }
        const lightDark = url.match(/openfreemap\.org\/styles\/([a-z-]+)/i)?.[1]
        // If user is on a known-light style, swap to dark equivalent (and vice versa).
        if (lightDark && variants.light.includes(lightDark) && newTheme === "dark") {
          this.tilesUrlValue = url.replace(lightDark, "dark")
        } else if (lightDark && variants.dark.includes(lightDark) && newTheme === "light") {
          this.tilesUrlValue = url.replace(lightDark, "liberty")
        }
      }
      this.map.setStyle(this.buildStyle())
    })

    // Live-reload basemap style when admin switches sources.
    window.addEventListener("atlas:basemap:changed", async () => {
      try {
        const r = await fetch("/admin/tiles", { headers: { Accept: "application/json" } })
        const body = await r.json()
        const newUrl = body.data?.effective || ""
        if (newUrl === this.tilesUrlValue) return
        this.tilesUrlValue = newUrl
        this.map.setStyle(this.buildStyle())
      } catch (_) {}
    })

    // Right-click / long-press → "What's here" popup.
    this.map.on("contextmenu", (e) => this.showWhatsHere(e.lngLat))

    // Pick-on-map mode (driven by the routing controller). When active, the
    // next single click dispatches the coords and exits mode.
    this.pickModeActive = false
    document.addEventListener("atlas:map:pick-mode", (e) => {
      this.pickModeActive = !!e.detail.active
      this.canvasTarget.style.cursor = this.pickModeActive ? "crosshair" : ""
    })
    this.map.on("click", (e) => {
      if (!this.pickModeActive) return
      document.dispatchEvent(new CustomEvent("atlas:map:click", {
        detail: { lat: e.lngLat.lat, lon: e.lngLat.lng }
      }))
    })
    let touchTimer = null
    this.map.on("touchstart", (e) => {
      if (e.points.length !== 1) return
      const pt = e.points[0]
      touchTimer = setTimeout(() => this.showWhatsHere(e.lngLat), 600)
      const cancel = () => { clearTimeout(touchTimer); touchTimer = null }
      this.map.once("touchmove", cancel)
      this.map.once("touchend",  cancel)
    })

    this.bboxRequestHandler = () => {
      if (!this.map) return
      const b = this.map.getBounds()
      window.dispatchEvent(new CustomEvent("atlas:map:bbox", {
        detail: { south: b.getSouth(), west: b.getWest(), north: b.getNorth(), east: b.getEast() }
      }))
    }
    window.addEventListener("atlas:map:bbox-request", this.bboxRequestHandler)

    // Delegated click handler for popup buttons that carry a data-apo-action.
    this.popupActionHandler = (e) => {
      const trigger = e.target.closest?.("[data-apo-action]")
      if (!trigger) return
      const action = trigger.dataset.apoAction
      try {
        const detail = trigger.dataset.apoPayload ? JSON.parse(trigger.dataset.apoPayload) : {}
        document.dispatchEvent(new CustomEvent(`atlas:${action}`, { detail }))
      } catch (_) { /* malformed payload — ignore */ }
    }
    document.addEventListener("click", this.popupActionHandler)

    this.poiMarkers = []

    this.observeRegionMeta()
  }

  disconnect() {
    if (this.regionObserver) this.regionObserver.disconnect()
    if (this.bboxRequestHandler) window.removeEventListener("atlas:map:bbox-request", this.bboxRequestHandler)
    if (this.popupActionHandler) document.removeEventListener("click", this.popupActionHandler)
    if (this.crossControllerHandlers) {
      for (const [name, handler] of Object.entries(this.crossControllerHandlers)) {
        window.removeEventListener(name, handler)
      }
    }
    if (this.map) this.map.remove()
  }

  showPlaces(features) {
    if (!this.map) return
    this.clearPlaces()
    ;(features || []).forEach(f => {
      if (!f.coords?.lon || !f.coords?.lat) return
      const el = document.createElement("div")
      el.className = "apo-poi-marker"
      el.style.cssText = "width:14px;height:14px;border-radius:50%;background:var(--color-accent);border:2px solid var(--color-base-100);box-shadow:0 1px 3px rgba(0,0,0,.4);cursor:pointer;"
      el.title = `${f.name || ""} (${f.category})`
      const popup = new maplibregl.Popup({ offset: 14, maxWidth: "320px", className: "apo-poi-popup" })
        .setHTML(this.poiPopupHTML(f))
      const m = new maplibregl.Marker({ element: el })
        .setLngLat([f.coords.lon, f.coords.lat])
        .setPopup(popup)
        .addTo(this.map)
      this.poiMarkers.push(m)
    })
  }

  poiPopupHTML(f) {
    const t = f.tags || {}
    const name = f.name || `Unnamed ${f.category}`
    const category = (f.category || "").replace(/_/g, " ")
    const subtitleParts = []
    if (t["brand"] && t["brand"] !== name) subtitleParts.push(t["brand"])
    if (t["cuisine"]) subtitleParts.push(t["cuisine"].replace(/[_;]/g, " "))
    const subtitle = subtitleParts.join(" · ")

    const address = [
      [t["addr:street"], t["addr:housenumber"]].filter(Boolean).join(" "),
      [t["addr:postcode"], t["addr:city"]].filter(Boolean).join(" ")
    ].filter(Boolean).join(", ")

    const phone     = t["phone"] || t["contact:phone"]
    const website   = t["website"] || t["contact:website"] || t["url"]
    const wikipedia = t["wikipedia"]
    const hours     = t["opening_hours"]

    const rows = []
    if (address)   rows.push(infoRow(iconPin(), escapeText(address)))
    if (hours)     rows.push(infoRow(iconClock(), escapeText(humanHours(hours))))
    if (phone)     rows.push(infoRow(iconPhone(), `<a href="tel:${escapeAttr(phone)}" class="apo-popup-link">${escapeText(phone)}</a>`))
    if (website)   rows.push(infoRow(iconLink(), `<a href="${escapeAttr(website)}" target="_blank" rel="noopener" class="apo-popup-link truncate">${escapeText(stripHttp(website))}</a>`))
    if (wikipedia) {
      const [lang, page] = wikipedia.split(":", 2)
      if (page) rows.push(infoRow(iconBook(), `<a href="https://${lang}.wikipedia.org/wiki/${encodeURIComponent(page)}" target="_blank" rel="noopener" class="apo-popup-link truncate">Wikipedia</a>`))
    }

    const badges = []
    if (t["wheelchair"] === "yes")      badges.push({ key: "wheelchair", label: "Accessible" })
    if (t["takeaway"] === "yes")        badges.push({ key: "takeaway",   label: "Takeaway" })
    if (t["outdoor_seating"] === "yes") badges.push({ key: "outdoor",    label: "Outdoor" })
    if (t["internet_access"] === "wlan" || t["wifi"] === "yes" || t["internet_access"] === "yes")
                                        badges.push({ key: "wifi",       label: "Wifi" })
    if (t["smoking"] === "no")          badges.push({ key: "no-smoke",   label: "No smoking" })
    if (t["breakfast"] === "yes")       badges.push({ key: "breakfast",  label: "Breakfast" })
    if (t["fee"] === "no" || t["fee"] === "free") badges.push({ key: "free", label: "Free" })
    if (t["stars"])                     badges.push({ key: "stars",      label: `${t["stars"]}★` })

    const payload = escapeAttr(JSON.stringify({ lat: f.coords.lat, lon: f.coords.lon, label: name }))

    return `
      <div class="apo-popup">
        <header class="apo-popup-header">
          <div class="apo-popup-name">${escapeText(name)}</div>
          <div class="apo-popup-meta">
            <span class="apo-popup-category">${escapeText(category)}</span>
            ${subtitle ? `<span class="apo-popup-sep">·</span><span>${escapeText(subtitle)}</span>` : ""}
          </div>
        </header>
        ${rows.length ? `<div class="apo-popup-rows">${rows.join("")}</div>` : ""}
        ${badges.length ? `<div class="apo-popup-badges">${badges.map(b => `<span class="apo-popup-badge apo-popup-badge--${b.key}">${escapeText(b.label)}</span>`).join("")}</div>` : ""}
        <footer class="apo-popup-actions">
          <button type="button"
                  class="apo-popup-cta"
                  data-apo-action="routing:set-destination"
                  data-apo-payload="${payload}">
            ${iconRoute()} <span>Directions</span>
          </button>
          <a class="apo-popup-secondary" target="_blank" rel="noopener" href="https://www.openstreetmap.org/${escapeAttr(f.id)}">
            ${iconExternal()} <span>OSM</span>
          </a>
        </footer>
      </div>
    `
  }

  clearPlaces() {
    if (!this.poiMarkers) return
    this.poiMarkers.forEach(m => m.remove())
    this.poiMarkers = []
  }

  observeRegionMeta() {
    const meta = document.getElementById("region_meta")
    if (!meta) return
    this.regionObserver = new MutationObserver(() => this.applyRegionCenter(meta))
    this.regionObserver.observe(meta, { attributes: true })
  }

  applyRegionCenter(meta) {
    if (!this.map) return
    const lat  = parseFloat(meta.dataset.lat)
    const lon  = parseFloat(meta.dataset.lon)
    const zoom = parseFloat(meta.dataset.zoom)
    if (Number.isFinite(lat) && Number.isFinite(lon)) {
      this.map.flyTo({ center: [lon, lat], zoom: Number.isFinite(zoom) ? zoom : this.map.getZoom(), duration: 1000 })
    }
  }

  // Build the map style based on TILES_URL shape:
  //   • empty                       → OSM raster fallback
  //   • *.pmtiles / pmtiles://*     → self-hosted Protomaps Basemap v4 with themes
  //   • *.json or remote style URL  → use directly (hosted MapLibre style services
  //     like OpenFreeMap, Stadia, MapTiler, etc.)
  buildStyle() {
    const url = this.tilesUrlValue
    if (!url) return OSM_RASTER_FALLBACK
    if (url.startsWith("pmtiles://") || url.endsWith(".pmtiles")) return this.protomapsStyle()
    return url  // MapLibre accepts a style URL directly here.
  }

  protomapsStyle() {
    return {
      version: 8,
      glyphs: "https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf",
      sprite: `https://protomaps.github.io/basemaps-assets/sprites/v4/${this.themeValue || "light"}`,
      sources: {
        protomaps: {
          type: "vector",
          url: this.protocolUrl(),
          attribution: this.attribution()
        }
      },
      layers: protomapsLayers("protomaps", this.themeValue || "light")
    }
  }

  protocolUrl() {
    const url = this.tilesUrlValue
    if (url.startsWith("pmtiles://")) return url
    if (url.endsWith(".pmtiles"))     return `pmtiles://${url}`
    return url
  }

  attribution() {
    return '<a href="https://protomaps.com">Protomaps</a> © <a href="https://openstreetmap.org">OpenStreetMap</a>'
  }

  flyTo({ lon, lat, zoom = 14 }) {
    if (typeof lon !== "number" || typeof lat !== "number") return
    this.map.flyTo({ center: [lon, lat], zoom, duration: 800 })
  }

  renderResults(features) {
    this.clearMarkers()
    if (!Array.isArray(features) || features.length === 0) return

    features.forEach((f) => {
      if (!f.coords?.lon || !f.coords?.lat) return
      const marker = new maplibregl.Marker({ color: themeColor("--color-accent", "#B86A3A") })
        .setLngLat([f.coords.lon, f.coords.lat])
        .setPopup(new maplibregl.Popup({ offset: 16 }).setText(f.label || f.name || ""))
        .addTo(this.map)
      this.markers.push(marker)
    })
  }

  clearMarkers() {
    this.markers.forEach((m) => m.remove())
    this.markers = []
  }

  async showWhatsHere(lngLat) {
    if (this.whatsHerePopup) this.whatsHerePopup.remove()
    if (this.whatsHereMarker) this.whatsHereMarker.remove()

    const lat = lngLat.lat, lon = lngLat.lng
    // Temporary pin so the user sees feedback while we fetch.
    const pin = document.createElement("div")
    pin.className = "apo-pin"
    pin.style.cssText = "width:14px;height:14px;border-radius:50%;background:var(--color-neutral);border:2px solid var(--color-base-100);box-shadow:0 1px 4px rgba(0,0,0,.4);"
    this.whatsHereMarker = new maplibregl.Marker({ element: pin }).setLngLat([lon, lat]).addTo(this.map)

    const popup = new maplibregl.Popup({ offset: 14, maxWidth: "320px", className: "apo-poi-popup" })
      .setLngLat([lon, lat])
      .setHTML(`<div class="apo-popup"><div class="apo-popup-header"><div class="apo-popup-name">Loading…</div><div class="apo-popup-meta"><span>${lat.toFixed(5)}, ${lon.toFixed(5)}</span></div></div></div>`)
      .addTo(this.map)
    this.whatsHerePopup = popup
    popup.on("close", () => {
      if (this.whatsHereMarker) this.whatsHereMarker.remove()
      this.whatsHereMarker = null
      this.whatsHerePopup = null
    })

    try {
      const url = new URL("/api/v1/whats_here", window.location.origin)
      url.searchParams.set("lat", lat)
      url.searchParams.set("lon", lon)
      url.searchParams.set("radius", "200")
      const res = await fetch(url.toString(), { headers: { Accept: "application/json" } })
      if (!res.ok) {
        popup.setHTML(this.whatsHereErrorHTML(lat, lon, `Lookup failed (${res.status})`))
        return
      }
      const body = await res.json()
      popup.setHTML(this.whatsHereHTML(lat, lon, body.data))
    } catch (err) {
      popup.setHTML(this.whatsHereErrorHTML(lat, lon, err.message))
    }
  }

  whatsHereErrorHTML(lat, lon, msg) {
    return `<div class="apo-popup"><div class="apo-popup-header"><div class="apo-popup-name">No info here</div><div class="apo-popup-meta"><span>${lat.toFixed(5)}, ${lon.toFixed(5)}</span></div></div><div class="apo-popup-rows"><div class="apo-popup-row"><span class="apo-popup-row-value text-red-600">${escapeText(msg)}</span></div></div>${this.whatsHereActions(lat, lon)}</div>`
  }

  whatsHereHTML(lat, lon, data) {
    const here   = data?.here  || {}
    const admin  = data?.admin || {}
    const nearby = data?.nearby || []
    const title  = here.name || admin.city || admin.country || "Unknown place"
    const addrParts = [here.label, admin.city, admin.country].filter(Boolean).filter((v, i, a) => a.indexOf(v) === i)
    const address = addrParts.join(" · ") || `${lat.toFixed(5)}, ${lon.toFixed(5)}`

    const nearbyRows = nearby.slice(0, 5).map(p => {
      const n = p.tags?.name || p.tags?.brand || "(unnamed)"
      const cat = (p.tags?.amenity || p.tags?.shop || p.tags?.tourism || p.tags?.leisure || "").replace(/_/g, " ")
      return `<div class="apo-popup-row"><span class="apo-popup-row-icon">${dotIcon()}</span><span class="apo-popup-row-value"><span class="font-medium">${escapeText(n)}</span>${cat ? ` <span class="text-base-content/50">· ${escapeText(cat)}</span>` : ""}</span></div>`
    }).join("")

    return `
      <div class="apo-popup">
        <header class="apo-popup-header">
          <div class="apo-popup-name">${escapeText(title)}</div>
          <div class="apo-popup-meta"><span>${escapeText(address)}</span></div>
        </header>
        ${nearbyRows ? `<div class="apo-popup-rows"><div class="text-[10px] uppercase tracking-wider text-base-content/40 px-0 pb-1">Nearby</div>${nearbyRows}</div>` : ""}
        ${this.whatsHereActions(lat, lon, title)}
      </div>
    `
  }

  whatsHereActions(lat, lon, label = "Pinned location") {
    const fromPayload = escapeAttr(JSON.stringify({ lat, lon, label, role: "from" }))
    const toPayload   = escapeAttr(JSON.stringify({ lat, lon, label, role: "to" }))
    return `
      <footer class="apo-popup-actions">
        <button type="button"
                class="apo-popup-cta"
                data-apo-action="routing:set-endpoint"
                data-apo-payload="${toPayload}">${iconRoute()} <span>Directions here</span></button>
        <button type="button"
                class="apo-popup-secondary"
                data-apo-action="routing:set-endpoint"
                data-apo-payload="${fromPayload}">${iconFlag()} <span>From here</span></button>
      </footer>
    `
  }

  setRouteEndpoint({ role, lon, lat, color }) {
    if (!this.map || typeof lon !== "number" || typeof lat !== "number") return
    if (this.routeEndpoints[role]) this.routeEndpoints[role].remove()
    const marker = new maplibregl.Marker({ color, draggable: true })
      .setLngLat([lon, lat])
      .addTo(this.map)
    marker.on("dragend", () => {
      const ll = marker.getLngLat()
      document.dispatchEvent(new CustomEvent("atlas:routing:set-endpoint", {
        detail: { lat: ll.lat, lon: ll.lng, role, label: `${ll.lat.toFixed(5)}, ${ll.lng.toFixed(5)}` }
      }))
    })
    this.routeEndpoints[role] = marker
  }

  clearRouteEndpoint(role) {
    if (this.routeEndpoints[role]) {
      this.routeEndpoints[role].remove()
      delete this.routeEndpoints[role]
    }
  }

  showRoute({ shapes }) {
    if (!this.map) return
    const coords = (shapes || []).flatMap(s => decodePolyline6(s))
    if (coords.length < 2) return

    const geojson = { type: "Feature", geometry: { type: "LineString", coordinates: coords } }
    this.ensureRouteLayer()
    this.map.getSource("route").setData(geojson)

    const lons = coords.map(c => c[0])
    const lats = coords.map(c => c[1])
    this.map.fitBounds(
      [[Math.min(...lons), Math.min(...lats)], [Math.max(...lons), Math.max(...lats)]],
      { padding: 60, duration: 600 }
    )
  }

  ensureRouteLayer() {
    if (this.map.getSource("route")) return
    this.map.addSource("route", { type: "geojson", data: { type: "FeatureCollection", features: [] } })
    this.map.addLayer({
      id: "route-casing", source: "route", type: "line",
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": themeColor("--color-base-100", "#ffffff"), "line-width": 8 }
    })
    this.map.addLayer({
      id: "route-line", source: "route", type: "line",
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": themeColor("--color-primary", "#2F5D3E"), "line-width": 5 }
    })
  }

  showTransit({ legs }) {
    if (!this.map || !legs?.length) return
    this.clearRoute()
    this.ensureTransitLayer()

    const features = []
    const allCoords = []
    legs.forEach((leg, idx) => {
      const coords = leg.shape ? decodePolyline5(leg.shape) : []
      if (coords.length < 2) return
      allCoords.push(...coords)
      features.push({
        type: "Feature",
        properties: { mode: leg.mode, color: legColor(leg.mode), idx },
        geometry: { type: "LineString", coordinates: coords }
      })
    })
    this.map.getSource("transit").setData({ type: "FeatureCollection", features })

    if (allCoords.length >= 2) {
      const lons = allCoords.map(c => c[0])
      const lats = allCoords.map(c => c[1])
      this.map.fitBounds(
        [[Math.min(...lons), Math.min(...lats)], [Math.max(...lons), Math.max(...lats)]],
        { padding: 60, duration: 600 }
      )
    }

    // Mark the first leg's start as "from", last leg's end as "to" via existing markers.
    const first = features[0]?.geometry.coordinates[0]
    const last  = features.at(-1)?.geometry.coordinates.at(-1)
    if (first) this.setRouteEndpoint({ role: "from", lon: first[0], lat: first[1], color: themeColor("--color-info", "#3D6F7A") })
    if (last)  this.setRouteEndpoint({ role: "to",   lon: last[0],  lat: last[1],  color: themeColor("--color-primary", "#2F5D3E") })
  }

  ensureTransitLayer() {
    if (this.map.getSource("transit")) return
    this.map.addSource("transit", { type: "geojson", data: { type: "FeatureCollection", features: [] } })
    this.map.addLayer({
      id: "transit-casing", source: "transit", type: "line",
      layout: { "line-cap": "round", "line-join": "round" },
      paint: { "line-color": themeColor("--color-base-100", "#ffffff"), "line-width": 8 }
    })
    this.map.addLayer({
      id: "transit-line", source: "transit", type: "line",
      layout: { "line-cap": "round", "line-join": "round" },
      paint: {
        "line-color": ["coalesce", ["get", "color"], themeColor("--color-primary", "#2F5D3E")],
        "line-width": 5,
        "line-dasharray": [
          "case",
          ["==", ["get", "mode"], "WALK"], ["literal", [1, 2]],
          ["literal", [1, 0]]
        ]
      }
    })
  }

  clearRoute() {
    if (!this.map) return
    ["route-line", "route-casing", "transit-line", "transit-casing"].forEach(l => {
      if (this.map.getLayer(l)) this.map.removeLayer(l)
    })
    ;["route", "transit"].forEach(s => {
      if (this.map.getSource(s)) this.map.removeSource(s)
    })
    Object.keys(this.routeEndpoints).forEach(role => this.clearRouteEndpoint(role))
  }
}

function escapeText(s) {
  return String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]))
}
function escapeAttr(s) { return escapeText(s) }

function stripHttp(url) { return String(url || "").replace(/^https?:\/\/(www\.)?/, "").replace(/\/$/, "") }

function humanHours(raw) {
  // Cheap normaliser: collapse whitespace, keep the user's format intact.
  return String(raw || "").replace(/\s+/g, " ").trim()
}

function infoRow(iconSvg, content) {
  return `<div class="apo-popup-row"><span class="apo-popup-row-icon">${iconSvg}</span><span class="apo-popup-row-value">${content}</span></div>`
}

// Wrappers that render Lucide outline icons sized for the popup chrome.
const POPUP_ICON = "apo-popup-icon"
function iconPin()      { return lucide("map-pin",       POPUP_ICON) }
function iconClock()    { return lucide("clock",         POPUP_ICON) }
function iconPhone()    { return lucide("phone",         POPUP_ICON) }
function iconLink()     { return lucide("link",          POPUP_ICON) }
function iconBook()     { return lucide("book-open",     POPUP_ICON) }
function iconRoute()    { return lucide("route",         POPUP_ICON) }
function iconExternal() { return lucide("external-link", POPUP_ICON) }
function iconFlag()     { return lucide("flag",          POPUP_ICON) }
function dotIcon()      { return lucide("dot",           POPUP_ICON) }

function legColor(mode) {
  const neutral   = themeColor("--color-neutral",   "#2A332D")
  const warning   = themeColor("--color-warning",   "#C28A2A")
  const error     = themeColor("--color-error",     "#9C3A2A")
  const info      = themeColor("--color-info",      "#3D6F7A")
  const success   = themeColor("--color-success",   "#4D7A3A")
  const secondary = themeColor("--color-secondary", "#7A6A4E")
  const accent    = themeColor("--color-accent",    "#B86A3A")
  const colors = {
    WALK:      neutral,
    BUS:       warning,
    TRAM:      error,
    SUBWAY:    info,
    RAIL:      success,
    FERRY:     secondary,
    CABLE_CAR: accent,
    GONDOLA:   accent
  }
  return colors[mode] || themeColor("--color-primary", "#2F5D3E")
}
