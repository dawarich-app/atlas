import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../app-phoenix/assets/js/hooks/map.js', import.meta.url), 'utf8').replace(/^import .*$/gm, '')
const {default: MapHook} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('a route arriving after map load while tiles are busy renders the latest data when ready', () => {
  const sources = new Map(), layers = []
  const map = {
    ready:false, isStyleLoaded(){return this.ready}, getSource:id=>sources.get(id),
    addSource(id, value){sources.set(id,{...value,setData(data){this.data=data}})},
    addLayer(layer){layers.push(layer)},
    once(){assert.fail('Must not wait for the already-fired map load event')}
  }
  const context = {map, routeGeoJSON:{features:['old']}}
  MapHook._renderRoute.call(context)
  assert.equal(sources.size,0)
  context.routeGeoJSON = {features:['new']}
  map.ready=true
  MapHook._renderRoute.call(context)
  assert.deepEqual(sources.get('route').data,{features:['new']})
  assert.deepEqual(layers.map(layer=>layer.id),['route-casing','route-line','route-walk'])
  assert.deepEqual(layers.find(layer=>layer.id==='route-walk').paint['line-dasharray'],[0,1.8])
  assert.equal(layers.find(layer=>layer.id==='route-walk').layout['line-cap'],'round')
  assert.deepEqual(layers.find(layer=>layer.id==='route-line').paint['line-color'],['coalesce',['get','color'],'#2563eb'])
  assert.equal(context._renderedRoute,context.routeGeoJSON)
  sources.clear()
  MapHook._renderRoute.call(context)
  assert.deepEqual(sources.get('route').data,{features:['new']})
})
