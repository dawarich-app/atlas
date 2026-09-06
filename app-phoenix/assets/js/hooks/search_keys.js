// Keyboard navigation for the search result list.
//
// This is a hook rather than phx-keydown because two of the four keys need
// preventDefault, which a declarative binding cannot do: the arrows would
// otherwise jump the text caret to the ends of the query, and Enter would
// submit the form underneath the highlighted row.
//
// The highlight index lives on the server (MapLive's :search_active) so it
// cannot drift out of step with the result list across a re-render.
export default {
  mounted() {
    this.onKeyDown = (event) => {
      switch (event.key) {
        case "ArrowDown":
          event.preventDefault()
          this.pushEvent("search_move", { dir: 1 })
          break
        case "ArrowUp":
          event.preventDefault()
          this.pushEvent("search_move", { dir: -1 })
          break
        case "Enter":
          // Only swallow Enter when a row is highlighted; otherwise let the
          // form submit, which is still the way to search without waiting for
          // the debounce.
          if (this.el.dataset.hasActive === "true") {
            event.preventDefault()
            this.pushEvent("search_commit", {})
          }
          break
        case "Escape":
          this.pushEvent("search_dismiss", {})
          break
      }
    }

    this.el.addEventListener("keydown", this.onKeyDown)
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.onKeyDown)
  }
}
