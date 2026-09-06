import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../app-phoenix/assets/js/hooks/search_clusters.js', import.meta.url), 'utf8')
const {default: SearchClusters} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

function element() {
  const classes = new Set(), attributes = {}, events = new Map()
  return {
    dataset: {}, attributes, events, textContent: "",
    classList: {toggle(name, enabled) {if (enabled) classes.add(name); else classes.delete(name)}, contains: name => classes.has(name)},
    setAttribute(name, value) {attributes[name] = value},
    addEventListener(name, callback) {events.set(name, callback)}
  }
}
globalThis.document = {createElement: () => element()}

function harness() {
  const sources = new Map(), events = new Map(), markers = []
  const map = {
    ready: false, contains: true, sourceReady: true, zoom: 5, eased: null, features: null,
    on: (name, fn) => events.set(name, fn), off: name => events.delete(name),
    isStyleLoaded() { return this.ready }, isSourceLoaded() {return this.sourceReady},
    getSource: id => sources.get(id),
    addSource(id, options) { sources.set(id, {...options, setData(data) { this.data = data }}) },
    addLayer() {}, getCenter: () => ({lng:0}),
    getBounds() { return {contains: () => this.contains} },
    querySourceFeatures(id) { return this.features || sources.get(id).data.features },
    getZoom() {return this.zoom}, getMaxZoom: () => 22,
    project: ([lon,lat]) => ({x:lon*100,y:lat*100}),
    easeTo(options) {this.eased=options},
  }
  const createMarker = point => {
    const el = element()
    const marker = {point, removed:false, additions:0, getElement: () => el,
      setLngLat(value) {this.position=value; return this},
      addTo() {this.additions++; return this}, remove() {this.removed=true}}
    markers.push(marker)
    return marker
  }
  class Marker {
    constructor({element}) {
      const marker = createMarker(null)
      marker.getElement = () => element
      return marker
    }
  }
  return {map, sources, events, markers, clusters:new SearchClusters(map, {Marker}, createMarker)}
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

const cluster = (id, count, lon=13.4) => ({geometry:{coordinates:[lon,52.5]},properties:{cluster:true,cluster_id:id,point_count:count}})

test('a progressive batch preserves points and their popup while the worker loads', () => {
  const h = harness()
  h.map.ready = true
  h.clusters.setPoints([point('one')], true)
  h.clusters.updateVisible()
  const marker = h.markers[0]
  marker.openPopup = {userOpened:true}
  h.map.sourceReady = false
  h.clusters.setPoints([point('one'), point('two')], true)
  h.clusters.updateVisible()
  assert.equal(marker.removed,false)
  assert.equal(h.clusters.markers.size,1)
  assert.equal(marker.getElement().classList.contains('atlas-marker-loading'),true)
  h.map.sourceReady = true
  h.clusters.updateVisible()
  assert.equal(h.clusters.markers.size,2)
  assert.equal(marker.additions,1)
  assert.equal(marker.openPopup.userOpened,true)
  h.clusters.setPoints([point('one'), point('two')], false)
  h.clusters.updateVisible()
  assert.equal(marker.getElement().attributes['aria-busy'],'false')
  assert.equal(marker.getElement().classList.contains('atlas-marker-loading'),false)
})

test('changed cluster IDs and counts reuse nearby DOM nodes and update click targets', async () => {
  const h = harness()
  h.map.ready = true
  h.map.features = [cluster(1,50)]
  h.clusters.setPoints([point('one')], true)
  h.clusters.updateVisible()
  const marker = h.markers[0]
  h.map.features = [cluster(22,90,13.5)]
  h.clusters.setPoints([point('one'),point('two')], true)
  h.clusters.updateVisible()
  assert.equal(h.markers.length,1)
  assert.equal(marker.additions,1)
  assert.equal(marker.removed,false)
  assert.equal(marker.getElement().dataset.count,'90')
  assert.equal(marker.getElement().attributes['aria-label'],'Zoom into 90 matches')
  let clickedID
  h.sources.get('search-results').getClusterExpansionZoom = async id => {clickedID=id; return 9}
  await marker.getElement().events.get('click')({stopPropagation() {}})
  assert.equal(clickedID,22)
  assert.deepEqual(h.map.eased,{center:[13.5,52.5],zoom:9})
})

test('exact identities are reserved before a changed neighboring cluster can reuse them', () => {
  const h = harness()
  h.map.ready = true
  h.map.features = [cluster(1,50,13.4),cluster(2,60,13.6)]
  h.clusters.setPoints([point('one')], true)
  h.clusters.updateVisible()
  const [first, second] = h.markers
  h.map.features = [cluster(3,75,13.59),cluster(2,60,13.6)]
  h.clusters.setPoints([point('one'),point('two')], true)
  h.clusters.updateVisible()
  assert.equal(h.clusters.markers.get('cluster:2'),second)
  assert.equal(h.clusters.markers.get('cluster:3'),first)
  assert.equal(h.markers.length,2)
})

test('a reused worker ID at a distant location does not teleport the old cluster', () => {
  const h = harness()
  h.map.ready = true
  h.map.features = [cluster(1,50,13.4)]
  h.clusters.setPoints([point('one')], true)
  h.clusters.updateVisible()
  h.map.features = [cluster(1,70,16)]
  h.clusters.setPoints([point('one'),point('two')], true)
  h.clusters.updateVisible()
  assert.equal(h.markers[0].removed,true)
  assert.equal(h.markers.length,2)
})

test('final data continues to pulse until indexed, and clear cannot resurrect stale source data', () => {
  const h = harness()
  h.map.ready = true
  h.clusters.setPoints([point('one')], true)
  h.clusters.updateVisible()
  const marker = h.markers[0]
  h.map.sourceReady = false
  h.clusters.setPoints([point('one')], false)
  assert.equal(marker.getElement().attributes['aria-busy'],'true')
  h.clusters.setPoints([])
  assert.equal(marker.removed,true)
  h.map.sourceReady = true
  h.map.features = [{properties:point('one')}]
  h.clusters.updateVisible()
  assert.equal(h.clusters.markers.size,0)
})

test('late cluster expansion cannot move the map after a newer batch', async () => {
  const h = harness()
  h.map.ready = true
  h.map.features = [cluster(1,50)]
  h.clusters.setPoints([point('one')], true)
  h.clusters.updateVisible()
  let resolve
  h.sources.get('search-results').getClusterExpansionZoom = () => new Promise(done => {resolve=done})
  const click = h.markers[0].getElement().events.get('click')({stopPropagation() {}})
  h.clusters.setPoints([point('one'),point('two')], true)
  resolve(9)
  await click
  assert.equal(h.map.eased,null)
})
