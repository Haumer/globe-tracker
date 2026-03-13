function C() { return window.Cesium }

// ── Standard entity label config ─────────────────────────────
// Use these for consistent sizing/positioning across all layers.
export const LABEL_DEFAULTS = {
  font: "13px JetBrains Mono, monospace",
  outlineWidth: 3,
  style: () => C().LabelStyle.FILL_AND_OUTLINE,
  outlineColor: () => C().Color.BLACK.withAlpha(0.8),
  scaleByDistance: () => new (C()).NearFarScalar(5e4, 1, 5e6, 0.35),
  // Labels fade in only when close — prevents jumbled text at far zoom
  translucencyByDistance: () => new (C()).NearFarScalar(5e4, 1, 5e5, 0),
  pixelOffsetBelow: () => new (C()).Cartesian2(0, 14),
  pixelOffsetAbove: () => new (C()).Cartesian2(0, -14),
  // Always render on top of 3D tiles / terrain — prevents entities hiding under photorealistic buildings
  disableDepthTest: Number.POSITIVE_INFINITY,
}

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

// ── Power plant icons by fuel category ────────────────────────
// Nuclear: circle-with-dot, Fossil: square, Renewable: triangle, Other: diamond
const _ppIconCache = new Map()

function _drawPPIcon(ctx, shape, color, s) {
  ctx.fillStyle = color
  ctx.strokeStyle = "rgba(0,0,0,0.5)"
  ctx.lineWidth = 1
  const h = s / 2

  if (shape === "circle") {
    // Nuclear — bullseye
    ctx.beginPath()
    ctx.arc(h, h, h - 2, 0, Math.PI * 2)
    ctx.fill(); ctx.stroke()
    ctx.beginPath()
    ctx.arc(h, h, 3, 0, Math.PI * 2)
    ctx.fillStyle = "rgba(0,0,0,0.4)"
    ctx.fill()
  } else if (shape === "square") {
    // Fossil
    const pad = 3
    ctx.fillRect(pad, pad, s - pad * 2, s - pad * 2)
    ctx.strokeRect(pad, pad, s - pad * 2, s - pad * 2)
  } else if (shape === "triangle") {
    // Renewable
    ctx.beginPath()
    ctx.moveTo(h, 2)
    ctx.lineTo(s - 2, s - 2)
    ctx.lineTo(2, s - 2)
    ctx.closePath()
    ctx.fill(); ctx.stroke()
  } else {
    // Diamond — other
    ctx.beginPath()
    ctx.moveTo(h, 2)
    ctx.lineTo(s - 2, h)
    ctx.lineTo(h, s - 2)
    ctx.lineTo(2, h)
    ctx.closePath()
    ctx.fill(); ctx.stroke()
  }
}

const PP_SHAPE_MAP = {
  Nuclear: "circle",
  Coal: "square", Gas: "square", Oil: "square", Petcoke: "square", Cogeneration: "square",
  Solar: "triangle", Wind: "triangle", Hydro: "triangle",
  Biomass: "diamond", Geothermal: "diamond", Waste: "diamond", Storage: "diamond", Other: "diamond",
}

export function createPowerPlantIcon(fuel, color) {
  const key = fuel + "|" + color
  if (_ppIconCache.has(key)) return _ppIconCache.get(key)
  const s = 20
  const canvas = document.createElement("canvas")
  canvas.width = s; canvas.height = s
  const ctx = canvas.getContext("2d")
  const shape = PP_SHAPE_MAP[fuel] || "diamond"
  _drawPPIcon(ctx, shape, color, s)
  const url = canvas.toDataURL()
  _ppIconCache.set(key, url)
  return url
}

// ── Airport icon — crosshair ─────────────────────────────────
const _apIconCache = new Map()

export function createAirportIcon(color, isMilitary) {
  const key = color + (isMilitary ? "-mil" : "")
  if (_apIconCache.has(key)) return _apIconCache.get(key)
  const s = 18
  const canvas = document.createElement("canvas")
  canvas.width = s; canvas.height = s
  const ctx = canvas.getContext("2d")
  const h = s / 2

  ctx.strokeStyle = color
  ctx.lineWidth = 1.5

  // Crosshair
  ctx.beginPath()
  ctx.moveTo(h, 2); ctx.lineTo(h, s - 2) // vertical
  ctx.moveTo(2, h); ctx.lineTo(s - 2, h) // horizontal
  ctx.stroke()

  // Center dot
  ctx.fillStyle = color
  ctx.beginPath()
  ctx.arc(h, h, 2, 0, Math.PI * 2)
  ctx.fill()

  if (isMilitary) {
    // Small corner marks for military
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(3, 3); ctx.lineTo(6, 3); ctx.moveTo(3, 3); ctx.lineTo(3, 6)
    ctx.moveTo(s - 3, 3); ctx.lineTo(s - 6, 3); ctx.moveTo(s - 3, 3); ctx.lineTo(s - 3, 6)
    ctx.stroke()
  }

  const url = canvas.toDataURL()
  _apIconCache.set(key, url)
  return url
}

// ── Train icon — filled circle ──────────────────────────────
const _trainIconCache = new Map()

export function createTrainIcon(color) {
  if (_trainIconCache.has(color)) return _trainIconCache.get(color)
  const s = 18
  const canvas = document.createElement("canvas")
  canvas.width = s; canvas.height = s
  const ctx = canvas.getContext("2d")
  const h = s / 2

  ctx.fillStyle = color
  ctx.beginPath()
  ctx.arc(h, h, h - 2, 0, Math.PI * 2)
  ctx.fill()

  ctx.strokeStyle = "rgba(0,0,0,0.5)"
  ctx.lineWidth = 1
  ctx.beginPath()
  ctx.arc(h, h, h - 2, 0, Math.PI * 2)
  ctx.stroke()

  const url = canvas.toDataURL()
  _trainIconCache.set(color, url)
  return url
}

export function getDataSource(viewer, cache, name) {
  if (!cache[name]) {
    const Cesium = C()
    cache[name] = new Cesium.CustomDataSource(name)
    viewer.dataSources.add(cache[name])
  }
  return cache[name]
}
