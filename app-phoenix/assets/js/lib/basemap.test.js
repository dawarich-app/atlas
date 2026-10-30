import assert from "node:assert/strict"
import test from "node:test"
import { buildBasemapStyle, registerPmtiles, OSM_RASTER_FALLBACK } from "./basemap.js"

test("PMTiles archives become MapLibre styles with a protocol vector source", () => {
  for (const url of ["/tiles/20261030.pmtiles", "https://example.com/planet.pmtiles?token=abc", "pmtiles:///tiles/planet.pmtiles"]) {
    const style = buildBasemapStyle(url, "atlas-dark")
    assert.equal(style.version, 8)
    assert.equal(style.sources.protomaps.type, "vector")
    assert.equal(style.sources.protomaps.url, url.startsWith("pmtiles://") ? url : `pmtiles://${url}`)
    assert.equal(style.sprite, "https://protomaps.github.io/basemaps-assets/sprites/v4/dark")
    assert.ok(style.layers.length > 20)
    assert.ok(style.layers.some(layer => layer["source-layer"]))
  }
})

test("hosted styles and the empty fallback retain their previous behavior", () => {
  const hosted = "https://tiles.example.com/style.json"
  assert.equal(buildBasemapStyle(hosted), hosted)
  assert.deepEqual(buildBasemapStyle(""), OSM_RASTER_FALLBACK)
  assert.equal(buildBasemapStyle("/tiles/planet.pmtiles", "forest-patina").sprite,
    "https://protomaps.github.io/basemaps-assets/sprites/v4/light")
})

test("PMTiles protocol is registered once per MapLibre instance", () => {
  const calls = []
  const maplibre = { addProtocol: (...args) => calls.push(args) }
  registerPmtiles(maplibre)
  registerPmtiles(maplibre)
  assert.equal(calls.length, 1)
  assert.equal(calls[0][0], "pmtiles")
  assert.equal(typeof calls[0][1], "function")
})
