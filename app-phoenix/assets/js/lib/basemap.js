import { Protocol } from "pmtiles"
import { layers } from "protomaps-themes-base"

const GLYPHS = "https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf"
const SPRITES = "https://protomaps.github.io/basemaps-assets/sprites/v4"
const ATTRIBUTION = '<a href="https://protomaps.com">Protomaps</a> © <a href="https://openstreetmap.org">OpenStreetMap</a>'
const FLAVORS = new Set(["light", "dark", "grayscale", "white", "black"])

export const OSM_RASTER_FALLBACK = {
  version: 8,
  sources: {
    osm: {
      type: "raster",
      tiles: ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      tileSize: 256,
      attribution: "© OpenStreetMap contributors"
    }
  },
  layers: [{ id: "osm", type: "raster", source: "osm" }]
}

// The protocol is global to this MapLibre instance, not to a map or LiveView hook.
const registeredWith = new WeakSet()

export function registerPmtiles(maplibregl) {
  if (!registeredWith.has(maplibregl)) {
    maplibregl.addProtocol("pmtiles", new Protocol().tile)
    registeredWith.add(maplibregl)
  }
}

export function buildBasemapStyle(url, theme = "light") {
  if (!url) return OSM_RASTER_FALLBACK
  if (!isPmtilesUrl(url)) return url

  const flavor = protomapsFlavor(theme)
  const spriteFlavor = flavor === "dark" || flavor === "black" ? "dark" : "light"
  return {
    version: 8,
    glyphs: GLYPHS,
    sprite: `${SPRITES}/${spriteFlavor}`,
    sources: {
      protomaps: {
        type: "vector",
        url: url.startsWith("pmtiles://") ? url : `pmtiles://${url}`,
        attribution: ATTRIBUTION
      }
    },
    layers: layers("protomaps", flavor)
  }
}

function isPmtilesUrl(url) {
  return url.startsWith("pmtiles://") || /\.pmtiles(?:[?#].*)?$/i.test(url)
}

function protomapsFlavor(theme) {
  if (FLAVORS.has(theme)) return theme
  return typeof theme === "string" && (theme.endsWith("dark") || theme === "bunker-brutalist")
    ? "dark" : "light"
}
