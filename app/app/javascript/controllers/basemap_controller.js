import { Controller } from "@hotwired/stimulus"

const PRESETS = [
  { id: "openfreemap",
    label: "OpenFreeMap Liberty",
    note:  "Hosted vector tiles · planet · no key",
    url:   "https://tiles.openfreemap.org/styles/liberty" },
  { id: "openfreemap-positron",
    label: "OpenFreeMap Positron",
    note:  "Light grayscale · planet · hosted",
    url:   "https://tiles.openfreemap.org/styles/positron" },
  { id: "openfreemap-bright",
    label: "OpenFreeMap Bright",
    note:  "Bright · planet · hosted",
    url:   "https://tiles.openfreemap.org/styles/bright" },
  { id: "protomaps-planet-daily",
    label: "Protomaps planet (daily)",
    note:  "~100 GB pmtiles · range-served by R2 · today's UTC build",
    download: true,
    urlBuilder: () => {
      const d = new Date()
      const yyyymmdd = d.getUTCFullYear().toString() +
        String(d.getUTCMonth() + 1).padStart(2, "0") +
        String(d.getUTCDate()).padStart(2, "0")
      return `https://build.protomaps.com/${yyyymmdd}.pmtiles`
    } }
]

export default class extends Controller {
  static targets = ["effective", "envSource", "localStatus", "downloadBlock",
                    "downloadLabel", "downloadBar", "downloadPercent",
                    "presetGrid", "customUrl", "status"]
  static values = {
    showUrl:     { type: String, default: "/admin/tiles" },
    updateUrl:   { type: String, default: "/admin/tiles" },
    downloadUrl: { type: String, default: "/admin/tiles/download" }
  }

  async connect() {
    this.renderPresets()
    await this.refresh()
    // If a download is already in flight (from a previous page load), resume polling.
    if (this.state?.local?.download?.status === "downloading") this.pollDownload()
  }

  disconnect() { clearInterval(this.pollTimer) }

  async refresh() {
    try {
      const res  = await fetch(this.showUrlValue, { headers: { Accept: "application/json" } })
      const body = await res.json()
      this.state = body.data
      this.render()
    } catch (err) {
      this.showStatus(`Refresh failed: ${err.message}`)
    }
  }

  render() {
    if (!this.state) return
    if (this.hasEffectiveTarget) this.effectiveTarget.textContent = this.state.effective || "(OSM raster fallback)"
    if (this.hasEnvSourceTarget) this.envSourceTarget.textContent = this.state.env || "(unset)"
    if (this.hasLocalStatusTarget) {
      if (this.state.local?.exists) {
        const mb = (this.state.local.size_bytes / 1024 / 1024).toFixed(1)
        const when = this.state.local.modified_at ? new Date(this.state.local.modified_at).toLocaleString() : ""
        this.localStatusTarget.innerHTML =
          `<span class="text-success">●</span> ${mb} MB <span class="text-base-content/50">· ${when}</span>`
      } else {
        this.localStatusTarget.innerHTML = `<span class="text-base-content/40">— not downloaded</span>`
      }
    }
    this.renderDownload()
  }

  renderDownload() {
    if (!this.hasDownloadBlockTarget) return
    const d = this.state?.local?.download
    if (!d) { this.downloadBlockTarget.hidden = true; return }

    this.downloadBlockTarget.hidden = false
    const doneMB = (d.bytes_done / 1024 / 1024)
    const totalMB = (d.bytes_total || 0) / 1024 / 1024
    const elapsedS = d.started_at ? Math.max(1, (Date.now() - new Date(d.started_at).getTime()) / 1000) : 1
    const rate = d.bytes_done / elapsedS // bytes/sec

    let label, percentText, percentValue
    if (d.status === "downloading") {
      if (totalMB > 0) {
        const pct = Math.min(100, (d.bytes_done / d.bytes_total) * 100)
        percentValue = pct
        percentText  = `${pct.toFixed(1)}%`
        label = `${doneMB.toFixed(1)} / ${totalMB.toFixed(1)} MB · ${humanRate(rate)}`
      } else {
        percentValue = null // indeterminate
        percentText  = "—"
        label = `${doneMB.toFixed(1)} MB · ${humanRate(rate)}`
      }
    } else if (d.status === "complete") {
      percentValue = 100; percentText = "Done"
      label = `Completed · ${doneMB.toFixed(1)} MB`
    } else {
      percentValue = 0; percentText = "Error"
      label = d.error || "Download failed"
    }

    this.downloadLabelTarget.textContent = label
    this.downloadPercentTarget.textContent = percentText
    if (percentValue == null) {
      this.downloadBarTarget.removeAttribute("value")
    } else {
      this.downloadBarTarget.value = percentValue
    }
    this.downloadBarTarget.classList.toggle("progress-error", d.status === "error")
    this.downloadBarTarget.classList.toggle("progress-success", d.status === "complete")
    this.downloadBarTarget.classList.toggle("progress-primary", d.status === "downloading")
  }

  renderPresets() {
    if (!this.hasPresetGridTarget) return
    this.presetGridTarget.innerHTML = ""
    PRESETS.forEach(p => {
      const card = document.createElement("div")
      card.className = "border border-base-300 rounded-md p-2 flex flex-col gap-1.5"
      card.innerHTML = `
        <div class="text-sm font-medium leading-tight">${escapeText(p.label)}</div>
        <div class="text-[10px] text-base-content/60 leading-snug">${escapeText(p.note)}</div>
      `
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "btn btn-xs btn-primary mt-1 self-start"
      btn.textContent = p.download ? "Download & use" : "Use"
      btn.addEventListener("click", () => {
        const url = p.urlBuilder ? p.urlBuilder() : p.url
        if (p.download) this.downloadAndSwitch(url)
        else            this.useUrl(url)
      })
      card.appendChild(btn)
      this.presetGridTarget.appendChild(card)
    })
  }

  async useCustom(event) {
    event.preventDefault()
    const url = this.customUrlTarget.value.trim()
    if (!url) return
    await this.useUrl(url)
  }

  async useLocal() {
    await this.postUpdate({ source: "local" })
    this.notifyMap()
    this.showStatus("Switched to local pmtiles")
  }

  async useEnv() {
    await this.postUpdate({ source: "env" })
    this.notifyMap()
    this.showStatus("Reverted to .env default")
  }

  async useUrl(url) {
    await this.postUpdate({ source: "url", url })
    this.notifyMap()
    this.showStatus("Switched basemap")
  }

  async downloadAndSwitch(url) {
    this.showStatus(`Starting download…`)
    try {
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content
      const headers = { "Content-Type": "application/json", "Accept": "application/json" }
      if (csrf) headers["X-CSRF-Token"] = csrf
      const res = await fetch(this.downloadUrlValue, {
        method: "POST", headers, body: JSON.stringify({ url })
      })
      if (!res.ok) {
        const body = await res.json().catch(() => ({}))
        this.showStatus(body?.error?.message || `Download failed (${res.status})`)
        return
      }
      this.showStatus(`Downloading in background — switch source manually once finished.`)
      // Refresh size info periodically while download is happening.
      this.pollDownload()
    } catch (err) {
      this.showStatus(`Network error: ${err.message}`)
    }
  }

  pollDownload() {
    clearInterval(this.pollTimer)
    this.pollTimer = setInterval(async () => {
      await this.refresh()
      const d = this.state?.local?.download
      if (!d) return
      if (d.status === "complete" || d.status === "error") {
        clearInterval(this.pollTimer)
        if (d.status === "complete") this.showStatus(`Download complete (${(d.bytes_done/1024/1024).toFixed(1)} MB)`)
      }
    }, 2000)
  }

  async postUpdate(payload) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const headers = { "Content-Type": "application/json", "Accept": "application/json" }
    if (csrf) headers["X-CSRF-Token"] = csrf
    const res = await fetch(this.updateUrlValue, {
      method: "PATCH", headers, body: JSON.stringify(payload)
    })
    if (!res.ok) {
      const body = await res.json().catch(() => ({}))
      this.showStatus(body?.error?.message || `Switch failed (${res.status})`)
      return
    }
    await this.refresh()
  }

  notifyMap() {
    // Map controller listens and reloads its style.
    window.dispatchEvent(new CustomEvent("atlas:basemap:changed"))
  }

  showStatus(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("hidden")
  }
}

function escapeText(s) {
  return String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]))
}

function humanRate(bytesPerSec) {
  const v = Number(bytesPerSec) || 0
  if (v > 1024 * 1024) return `${(v / 1024 / 1024).toFixed(1)} MB/s`
  if (v > 1024)        return `${(v / 1024).toFixed(0)} KB/s`
  return `${v.toFixed(0)} B/s`
}
