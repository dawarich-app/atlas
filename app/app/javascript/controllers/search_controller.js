import { Controller } from "@hotwired/stimulus"
import { lucide } from "../lib/lucide_icons"

// Photon's GeoJSON properties.type → friendly category + Lucide icon.
const TYPE_ICONS = {
  house:     ["map-pin", "Address"],
  street:    ["navigation", "Street"],
  city:      ["landmark", "City"],
  district:  ["landmark", "District"],
  locality:  ["landmark", "Locality"],
  county:    ["landmark", "County"],
  state:     ["landmark", "Region"],
  country:   ["landmark", "Country"],
  attraction:["map-pin", "Attraction"],
  amenity:   ["map-pin", "POI"],
  shop:      ["map-pin", "Shop"],
  tourism:   ["map-pin", "Tourism"],
  leisure:   ["map-pin", "Leisure"],
  station:   ["train-front", "Station"],
  airport:   ["map-pin", "Airport"]
}

const DEBOUNCE_MS = 200
const MIN_QUERY_LENGTH = 2

export default class extends Controller {
  static targets = ["input", "results", "status"]
  static values = { endpoint: String }

  connect() {
    this.timer = null
    this.lastQuery = ""
    this.results = []
    this.activeIndex = -1

    // Re-fetch with the new bbox when the map is panned/zoomed, but only if
    // there's an active query — otherwise it's noise.
    this.moveHandler = () => {
      const q = this.inputTarget.value.trim()
      if (q.length < MIN_QUERY_LENGTH) return
      this.fetchResults(q)
    }
    window.addEventListener("atlas:map:moved", this.moveHandler)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
    if (this.moveHandler) window.removeEventListener("atlas:map:moved", this.moveHandler)
  }

  query() {
    const q = this.inputTarget.value.trim()
    if (q === this.lastQuery) return
    this.lastQuery = q

    if (this.timer) clearTimeout(this.timer)
    if (q.length < MIN_QUERY_LENGTH) {
      this.hideResults()
      return
    }

    this.timer = setTimeout(() => this.fetchResults(q), DEBOUNCE_MS)
  }

  keydown(event) {
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.moveActive(1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.moveActive(-1)
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.commitActive()
    } else if (event.key === "Escape") {
      this.hideResults()
    }
  }

  stop(event) {
    event.stopPropagation()
  }

  clear() {
    this.inputTarget.value = ""
    this.lastQuery = ""
    this.hideResults()
    this.broadcastResults([])
    this.inputTarget.focus()
  }

  async askBbox() {
    return new Promise(resolve => {
      const handler = (e) => {
        window.removeEventListener("atlas:map:bbox", handler)
        resolve(e.detail)
      }
      window.addEventListener("atlas:map:bbox", handler, { once: true })
      window.dispatchEvent(new CustomEvent("atlas:map:bbox-request"))
      // Give the map 200ms to respond; carry on without bbox if it doesn't.
      setTimeout(() => { window.removeEventListener("atlas:map:bbox", handler); resolve(null) }, 200)
    })
  }

  async fetchResults(q) {
    this.showStatus("Searching…")
    try {
      const url = new URL(this.endpointValue, window.location.origin)
      url.searchParams.set("q", q)
      url.searchParams.set("limit", "40")

      // Scope to the current viewport so brand searches (e.g. "McDonald's")
      // return every visible match, not just the global top-N.
      const bbox = await this.askBbox()
      if (bbox) {
        // Photon expects west,south,east,north
        url.searchParams.set("bbox", [bbox.west, bbox.south, bbox.east, bbox.north].join(","))
      }

      const response = await fetch(url.toString(), { headers: { Accept: "application/json" } })

      if (!response.ok) {
        const body = await response.json().catch(() => ({}))
        const message = body?.error?.message || `Search failed (${response.status})`
        this.showStatus(message)
        this.renderItems([])
        return
      }

      const body = await response.json()
      const features = body.data || []
      this.results = features
      this.activeIndex = features.length > 0 ? 0 : -1

      if (features.length === 0) {
        this.showStatus("No results")
      } else {
        this.hideStatus()
      }
      this.renderItems(features)
      this.broadcastResults(features)
    } catch (err) {
      this.showStatus(`Network error: ${err.message}`)
      this.renderItems([])
    }
  }

  renderItems(items) {
    this.resultsTarget.innerHTML = ""
    if (items.length === 0) {
      this.resultsTarget.classList.add("hidden")
      return
    }
    items.forEach((item, idx) => {
      const [iconName, kindLabel] = TYPE_ICONS[item.type] || ["map-pin", item.type || "Result"]

      const li = document.createElement("li")
      li.className = `flex items-center gap-2 px-2 py-1.5 rounded-md cursor-pointer transition-colors
        ${idx === this.activeIndex ? "bg-primary/10" : "hover:bg-base-200/70"}`
      li.dataset.index = idx
      li.addEventListener("click", (e) => {
        e.preventDefault()
        this.activeIndex = idx
        this.commitActive()
      })

      const iconWrap = document.createElement("span")
      iconWrap.className = "shrink-0 text-base-content/40 flex items-center justify-center w-7 h-7 rounded-md bg-base-200/50"
      iconWrap.innerHTML = lucide(iconName, "w-4 h-4")

      const text = document.createElement("div")
      text.className = "flex-1 min-w-0 flex flex-col"

      const name = document.createElement("span")
      name.className = "text-sm font-medium leading-tight truncate"
      name.textContent = item.name || item.label || "(unnamed)"

      const sub = document.createElement("span")
      sub.className = "text-[11px] text-base-content/60 truncate"
      const subText = item.label && item.label !== name.textContent ? item.label : kindLabel
      sub.textContent = subText

      text.appendChild(name)
      text.appendChild(sub)

      const kind = document.createElement("span")
      kind.className = "shrink-0 text-[9px] uppercase tracking-wide text-base-content/40 ml-1"
      kind.textContent = kindLabel

      li.appendChild(iconWrap)
      li.appendChild(text)
      li.appendChild(kind)
      this.resultsTarget.appendChild(li)
    })
    this.resultsTarget.classList.remove("hidden")
  }

  moveActive(delta) {
    if (this.results.length === 0) return
    this.activeIndex = (this.activeIndex + delta + this.results.length) % this.results.length
    this.renderItems(this.results)
  }

  commitActive() {
    const item = this.results[this.activeIndex]
    if (!item) return
    this.inputTarget.value = item.label || item.name || ""
    this.lastQuery = this.inputTarget.value
    this.hideResults()
    this.dispatch("flyto", { detail: item.coords, prefix: "atlas", bubbles: true })
    this.broadcastResults([item])
  }

  hideResults() {
    this.resultsTarget.classList.add("hidden")
    this.hideStatus()
  }

  showStatus(text) {
    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("hidden")
  }

  hideStatus() {
    this.statusTarget.classList.add("hidden")
    this.statusTarget.textContent = ""
  }

  broadcastResults(features) {
    const event = new CustomEvent("atlas:setresults", { detail: features, bubbles: true })
    this.element.dispatchEvent(event)
  }
}
