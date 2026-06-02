import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "status"]

  copy() {
    const text = this.sourceTarget.innerText
    navigator.clipboard.writeText(text).then(
      () => this.flash("Copied!"),
      () => this.flash("Failed — copy manually")
    )
  }

  flash(msg) {
    this.statusTarget.textContent = msg
    setTimeout(() => { this.statusTarget.textContent = "" }, 2000)
  }
}
