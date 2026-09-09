export default {
  mounted() {
    this.sync()
    this.onChange = () => {
      const value = this.el.value
      if (!value) this.pushEvent("route_departure", {departure: ""})
      else {
        const date = new Date(value)
        if (!Number.isNaN(date.getTime())) this.pushEvent("route_departure", {departure: date.toISOString()})
      }
    }
    this.el.addEventListener("change", this.onChange)
  },
  updated() { this.sync() },
  sync() {
    const value = this.el.dataset.value
    if (!value) { this.el.value = ""; return }
    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return
    const pad = value => String(value).padStart(2, "0")
    this.el.value = `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
  },
  destroyed() { this.el.removeEventListener("change", this.onChange) }
}
