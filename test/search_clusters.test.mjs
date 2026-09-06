import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../app-phoenix/assets/js/hooks/search_clusters.js', import.meta.url), 'utf8')
const {default: SearchClusters} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

function harness() {
  const sources = new Map(), events = new Map(), markers = []
  const map = {
    ready: false, contains: true,
    on: (name, fn) => events.set(name, fn), off: name => events.delete(name),
    isStyleLoaded() { return this.ready }, isSourceLoaded: () => true,
    getSource: id => sources.get(id),
    addSource(id, options) { sources.set(id, {...options, setData(data) { this.data = data }}) },
    addLayer() {}, getCenter: () => ({lng:0}),
    getBounds() { return {contains: () => this.contains} },
    querySourceFeatures(id) { return sources.get(id).data.features },
  }
  const createMarker = point => {
    const marker = {point, removed:false, setLngLat() {return this}, addTo() {return this}, remove() {this.removed=true}}
    markers.push(marker)
    return marker
  }
  return {map, sources, events, markers, clusters:new SearchClusters(map, {}, createMarker)}
}
const point = id => ({id,lon:13.4,lat:52.5,label:`Point ${id}`})

test('initial load and a style swap restore the latest query, never a captured old query', () => {
  const h = harness()
  h.clusters.setPoints([point('old')])
  h.clusters.setPoints([point('new')])
  h.map.ready = true
  h.events.get('style.load')()
  assert.deepEqual(h.sources.get('search-results').data.features.map(f=>f.properties.id), ['new'])
  h.sources.clear()
  h.map.ready = false
  h.clusters.setPoints([])
  h.map.ready = true
  h.events.get('style.load')()
  assert.deepEqual(h.sources.get('search-results').data.features, [])
})

test('tile duplicates create one marker and clearing the query removes it', () => {
  const h = harness()
  h.map.ready = true
  h.clusters.setPoints([point('one'),point('one')])
  h.clusters.updateVisible()
  assert.equal(h.markers.length,1)
  h.clusters.setPoints([])
  h.clusters.updateVisible()
  assert.equal(h.markers[0].removed,true)
  assert.equal(h.clusters.markers.size,0)
})

test('panning removes off-screen markers and destruction removes map listeners', () => {
  const h = harness()
  h.map.ready = true
  h.clusters.setPoints([point('one')])
  h.clusters.updateVisible()
  h.map.contains = false
  h.clusters.updateVisible()
  assert.equal(h.markers[0].removed,true)
  h.clusters.destroy()
  assert.equal(h.events.size,0)
})
