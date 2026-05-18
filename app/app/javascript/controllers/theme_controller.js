import { Controller } from "@hotwired/stimulus"
import { lucide } from "../lib/lucide_icons"

const STORAGE_KEY = "atlas:theme"
const LIGHT = "forest-patina"
const DARK  = "bunker-brutalist"

const LEGACY = { light: LIGHT, dark: DARK }

export default class extends Controller {
  static targets = ["icon"]

  connect() {
    const stored = localStorage.getItem(STORAGE_KEY)
    const migrated = stored && LEGACY[stored] ? LEGACY[stored] : stored
    if (migrated && migrated !== stored) localStorage.setItem(STORAGE_KEY, migrated)
    this.theme = migrated || preferredTheme()
    this.apply()
  }

  toggle() {
    this.theme = this.isDark() ? LIGHT : DARK
    localStorage.setItem(STORAGE_KEY, this.theme)
    this.apply()
    window.dispatchEvent(new CustomEvent("atlas:theme:changed", {
      detail: { theme: this.theme, isDark: this.isDark() }
    }))
  }

  apply() {
    document.documentElement.setAttribute("data-theme", this.theme)
    if (this.hasIconTarget) {
      this.iconTarget.innerHTML = lucide(this.isDark() ? "sun" : "moon", "w-4 h-4")
    }
  }

  isDark() { return this.theme === DARK }
}

function preferredTheme() {
  if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) return DARK
  return LIGHT
}
