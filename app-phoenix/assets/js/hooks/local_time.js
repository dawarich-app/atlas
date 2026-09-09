export default {
  mounted() { this.format() },
  updated() { this.format() },
  format() {
    const date = new Date(this.el.dateTime)
    if (Number.isNaN(date.getTime())) return
    const options = this.el.dataset.compact === "true"
      ? {hour: "2-digit", minute: "2-digit", timeZoneName: "short"}
      : {dateStyle: "medium", timeStyle: "short"}
    this.el.textContent = new Intl.DateTimeFormat(undefined, options).format(date)
    this.el.title = new Intl.DateTimeFormat(undefined, {dateStyle: "full", timeStyle: "long"}).format(date)
  }
}
