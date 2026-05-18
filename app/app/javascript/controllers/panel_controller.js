import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body"]
  static values  = { open: Boolean }

  connect() {
    const stored = localStorage.getItem("atlas:panel-open")
    if (stored === "true") this.openValue = true
    this.render()
  }

  toggle() {
    this.openValue = !this.openValue
    localStorage.setItem("atlas:panel-open", this.openValue)
    this.render()
  }

  render() {
    this.bodyTarget.classList.toggle("hidden", !this.openValue)
  }
}
