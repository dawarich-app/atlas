import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../app-phoenix/assets/js/hooks/route_labels.js',import.meta.url),'utf8')
const {default: RouteLabels, lineMidpoint} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('labels lie halfway along unequal path segments and handle empty or wrapped paths', () => {
  assert.deepEqual(lineMidpoint([[0,0],[1,0],[10,0]]),[5,0])
  assert.equal(lineMidpoint([]),null)
  assert.deepEqual(lineMidpoint([[1,2],[1,2]]),[1,2])
  assert.deepEqual(lineMidpoint([[179,0],[-179,0]]),[180,0])
})

test('line labels reuse markers, display text safely and disappear on route/mode change', () => {
  const previous = globalThis.document
  globalThis.document = {createElement(){return {style:{},appendChild(child){this.firstChild=child},setAttribute(key,value){this[key]=value}}}}
  const created=[]
  class Marker {
    constructor({element}){this.element=element;created.push(this)}
    setLngLat(position){this.position=position;return this}
    addTo(){return this}
    getElement(){return this.element}
    remove(){this.removed=true}
  }
  try {
    const labels=new RouteLabels({}, {Marker})
    const feature=(route_label,color)=>({properties:{route_label,color},geometry:{type:'LineString',coordinates:[[0,0],[10,0]]}})
    labels.setRoute({features:[feature(null),feature('S85','#6d28d9'),feature('S7','#007c78')]})
    assert.equal(created.length,2)
    assert.equal(created[0].element.firstChild.textContent,'S85')
    assert.equal(created[1].element.firstChild.style.backgroundColor,'#007c78')
    assert.deepEqual(created[0].position,[5,0])
    labels.setRoute({features:[feature(null),feature('<b>165</b>','#c2410c')]})
    assert.equal(created.length,2)
    assert.equal(created[0].element.firstChild.textContent,'<b>165</b>')
    assert.equal(created[1].removed,true)
    labels.setRoute({features:[]})
    assert.equal(created[0].removed,true)
    assert.equal(labels.markers.size,0)
    labels.setRoute({features:[feature('S7','#007c78')]})
    labels.destroy()
    assert.equal(created[2].removed,true)
  } finally { globalThis.document=previous }
})
