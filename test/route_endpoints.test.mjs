import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../app-phoenix/assets/js/hooks/route_endpoints.js', import.meta.url), 'utf8')
const {default: RouteEndpoints} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

globalThis.document = {createElement() {
  return {dataset:{}, attributes:{}, appendChild(){}, setAttribute(key,value){this.attributes[key]=value}}
}}
function harness() {
  const created = [], fits = []
  const map = {fitBounds(bounds, options, event){fits.push({points:bounds.points, options, event})}}
  class Marker {
    constructor({element}) {this.element=element; created.push(this)}
    getElement(){return this.element}
    setLngLat(point){this.point=point; return this}
    setPopup(popup){this.popup=popup; return this}
    getPopup(){return this.popup}
    addTo(){return this}
    remove(){this.removed=true}
  }
  class Popup {setText(text){this.text=text; return this}}
  class LngLatBounds {constructor(){this.points=[]} extend(point){this.points.push(point);return this}}
  return {created, fits, endpoints:new RouteEndpoints(map, {Marker, Popup, LngLatBounds})}
}
const from = {field:'from', lat:52.52, lon:13.4, label:'Origin'}
const to = {field:'to', lat:52.51, lon:13.5, label:'Destination'}

test('one point is centred; adding the second fits both without recreating the first marker', () => {
  const h = harness()
  h.endpoints.setPoints([from])
  assert.deepEqual(h.fits[0].points, [[13.4,52.52]])
  assert.equal(h.fits[0].options.maxZoom,14)
  assert.equal(h.fits[0].options.duration,0)
  const original = h.created[0]
  h.endpoints.setPoints([from,to])
  assert.equal(h.created.length,2)
  assert.equal(h.endpoints.markers.get('from'),original)
  assert.deepEqual(h.fits[1].points, [[13.4,52.52],[13.5,52.51]])
})

test('fitting a route includes its detours and both original endpoints, without removing markers', () => {
  const h = harness()
  h.endpoints.setPoints([from,to])
  h.endpoints.fit([[13.41,52.52],[14,53],[13.49,52.51]])
  assert.deepEqual(h.fits.at(-1).points, [[13.41,52.52],[14,53],[13.49,52.51],[13.4,52.52],[13.5,52.51]])
  assert.equal(h.created.length,2)
  assert.ok(h.created.every(marker => !marker.removed))
})

test('swap updates positions, popup labels and accessibility names in place', () => {
  const h = harness()
  h.endpoints.setPoints([from,to])
  h.endpoints.setPoints([{...to,field:'from'},{...from,field:'to'}])
  assert.equal(h.created.length,2)
  assert.deepEqual(h.created[0].point,[13.5,52.51])
  assert.equal(h.created[0].popup.text,'Destination')
  assert.equal(h.created[0].element.attributes['aria-label'],'From: Destination')
})

test('clearing an endpoint removes only its marker; clearing both does not move the camera', () => {
  const h = harness()
  h.endpoints.setPoints([from,to])
  h.endpoints.setPoints([to])
  assert.equal(h.created[0].removed,true)
  assert.ok(!h.created[1].removed)
  const fitCount = h.fits.length
  h.endpoints.setPoints([])
  assert.equal(h.created[1].removed,true)
  assert.equal(h.fits.length,fitCount)
})

test('destroy removes endpoint markers', () => {
  const h = harness()
  h.endpoints.setPoints([from,to])
  h.endpoints.destroy()
  assert.equal(h.endpoints.markers.size,0)
  assert.ok(h.created.every(marker => marker.removed))
})
