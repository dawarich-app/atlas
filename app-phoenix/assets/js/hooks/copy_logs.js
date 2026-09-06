// CopyLogs hook — copy the full text of a log viewer to the clipboard.
//
// `data-copy-target` is the id of the element whose textContent to copy. The
// button reports the outcome inline rather than silently succeeding, because
// clipboard writes fail in ways the user cannot otherwise see: the API is
// unavailable on insecure origins (a LAN deployment over plain HTTP is a
// supported setup here), and permission can be denied outright.
export default {
  mounted() {
    this.label = this.el.dataset.copyLabel || "copy"

    this.el.addEventListener("click", async () => {
      const target = document.getElementById(this.el.dataset.copyTarget)
      if (!target) return this.flash("nothing to copy")

      const text = target.innerText.trim()
      if (!text) return this.flash("nothing to copy")

      try {
        await this.write(text)
        this.flash("copied")
      } catch (_error) {
        this.flash("copy failed")
      }
    })
  },

  // navigator.clipboard is undefined on http:// origins other than localhost,
  // so fall back to a detached textarea + execCommand, which still works there.
  async write(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text)
    }

    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.style.position = "fixed"
    area.style.opacity = "0"
    document.body.appendChild(area)
    area.select()

    try {
      if (!document.execCommand("copy")) throw new Error("execCommand refused")
    } finally {
      document.body.removeChild(area)
    }
  },

  flash(message) {
    this.el.textContent = message
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.el.textContent = this.label
    }, 1500)
  },

  destroyed() {
    clearTimeout(this.timer)
  }
}
