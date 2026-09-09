const key = "atlas:map-context:v1"
export default {
  mounted() {
    this.restoring = true
    let saved
    try { saved = JSON.parse(sessionStorage.getItem(key)) } catch (_) { /* Storage may be disabled. */ }
    // An explicit shared search always wins over this browser's previous draft.
    const params = new URLSearchParams(location.search)
    if (saved && (!params.toString() || saved.urlSearch === location.search)) {
      this.pushEvent("restore_map_context", saved, () => { this.restoring = false; this.save() })
    } else { this.restoring = false; this.save() }
  },
  updated() { if (!this.restoring) this.save() },
  save() {
    try {
      const context = JSON.parse(this.el.dataset.context)
      context.urlSearch = location.search
      sessionStorage.setItem(key, JSON.stringify(context))
    } catch (_) { /* Optional draft persistence. */ }
  }
}
