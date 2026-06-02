// Decode a Google-style encoded polyline at the given precision into an
// array of [lon, lat] pairs (GeoJSON order). Valhalla uses precision 6;
// OTP, OSRM, and Google Maps proper use precision 5.
//
// Ported from Rails `app/javascript/lib/polyline6.js`.
export function decodePolyline(str, precision = 6) {
  const factor = Math.pow(10, precision)
  let index = 0, lat = 0, lng = 0
  const coords = []

  while (index < str.length) {
    let result = 0, shift = 0, byte
    do {
      byte = str.charCodeAt(index++) - 63
      result |= (byte & 0x1f) << shift
      shift += 5
    } while (byte >= 0x20)
    const dlat = (result & 1) ? ~(result >> 1) : (result >> 1)
    lat += dlat

    result = 0; shift = 0
    do {
      byte = str.charCodeAt(index++) - 63
      result |= (byte & 0x1f) << shift
      shift += 5
    } while (byte >= 0x20)
    const dlng = (result & 1) ? ~(result >> 1) : (result >> 1)
    lng += dlng

    coords.push([lng / factor, lat / factor])
  }

  return coords
}

export const decodePolyline6 = (str) => decodePolyline(str, 6)
export const decodePolyline5 = (str) => decodePolyline(str, 5)
