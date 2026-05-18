import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 200
const MIN_QUERY_LENGTH = 2
const readThemeColor = (token, fallback) => {
  if (typeof document === "undefined") return fallback
  const v = getComputedStyle(document.documentElement).getPropertyValue(token).trim()
  return v || fallback
}
const ENDPOINT_COLORS = {
  get from() { return readThemeColor("--color-info", "#3D6F7A") },
  get to()   { return readThemeColor("--color-primary", "#2F5D3E") }
}

export default class extends Controller {
  static targets = [
    "fromInput", "toInput", "fromResults", "toResults",
    "summary", "summaryDuration", "summaryDistance", "details",
    "submit", "status", "itineraries",
    "optionsBlock", "avoidTolls", "avoidHighways", "avoidFerries"
  ]
  static values = {
    searchEndpoint:  { type: String, default: "/api/v1/search" },
    routeEndpoint:   { type: String, default: "/api/v1/route" },
    transitEndpoint: { type: String, default: "/api/v1/transit" }
  }

  connect() {
    this.timers = { from: null, to: null }
    this.picked = { from: null, to: null }
    this.mode = "auto"
    this.activeIndex = { from: -1, to: -1 }
    this.lastResults = { from: [], to: [] }
    this.setDestHandler = (e) => this.setEndpoint({ ...e.detail, role: "to" })
    this.setEndpointHandler = (e) => this.setEndpoint(e.detail)
    this.pickRequestHandler = (e) => this.handleMapPick(e.detail)
    document.addEventListener("atlas:routing:set-destination", this.setDestHandler)
    document.addEventListener("atlas:routing:set-endpoint",   this.setEndpointHandler)
    document.addEventListener("atlas:map:click",              this.pickRequestHandler)
  }

  disconnect() {
    Object.values(this.timers).forEach(t => t && clearTimeout(t))
    document.removeEventListener("atlas:routing:set-destination", this.setDestHandler)
    document.removeEventListener("atlas:routing:set-endpoint",   this.setEndpointHandler)
    document.removeEventListener("atlas:map:click",              this.pickRequestHandler)
  }

  setEndpoint({ lat, lon, label, role = "to" }) {
    if (!["from", "to"].includes(role)) role = "to"
    this.picked[role] = { lat, lon }
    const input = role === "from" ? this.fromInputTarget : this.toInputTarget
    input.value = label || `${lat.toFixed(5)}, ${lon.toFixed(5)}`
    this.dispatchEndpoint(role, { lat, lon })
    const routeTab = document.querySelector("[data-side-panel-target='tab'][data-tab='route']")
    if (routeTab) routeTab.click()
    if (this.picked.from && this.picked.to) this.submit()
    else (role === "to" ? this.fromInputTarget : this.toInputTarget).focus()
  }

  // Backwards-compat shim for the POI popup's old action name.
  setDestination(detail) { this.setEndpoint({ ...detail, role: "to" }) }

  // "Pick on map" mode: arms the controller; next map click sets the endpoint.
  pickFrom() { this.startPick("from") }
  pickTo()   { this.startPick("to") }
  startPick(role) {
    this.pickingRole = role
    document.body.classList.add("apo-picking")
    const btn = this.element.querySelector(`[data-action$="${role === "from" ? "pickFrom" : "pickTo"}"]`)
    if (btn) btn.classList.add("btn-primary", "ring-2", "ring-primary/40")
    document.dispatchEvent(new CustomEvent("atlas:map:pick-mode", { detail: { active: true } }))
  }
  cancelPick() {
    document.body.classList.remove("apo-picking")
    this.element.querySelectorAll("[data-pick-on-map]").forEach(b => {
      b.classList.remove("btn-primary", "ring-2", "ring-primary/40")
    })
    document.dispatchEvent(new CustomEvent("atlas:map:pick-mode", { detail: { active: false } }))
    this.pickingRole = null
  }
  handleMapPick({ lat, lon, label }) {
    if (!this.pickingRole) return
    const role = this.pickingRole
    this.cancelPick()
    this.setEndpoint({ lat, lon, label: label || `${lat.toFixed(5)}, ${lon.toFixed(5)}`, role })
  }

  // ---- mode switching ----
  selectMode(event) {
    const button = event.currentTarget
    this.mode = button.dataset.mode || "auto"
    this.element.querySelectorAll("[data-mode]").forEach(b => {
      b.classList.toggle("btn-primary", b === button)
      b.classList.toggle("btn-ghost",   b !== button)
    })
    if (this.hasOptionsBlockTarget) this.optionsBlockTarget.hidden = this.mode !== "auto"
    if (this.picked.from && this.picked.to) this.submit()
  }

  optionsChanged() {
    if (this.picked.from && this.picked.to) this.submit()
  }

  // ---- input handling ----
  queryFrom() { this.queryEndpoint("from") }
  queryTo()   { this.queryEndpoint("to") }

  queryEndpoint(role) {
    const input = role === "from" ? this.fromInputTarget : this.toInputTarget
    const q = input.value.trim()
    this.picked[role] = null
    clearTimeout(this.timers[role])
    if (q.length < MIN_QUERY_LENGTH) { this.hideResults(role); return }
    this.timers[role] = setTimeout(() => this.fetchSuggestions(role, q), DEBOUNCE_MS)
  }

  async fetchSuggestions(role, q) {
    try {
      const url = new URL(this.searchEndpointValue, window.location.origin)
      url.searchParams.set("q", q)
      url.searchParams.set("limit", "6")
      const res = await fetch(url.toString(), { headers: { Accept: "application/json" } })
      if (!res.ok) { this.hideResults(role); return }
      const body = await res.json()
      const items = body.data || []
      this.lastResults[role] = items
      this.activeIndex[role] = items.length > 0 ? 0 : -1
      this.renderSuggestions(role, items)
    } catch (_) {
      this.hideResults(role)
    }
  }

  renderSuggestions(role, items) {
    const list = role === "from" ? this.fromResultsTarget : this.toResultsTarget
    list.innerHTML = ""
    if (items.length === 0) { list.classList.add("hidden"); return }

    items.forEach((item, idx) => {
      const li = document.createElement("li")
      const a  = document.createElement("a")
      a.className = idx === this.activeIndex[role] ? "active" : ""
      a.dataset.index = idx
      a.addEventListener("click", (e) => {
        e.preventDefault()
        this.activeIndex[role] = idx
        this.pickActive(role)
      })
      const name = document.createElement("span")
      name.className = "font-medium truncate"
      name.textContent = item.name || item.label || "(unnamed)"
      const sub = document.createElement("span")
      sub.className = "text-xs text-base-content/60 truncate"
      sub.textContent = item.label && item.label !== name.textContent ? item.label : (item.type || "")
      a.appendChild(name); a.appendChild(sub)
      li.appendChild(a)
      list.appendChild(li)
    })
    list.classList.remove("hidden")
  }

  keyFrom(e) { this.handleKeydown("from", e) }
  keyTo(e)   { this.handleKeydown("to", e) }

  handleKeydown(role, event) {
    const items = this.lastResults[role]
    if (event.key === "ArrowDown") {
      event.preventDefault()
      if (items.length) {
        this.activeIndex[role] = (this.activeIndex[role] + 1 + items.length) % items.length
        this.renderSuggestions(role, items)
      }
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      if (items.length) {
        this.activeIndex[role] = (this.activeIndex[role] - 1 + items.length) % items.length
        this.renderSuggestions(role, items)
      }
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.pickActive(role)
    } else if (event.key === "Escape") {
      this.hideResults(role)
    }
  }

  pickActive(role) {
    const item = this.lastResults[role][this.activeIndex[role]]
    if (!item || !item.coords) return
    const input = role === "from" ? this.fromInputTarget : this.toInputTarget
    input.value = item.label || item.name || ""
    this.picked[role] = item.coords
    this.hideResults(role)
    this.dispatchEndpoint(role, item.coords)
    if (this.picked.from && this.picked.to) this.submit()
  }

  hideResults(role) {
    const list = role === "from" ? this.fromResultsTarget : this.toResultsTarget
    list.classList.add("hidden")
  }

  // ---- swap + clear ----
  swap() {
    const aText = this.fromInputTarget.value
    const bText = this.toInputTarget.value
    const aCoords = this.picked.from
    const bCoords = this.picked.to

    this.fromInputTarget.value = bText
    this.toInputTarget.value   = aText
    this.picked.from = bCoords
    this.picked.to   = aCoords

    if (this.picked.from) this.dispatchEndpoint("from", this.picked.from); else this.dispatchClear("from")
    if (this.picked.to)   this.dispatchEndpoint("to",   this.picked.to);   else this.dispatchClear("to")
    if (this.picked.from && this.picked.to) this.submit()
  }

  close() {
    this.dispatchClear("from")
    this.dispatchClear("to")
    this.dispatchClearRoute()
    this.element.dispatchEvent(new CustomEvent("atlas:routing:close", { bubbles: true }))
  }

  // ---- submit ----
  async submit() {
    if (!this.picked.from || !this.picked.to) return
    if (this.mode === "transit") {
      return this.submitTransit()
    }
    this.hideItineraries()
    this.showStatus("Routing…")
    this.submitTarget.disabled = true
    try {
      const url = new URL(this.routeEndpointValue, window.location.origin)
      url.searchParams.set("from", `${this.picked.from.lat},${this.picked.from.lon}`)
      url.searchParams.set("to",   `${this.picked.to.lat},${this.picked.to.lon}`)
      url.searchParams.set("mode", this.mode)
      if (this.mode === "auto") {
        if (this.hasAvoidTollsTarget    && this.avoidTollsTarget.checked)    url.searchParams.set("avoid_tolls",    "true")
        if (this.hasAvoidHighwaysTarget && this.avoidHighwaysTarget.checked) url.searchParams.set("avoid_highways", "true")
        if (this.hasAvoidFerriesTarget  && this.avoidFerriesTarget.checked)  url.searchParams.set("avoid_ferries",  "true")
      }
      const res = await fetch(url.toString(), { headers: { Accept: "application/json" } })
      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        this.showStatus(body?.error?.message || `Routing failed (${res.status})`)
        return
      }
      const body = await res.json()
      this.renderRoute(body.data)
      this.hideStatus()
    } catch (err) {
      this.showStatus(`Network error: ${err.message}`)
    } finally {
      this.submitTarget.disabled = false
    }
  }

  async submitTransit() {
    this.hideSummary()
    this.showStatus("Planning transit…")
    this.submitTarget.disabled = true
    try {
      const url = new URL(this.transitEndpointValue, window.location.origin)
      url.searchParams.set("from", `${this.picked.from.lat},${this.picked.from.lon}`)
      url.searchParams.set("to",   `${this.picked.to.lat},${this.picked.to.lon}`)
      url.searchParams.set("num",  "3")
      const res = await fetch(url.toString(), { headers: { Accept: "application/json" } })
      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        this.showStatus(body?.error?.message || `Transit failed (${res.status})`)
        return
      }
      const body = await res.json()
      this.renderItineraries(body.data)
      this.hideStatus()
    } catch (err) {
      this.showStatus(`Network error: ${err.message}`)
    } finally {
      this.submitTarget.disabled = false
    }
  }

  renderItineraries(plan) {
    const list = plan?.itineraries || []
    this.itinerariesTarget.innerHTML = ""
    if (list.length === 0) {
      this.showStatus("No transit options found.")
      this.itinerariesTarget.classList.add("hidden")
      this.element.dispatchEvent(new CustomEvent("atlas:routing:clear", { bubbles: true }))
      return
    }

    list.forEach((it, idx) => {
      const item = document.createElement("li")
      item.className = "border rounded-md p-2 hover:bg-base-200/50 cursor-pointer transition-colors"
      item.dataset.index = idx
      item.addEventListener("click", () => this.selectItinerary(idx, list))
      if (idx === 0) item.classList.add("border-primary", "bg-primary/5")

      const head = document.createElement("div")
      head.className = "flex items-baseline justify-between gap-2"
      const dur = document.createElement("span")
      dur.className = "text-sm font-semibold"
      dur.textContent = formatDuration(it.duration)
      const time = document.createElement("span")
      time.className = "text-xs text-base-content/60 tabular-nums"
      time.textContent = `${formatHM(it.start_time)} → ${formatHM(it.end_time)}`
      head.appendChild(dur); head.appendChild(time)

      const legs = document.createElement("div")
      legs.className = "flex items-center gap-1 mt-1 flex-wrap"
      ;(it.legs || []).forEach(leg => legs.appendChild(legBadge(leg)))

      item.appendChild(head); item.appendChild(legs)
      this.itinerariesTarget.appendChild(item)
    })
    this.itinerariesTarget.classList.remove("hidden")
    // Auto-select the first itinerary on the map.
    this.selectItinerary(0, list)
  }

  selectItinerary(idx, list) {
    this.itinerariesTarget.querySelectorAll("li").forEach((li, i) => {
      li.classList.toggle("border-primary", i === idx)
      li.classList.toggle("bg-primary/5", i === idx)
    })
    const it = list[idx]
    if (!it) return
    this.element.dispatchEvent(new CustomEvent("atlas:routing:transit", {
      detail: { legs: it.legs || [] }, bubbles: true
    }))
  }

  hideItineraries() {
    if (this.hasItinerariesTarget) {
      this.itinerariesTarget.classList.add("hidden")
      this.itinerariesTarget.innerHTML = ""
    }
  }

  hideSummary() {
    if (this.hasSummaryTarget) this.summaryTarget.classList.add("hidden")
  }

  renderRoute(data) {
    const summary = data.summary || {}
    const legs    = data.legs || []
    const shapeStrs = legs.map(l => l.shape).filter(Boolean)

    // Each leg has its own encoded polyline; concatenate decoded segments.
    this.element.dispatchEvent(new CustomEvent("atlas:routing:show", {
      detail: { shapes: shapeStrs, summary }, bubbles: true
    }))

    if (typeof summary.time === "number") {
      const mins = Math.max(1, Math.round(summary.time / 60))
      this.summaryDurationTarget.textContent = mins >= 60
        ? `${Math.floor(mins / 60)} h ${mins % 60} min`
        : `${mins} min`
    } else {
      this.summaryDurationTarget.textContent = "—"
    }
    if (typeof summary.length === "number") {
      // Valhalla returns length in the requested units (default kilometers).
      this.summaryDistanceTarget.textContent = summary.length >= 10
        ? `${summary.length.toFixed(0)} km`
        : `${summary.length.toFixed(1)} km`
    } else {
      this.summaryDistanceTarget.textContent = ""
    }
    this.renderTurnByTurn(legs)
    this.summaryTarget.classList.remove("hidden")
  }

  renderTurnByTurn(legs) {
    this.detailsTarget.innerHTML = ""
    legs.flatMap(l => l.maneuvers || []).forEach(m => {
      const li = document.createElement("li")
      const main = document.createElement("div")
      main.className = "text-sm"
      main.textContent = m.instruction || ""
      const sub = document.createElement("div")
      sub.className = "text-xs text-base-content/60"
      const parts = []
      if (typeof m.length === "number") parts.push(`${(m.length * 1000).toFixed(0)} m`)
      if (typeof m.time === "number" && m.time > 0) parts.push(`${Math.max(1, Math.round(m.time / 60))} min`)
      sub.textContent = parts.join(" · ")
      li.appendChild(main); li.appendChild(sub)
      this.detailsTarget.appendChild(li)
    })
  }

  toggleDetails() {
    this.detailsTarget.classList.toggle("hidden")
  }

  // ---- events to map ----
  dispatchEndpoint(role, coords) {
    this.element.dispatchEvent(new CustomEvent("atlas:routing:endpoint", {
      detail: { role, lon: coords.lon, lat: coords.lat, color: ENDPOINT_COLORS[role] },
      bubbles: true
    }))
  }
  dispatchClear(role) {
    this.element.dispatchEvent(new CustomEvent("atlas:routing:clearendpoint", {
      detail: { role }, bubbles: true
    }))
  }
  dispatchClearRoute() {
    this.element.dispatchEvent(new CustomEvent("atlas:routing:clear", { bubbles: true }))
  }

  showStatus(text) { this.statusTarget.textContent = text; this.statusTarget.classList.remove("hidden") }
  hideStatus()      { this.statusTarget.textContent = "";   this.statusTarget.classList.add("hidden") }
}

function formatDuration(seconds) {
  const m = Math.max(1, Math.round((seconds || 0) / 60))
  return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min`
}

function formatHM(ms) {
  const d = new Date(ms || Date.now())
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
}

const MODE_COLORS = {
  WALK:      "bg-base-300 text-base-content",
  BUS:       "bg-warning text-warning-content",
  TRAM:      "bg-error text-error-content",
  SUBWAY:    "bg-info text-info-content",
  RAIL:      "bg-success text-success-content",
  FERRY:     "bg-secondary text-secondary-content",
  CABLE_CAR: "bg-accent text-accent-content",
  GONDOLA:   "bg-accent text-accent-content"
}

function legBadge(leg) {
  const span = document.createElement("span")
  const color = MODE_COLORS[leg.mode] || "bg-base-300 text-base-content"
  span.className = `text-[10px] px-1.5 py-0.5 rounded font-medium ${color}`
  if (leg.mode === "WALK") {
    span.textContent = `🚶 ${formatDuration(leg.duration)}`
  } else {
    span.textContent = leg.route_name ? `${leg.route_name}` : leg.mode
  }
  return span
}
