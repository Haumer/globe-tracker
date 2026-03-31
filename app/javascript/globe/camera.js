function C() { return window.Cesium }

// ── Persistence ──────────────────────────────────────────

export function saveCamera(viewer) {
  if (!viewer?.camera) return
  const carto = viewer.camera.positionCartographic
  sessionStorage.setItem("globe_camera", JSON.stringify({
    lng: C().Math.toDegrees(carto.longitude),
    lat: C().Math.toDegrees(carto.latitude),
    height: carto.height,
    heading: viewer.camera.heading,
    pitch: viewer.camera.pitch,
  }))
}

export function restoreCamera(viewer, prefs) {
  // DB prefs take priority
  if (prefs?.camera_lat != null && prefs?.camera_lng != null) {
    viewer.camera.setView({
      destination: C().Cartesian3.fromDegrees(
        prefs.camera_lng, prefs.camera_lat, prefs.camera_height || 20_000_000
      ),
      orientation: {
        heading: prefs.camera_heading || 0,
        pitch: prefs.camera_pitch || -C().Math.PI_OVER_TWO,
        roll: 0,
      },
    })
    return
  }

  // Fall back to sessionStorage
  const saved = sessionStorage.getItem("globe_camera")
  if (saved) {
    try {
      const cam = JSON.parse(saved)
      viewer.camera.setView({
        destination: C().Cartesian3.fromDegrees(cam.lng, cam.lat, cam.height),
        orientation: { heading: cam.heading, pitch: cam.pitch, roll: 0 },
      })
      return
    } catch { /* fall through to default */ }
  }

  // Default view
  viewer.camera.flyTo({
    destination: C().Cartesian3.fromDegrees(10, 30, 20_000_000), duration: 0,
  })
}

// ── Viewport ─────────────────────────────────────────────

export function getViewportBounds(viewer) {
  if (!viewer?.scene?.canvas) return null
  const scene = viewer.scene
  const canvas = scene.canvas
  const w = canvas.width, h = canvas.height
  if (!w || !h) return null

  const corners = [
    new C().Cartesian2(0, 0),
    new C().Cartesian2(w, 0),
    new C().Cartesian2(0, h),
    new C().Cartesian2(w, h),
    new C().Cartesian2(w / 2, 0),
    new C().Cartesian2(w / 2, h),
    new C().Cartesian2(0, h / 2),
    new C().Cartesian2(w, h / 2),
  ]

  const lats = [], lngs = []
  try {
    for (const corner of corners) {
      const ray = scene.camera.getPickRay(corner)
      if (!ray) continue
      const pos = scene.globe.pick(ray, scene)
      if (pos) {
        const carto = C().Cartographic.fromCartesian(pos)
        lats.push(C().Math.toDegrees(carto.latitude))
        lngs.push(C().Math.toDegrees(carto.longitude))
      }
    }
  } catch { return null }

  if (lats.length === 0) return null

  return {
    lamin: Math.min(...lats),
    lamax: Math.max(...lats),
    lomin: Math.min(...lngs),
    lomax: Math.max(...lngs),
  }
}

export function getPlaybackBounds(viewer) {
  const viewportBounds = getViewportBounds(viewer)
  const candidateBounds = viewportBounds || computeViewRectangleBounds(viewer) || approximateCameraBounds(viewer)
  if (!candidateBounds) return null

  return clampPlaybackBounds(candidateBounds, viewer)
}

// ── Camera Controls ──────────────────────────────────────

function flyToCurrentPosition(viewer, { heightFactor = 1, maxHeight, heading, pitch, duration = 0.5 } = {}) {
  const carto = viewer.camera.positionCartographic
  let height = carto.height * heightFactor
  if (maxHeight != null) height = Math.min(height, maxHeight)

  const options = {
    destination: C().Cartesian3.fromDegrees(
      C().Math.toDegrees(carto.longitude),
      C().Math.toDegrees(carto.latitude),
      height
    ),
    duration,
  }

  if (heading != null || pitch != null) {
    options.orientation = {
      heading: heading ?? viewer.camera.heading,
      pitch: pitch ?? viewer.camera.pitch,
      roll: 0,
    }
  }

  viewer.camera.flyTo(options)
}

export function resetView(viewer) {
  viewer.camera.flyTo({
    destination: C().Cartesian3.fromDegrees(10, 30, 20_000_000),
    orientation: { heading: 0, pitch: -C().Math.PI_OVER_TWO, roll: 0 },
    duration: 1.5,
  })
}

export function viewTopDown(viewer) {
  flyToCurrentPosition(viewer, {
    heading: 0,
    pitch: -C().Math.PI_OVER_TWO,
    duration: 1,
  })
}

export function resetTilt(viewer) {
  flyToCurrentPosition(viewer, {
    pitch: -C().Math.PI_OVER_TWO,
    duration: 0.8,
  })
}

export function zoomIn(viewer) {
  flyToCurrentPosition(viewer, { heightFactor: 0.5 })
}

export function zoomOut(viewer) {
  flyToCurrentPosition(viewer, { heightFactor: 2, maxHeight: 40_000_000 })
}

function computeViewRectangleBounds(viewer) {
  const scene = viewer?.scene
  const rectangle = scene?.camera?.computeViewRectangle?.(scene?.globe?.ellipsoid)
  if (!rectangle) return null

  return {
    lamin: C().Math.toDegrees(rectangle.south),
    lamax: C().Math.toDegrees(rectangle.north),
    lomin: C().Math.toDegrees(rectangle.west),
    lomax: C().Math.toDegrees(rectangle.east),
  }
}

function approximateCameraBounds(viewer) {
  const carto = viewer?.camera?.positionCartographic
  if (!carto) return null

  const lat = C().Math.toDegrees(carto.latitude)
  const lng = C().Math.toDegrees(carto.longitude)
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null

  const latSpan = playbackLatSpanForHeight(carto.height)
  const lngSpan = latSpan / Math.max(Math.cos(lat * Math.PI / 180), 0.25)

  return {
    lamin: lat - latSpan / 2,
    lamax: lat + latSpan / 2,
    lomin: lng - lngSpan / 2,
    lomax: lng + lngSpan / 2,
  }
}

function clampPlaybackBounds(bounds, viewer) {
  const centerLat = midpoint(bounds.lamin, bounds.lamax)
  const centerLng = midpoint(bounds.lomin, bounds.lomax)
  const latSpan = Math.abs(bounds.lamax - bounds.lamin)
  const lngSpan = Math.abs(bounds.lomax - bounds.lomin)
  const maxLatSpan = playbackLatSpanForHeight(viewer?.camera?.positionCartographic?.height)
  const maxLngSpan = maxLatSpan / Math.max(Math.cos(centerLat * Math.PI / 180), 0.25)
  const clampedLatSpan = Math.max(2, Math.min(latSpan || maxLatSpan, maxLatSpan))
  const clampedLngSpan = Math.max(2, Math.min(lngSpan || maxLngSpan, maxLngSpan))

  return {
    lamin: Math.max(-85, centerLat - clampedLatSpan / 2),
    lamax: Math.min(85, centerLat + clampedLatSpan / 2),
    lomin: centerLng - clampedLngSpan / 2,
    lomax: centerLng + clampedLngSpan / 2,
  }
}

function playbackLatSpanForHeight(height) {
  if (!Number.isFinite(height) || height <= 0) return 8
  return Math.max(4, Math.min(24, height / 300000))
}

function midpoint(a, b) {
  if (Number.isFinite(a) && Number.isFinite(b)) return (a + b) / 2
  if (Number.isFinite(a)) return a
  if (Number.isFinite(b)) return b
  return 0
}
