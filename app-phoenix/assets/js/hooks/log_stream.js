// LogStream hook — auto-scroll a log container to the bottom whenever new
// child elements are appended (LiveView stream inserts).
export default {
  mounted() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.el, { childList: true })
  },

  updated() {
    this.scrollToBottom()
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}
