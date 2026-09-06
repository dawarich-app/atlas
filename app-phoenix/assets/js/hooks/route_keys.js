// Each endpoint owns its suggestions; never submit a stale highlighted result.
export default {
  mounted() {
    this.onKeyDown = (event) => {
      const payload = {field: this.el.dataset.field, query: this.el.value}
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault()
        this.pushEvent("route_move", {...payload, dir: event.key === "ArrowDown" ? 1 : -1})
      } else if (event.key === "Enter" && this.el.dataset.hasActive === "true" &&
                 this.el.dataset.query === this.el.value) {
        event.preventDefault()
        this.pushEvent("route_select", payload)
      } else if (event.key === "Escape" || event.key === "Tab") {
        if (event.key === "Escape") event.preventDefault()
        this.pushEvent("route_dismiss", {})
      }
    }
    this.el.addEventListener("keydown", this.onKeyDown)
    this.handleEvent("route:endpoint", ({field, value}) => {
      // LiveView deliberately preserves a focused text input's DOM value.
      if (field === this.el.dataset.field) this.el.value = value
    })
  },
  updated() {
    if (this.el.dataset.hasActive === "true") {
      document.getElementById(this.el.getAttribute("aria-activedescendant"))
        ?.scrollIntoView({block: "nearest"})
    }
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.onKeyDown)
  }
}
