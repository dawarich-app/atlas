import { Controller } from "@hotwired/stimulus"
import { lucide } from "../lib/lucide_icons"

export default class extends Controller {
  static targets = ["search", "pinned", "sections", "selected", "results", "status",
                    "nameSearch", "nameSearchWrap"]
  static values  = {
    endpoint:           { type: String, default: "/api/v1/pois" },
    categoriesEndpoint: { type: String, default: "/api/v1/pois/categories" }
  }

  async connect() {
    this.selected = new Set()
    this.catalog  = null
    this.expandedSections = new Set()
    this.filterText = ""
    this.nameQuery = ""
    this.nameTimer = null

    this.moveHandler = () => {
      if (this.selected.size === 0) return
      this.fetchAndRender()
    }
    window.addEventListener("atlas:map:moved", this.moveHandler)

    await this.loadCatalog()
    this.renderAll()
  }

  disconnect() {
    if (this.moveHandler) window.removeEventListener("atlas:map:moved", this.moveHandler)
  }

  async loadCatalog() {
    try {
      const res = await fetch(this.categoriesEndpointValue, { headers: { Accept: "application/json" } })
      const body = await res.json()
      this.catalog = body.data
      // Build flat lookup of items by id.
      this.itemsById = {}
      this.catalog.sections.forEach(s => s.items.forEach(i => { this.itemsById[i.id] = i }))
    } catch (_) {
      this.catalog = { sections: [] }
      this.itemsById = {}
    }
  }

  renderAll() {
    this.renderPinned()
    this.renderSections()
    this.renderSelected()
  }

  renderPinned() {
    if (!this.hasPinnedTarget || !this.catalog) return
    const pinned = this.catalog.sections.flatMap(s => s.items.filter(i => i.pinned))
    this.pinnedTarget.innerHTML = ""
    pinned.forEach(item => this.pinnedTarget.appendChild(this.chip(item)))
  }

  renderSections() {
    if (!this.hasSectionsTarget || !this.catalog) return
    this.sectionsTarget.innerHTML = ""

    const query = this.filterText.trim().toLowerCase()
    if (query !== "") {
      const matches = this.catalog.sections.flatMap(s => s.items).filter(i =>
        i.label.toLowerCase().includes(query) || i.id.includes(query)
      )
      const wrap = document.createElement("div")
      wrap.className = "grid grid-cols-2 gap-1 px-2 py-2"
      if (matches.length === 0) {
        const empty = document.createElement("div")
        empty.className = "col-span-2 text-xs text-base-content/50 px-2 py-3"
        empty.textContent = `No category matches “${this.filterText}”`
        wrap.appendChild(empty)
      } else {
        matches.forEach(i => wrap.appendChild(this.chip(i)))
      }
      this.sectionsTarget.appendChild(wrap)
      return
    }

    this.catalog.sections.forEach(section => {
      const wrap = document.createElement("section")
      wrap.className = "border-b border-base-200 last:border-b-0"

      const isOpen = this.expandedSections.has(section.id)
      const header = document.createElement("button")
      header.type = "button"
      header.className = "w-full px-2 py-2 flex items-center justify-between gap-2 hover:bg-base-200/40 text-left transition-colors"
      header.innerHTML = `
        <span class="flex items-center gap-2 text-xs uppercase tracking-wide text-base-content/70 font-medium">
          <span class="text-base-content/50">${sized(section.icon_svg, "w-3.5 h-3.5")}</span>
          <span>${escapeText(section.label)}</span>
          <span class="text-[10px] text-base-content/40 tabular-nums font-normal normal-case">${section.items.length}</span>
        </span>
        <span class="text-base-content/40 transition-transform ${isOpen ? "rotate-180" : ""}">
          ${chevronDown()}
        </span>
      `
      header.addEventListener("click", () => {
        if (this.expandedSections.has(section.id)) this.expandedSections.delete(section.id)
        else this.expandedSections.add(section.id)
        this.renderSections()
      })
      wrap.appendChild(header)

      if (isOpen) {
        const grid = document.createElement("div")
        grid.className = "grid grid-cols-2 gap-1 px-2 pb-2 pt-1"
        section.items.forEach(i => grid.appendChild(this.chip(i)))
        wrap.appendChild(grid)
      }

      this.sectionsTarget.appendChild(wrap)
    })
  }

  renderSelected() {
    if (this.hasNameSearchWrapTarget) {
      this.nameSearchWrapTarget.hidden = this.selected.size === 0
    }
    if (!this.hasSelectedTarget) return
    this.selectedTarget.innerHTML = ""
    if (this.selected.size === 0) { this.selectedTarget.hidden = true; return }
    this.selectedTarget.hidden = false
    Array.from(this.selected).forEach(id => {
      const item = this.itemsById[id]
      if (!item) return
      const pill = document.createElement("button")
      pill.type = "button"
      pill.className = "flex items-center gap-1 bg-primary/10 border border-primary/30 text-primary rounded-full pl-1.5 pr-2 py-0.5 text-xs hover:bg-primary/20 transition-colors"
      pill.innerHTML = `${sized(item.icon_svg, "w-3 h-3")} <span>${escapeText(item.label)}</span> <span class="text-base-content/40">×</span>`
      pill.addEventListener("click", () => this.toggleId(item.id))
      this.selectedTarget.appendChild(pill)
    })
  }

  chip(item) {
    const btn = document.createElement("button")
    btn.type = "button"
    const isSelected = this.selected.has(item.id)
    btn.className = `flex items-center gap-1.5 px-2 py-1 rounded-md border text-left text-xs truncate transition-colors
      ${isSelected
        ? "border-primary bg-primary/10 text-primary"
        : "border-base-300 text-base-content/80 hover:bg-base-200/60 hover:border-base-content/20"}`
    btn.innerHTML = `${sized(item.icon_svg, "w-3.5 h-3.5 shrink-0 " + (isSelected ? "text-primary" : "text-base-content/50"))} <span class="truncate">${escapeText(item.label)}</span>`
    btn.addEventListener("click", () => this.toggleId(item.id))
    return btn
  }

  toggleId(id) {
    if (this.selected.has(id)) this.selected.delete(id)
    else this.selected.add(id)
    this.renderAll()
    this.fetchAndRender()
  }

  onSearch() {
    this.filterText = this.searchTarget.value
    this.renderSections()
  }

  clearSearch() {
    this.searchTarget.value = ""
    this.filterText = ""
    this.renderSections()
  }

  // ---- name search within selected categories ----
  onNameSearch() {
    this.nameQuery = this.nameSearchTarget.value
    clearTimeout(this.nameTimer)
    this.nameTimer = setTimeout(() => this.fetchAndRender(), 250)
  }
  onNameSearchKey(e) {
    if (e.key === "Enter") {
      clearTimeout(this.nameTimer)
      this.fetchAndRender()
    } else if (e.key === "Escape") {
      this.clearNameSearch()
    }
  }
  clearNameSearch() {
    if (this.hasNameSearchTarget) this.nameSearchTarget.value = ""
    this.nameQuery = ""
    clearTimeout(this.nameTimer)
    this.fetchAndRender()
  }

  clear() {
    this.selected.clear()
    if (this.hasNameSearchTarget) this.nameSearchTarget.value = ""
    this.nameQuery = ""
    this.element.dispatchEvent(new CustomEvent("atlas:places:clear", { bubbles: true }))
    this.resultsTarget.innerHTML = ""
    this.statusTarget.textContent = ""
    this.statusTarget.classList.add("hidden")
    this.renderAll()
  }

  async fetchAndRender() {
    if (this.selected.size === 0) {
      this.element.dispatchEvent(new CustomEvent("atlas:places:clear", { bubbles: true }))
      this.resultsTarget.innerHTML = ""
      this.statusTarget.classList.add("hidden")
      return
    }
    const bbox = await this.askBbox()
    if (!bbox) { this.showStatus("Map not ready"); return }

    this.showStatus(this.nameQuery ? `Searching “${this.nameQuery}”…` : "Searching…")
    try {
      const url = new URL(this.endpointValue, window.location.origin)
      url.searchParams.set("bbox",  [bbox.south, bbox.west, bbox.north, bbox.east].join(","))
      url.searchParams.set("types", [...this.selected].join(","))
      if (this.nameQuery && this.nameQuery.trim()) {
        url.searchParams.set("q", this.nameQuery.trim())
      }
      const res = await fetch(url.toString(), { headers: { Accept: "application/json" } })
      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        this.showStatus(body?.error?.message || `Search failed (${res.status})`)
        return
      }
      const body = await res.json()
      const features = body.data?.features || []
      this.renderResults(features)
      this.element.dispatchEvent(new CustomEvent("atlas:places:show", {
        detail: { features }, bubbles: true
      }))
      this.showStatus(`${features.length} place${features.length === 1 ? "" : "s"} found`)
    } catch (err) {
      this.showStatus(`Network error: ${err.message}`)
    }
  }

  askBbox() {
    return new Promise(resolve => {
      const handler = (e) => {
        window.removeEventListener("atlas:map:bbox", handler)
        resolve(e.detail)
      }
      window.addEventListener("atlas:map:bbox", handler, { once: true })
      window.dispatchEvent(new CustomEvent("atlas:map:bbox-request"))
    })
  }

  renderResults(features) {
    this.resultsTarget.innerHTML = ""
    features.slice(0, 50).forEach(f => {
      const item = this.itemsById[f.category]
      const li = document.createElement("li")
      li.className = "border-b border-base-200 last:border-b-0 py-2 cursor-pointer hover:bg-base-200/50 px-2 flex items-center gap-2"
      li.addEventListener("click", () => {
        this.element.dispatchEvent(new CustomEvent("atlas:flyto", {
          detail: f.coords, bubbles: true
        }))
      })
      const iconWrap = document.createElement("div")
      iconWrap.className = "shrink-0 text-base-content/40"
      iconWrap.innerHTML = sized(item?.icon_svg, "w-4 h-4")
      const text = document.createElement("div")
      text.className = "flex-1 min-w-0"
      const name = document.createElement("div")
      name.className = "text-sm font-medium truncate"
      name.textContent = f.name || `(unnamed ${item?.label || f.category})`
      const meta = document.createElement("div")
      meta.className = "text-[10px] text-base-content/60 uppercase tracking-wide"
      meta.textContent = item?.label || f.category
      text.appendChild(name); text.appendChild(meta)
      li.appendChild(iconWrap); li.appendChild(text)
      this.resultsTarget.appendChild(li)
    })
  }

  showStatus(text) {
    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("hidden")
  }
}

// Render an SVG string with extra classes applied to <svg>. Safe to call with
// undefined; returns a tiny placeholder so layout doesn't jump.
function sized(svg, classes) {
  if (!svg) return `<span class="${classes} inline-block"></span>`
  return svg.replace(/<svg([^>]*)>/, (_m, attrs) => {
    // Drop any inline class already on the SVG and replace with ours.
    const cleaned = attrs.replace(/\s*class="[^"]*"/, "")
    return `<svg${cleaned} class="${classes}">`
  })
}

function chevronDown() {
  return lucide("chevron-down", "w-3.5 h-3.5")
}

function escapeText(s) {
  return String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]))
}
