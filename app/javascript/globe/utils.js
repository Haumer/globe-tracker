function C() { return window.Cesium }

export function screenToLatLng(viewer, screenPos) {
  const Cesium = C()
  const ray = viewer.camera.getPickRay(screenPos)
  const cartesian = viewer.scene.globe.pick(ray, viewer.scene)
  if (!cartesian) return null
  const carto = Cesium.Cartographic.fromCartesian(cartesian)
  return { lat: Cesium.Math.toDegrees(carto.latitude), lng: Cesium.Math.toDegrees(carto.longitude) }
}

export function haversineDistance(a, b) {
  const R = 6371000
  const toRad = d => d * Math.PI / 180
  const dLat = toRad(b.lat - a.lat)
  const dLng = toRad(b.lng - a.lng)
  const sin2 = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(sin2), Math.sqrt(1 - sin2))
}

export function pointInPolygon(lat, lng, ring) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i][0], yi = ring[i][1]
    const xj = ring[j][0], yj = ring[j][1]
    if ((yi > lat) !== (yj > lat) && lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
      inside = !inside
    }
  }
  return inside
}

export function findCountryAtPoint(features, lat, lng) {
  for (const feature of features) {
    const geom = feature.geometry
    const name = feature.properties?.NAME || feature.properties?.name
    if (!geom || !name) continue

    const polygons = geom.type === "Polygon" ? [geom.coordinates] : geom.type === "MultiPolygon" ? geom.coordinates : []
    for (const poly of polygons) {
      if (pointInPolygon(lat, lng, poly[0])) return name
    }
  }
  return null
}

export function createPlaneIcon(color) {
  const size = 32
  const canvas = document.createElement("canvas")
  canvas.width = size
  canvas.height = size
  const ctx = canvas.getContext("2d")

  ctx.translate(size / 2, size / 2)

  ctx.fillStyle = color
  ctx.beginPath()
  ctx.moveTo(0, -14)
  ctx.lineTo(3, -6)
  ctx.lineTo(3, 4)
  ctx.lineTo(0, 14)
  ctx.lineTo(-3, 4)
  ctx.lineTo(-3, -6)
  ctx.closePath()
  ctx.fill()

  ctx.beginPath()
  ctx.moveTo(0, -2)
  ctx.lineTo(12, 4)
  ctx.lineTo(12, 6)
  ctx.lineTo(3, 2)
  ctx.lineTo(-3, 2)
  ctx.lineTo(-12, 6)
  ctx.lineTo(-12, 4)
  ctx.closePath()
  ctx.fill()

  ctx.beginPath()
  ctx.moveTo(0, 10)
  ctx.lineTo(5, 13)
  ctx.lineTo(5, 14)
  ctx.lineTo(0, 12)
  ctx.lineTo(-5, 14)
  ctx.lineTo(-5, 13)
  ctx.closePath()
  ctx.fill()

  return canvas.toDataURL()
}

export function createSatelliteIcon(color, size = 36) {
  const canvas = document.createElement("canvas")
  canvas.width = size
  canvas.height = size
  const ctx = canvas.getContext("2d")
  const cx = size / 2, cy = size / 2

  ctx.translate(cx, cy)

  // Main body — rectangular bus
  ctx.fillStyle = color
  ctx.fillRect(-3, -5, 6, 10)

  // Solar panels — two rectangles on each side
  ctx.fillStyle = color
  // Left panel
  ctx.fillRect(-13, -4, 9, 8)
  // Right panel
  ctx.fillRect(4, -4, 9, 8)

  // Panel lines (grid pattern)
  ctx.strokeStyle = "rgba(0,0,0,0.4)"
  ctx.lineWidth = 0.5
  // Left panel grid
  ctx.strokeRect(-13, -4, 9, 8)
  ctx.beginPath(); ctx.moveTo(-13, 0); ctx.lineTo(-4, 0); ctx.stroke()
  ctx.beginPath(); ctx.moveTo(-8.5, -4); ctx.lineTo(-8.5, 4); ctx.stroke()
  // Right panel grid
  ctx.strokeRect(4, -4, 9, 8)
  ctx.beginPath(); ctx.moveTo(4, 0); ctx.lineTo(13, 0); ctx.stroke()
  ctx.beginPath(); ctx.moveTo(8.5, -4); ctx.lineTo(8.5, 4); ctx.stroke()

  // Antenna dish — small circle on top
  ctx.fillStyle = color
  ctx.beginPath()
  ctx.arc(0, -7, 2.5, 0, Math.PI * 2)
  ctx.fill()

  // Antenna stalk
  ctx.strokeStyle = color
  ctx.lineWidth = 1
  ctx.beginPath()
  ctx.moveTo(0, -5)
  ctx.lineTo(0, -7)
  ctx.stroke()

  return canvas.toDataURL()
}

export function getDataSource(viewer, cache, name) {
  if (!cache[name]) {
    const Cesium = C()
    cache[name] = new Cesium.CustomDataSource(name)
    viewer.dataSources.add(cache[name])
  }
  return cache[name]
}
