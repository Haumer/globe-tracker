import { getViewportBounds } from "globe/camera"

function C() { return window.Cesium }

// Animating every point on the globe is what made the map feel busy rather than
// alive, so each layer only ever breathes for what is on screen, and only up to
// this many points. Everything else renders static.
const MAX_ANIMATED_PER_LAYER = 120

// Only the top slice of a layer by weight earns an expanding halo ping.
const HALO_SHARE = 0.25

const MIN_PERIOD = 2.6
const PERIOD_SPREAD = 1.9

function state(controller) {
  if (!controller._ambient) {
    controller._ambient = {
      entries: new Map(),
      layers: new Map(),
      staging: new Map(),
      bounds: null,
      boundsStale: true,
      raf: null,
      lastPump: 0,
    }
  }
  return controller._ambient
}

// The viewer runs with requestRenderMode: true, so Cesium only draws when
// something asks it to. A CallbackProperty changing value is not an ask -- it is
// merely read during a draw that happens for some other reason. Every layer that
// used to keep the loop busy (flights, weather, fires) is currently held, which
// left the only heartbeat the 500ms occlusion tick: a 2.6-4.5s sine sampled at
// 2fps, which steps rather than breathes.
//
// So the pulse drives its own frames, and only while something is actually
// pulsing. 30fps is indistinguishable from 60 for a sine this slow and costs
// half as much.
const PUMP_INTERVAL_MS = 1000 / 30

function pumpFrame(controller) {
  const store = controller._ambient
  if (!store) return
  if (store.entries.size === 0) {
    store.raf = null
    return
  }

  const now = performance.now()
  if (now - store.lastPump >= PUMP_INTERVAL_MS) {
    store.lastPump = now
    controller.viewer?.scene?.requestRender()
  }
  store.raf = requestAnimationFrame(() => pumpFrame(controller))
}

function startPump(controller) {
  const store = state(controller)
  if (store.raf || store.entries.size === 0) return
  store.raf = requestAnimationFrame(() => pumpFrame(controller))
}

function stopPump(controller) {
  const store = controller._ambient
  if (!store?.raf) return
  cancelAnimationFrame(store.raf)
  store.raf = null
}

// Deterministic 0..1 from any string. Used for phase and period so that two
// points registered in the same frame do not pulse in lockstep, and so a point
// keeps its rhythm across re-renders instead of jumping.
export function ambientHash01(value) {
  const text = String(value ?? "")
  let hash = 2166136261
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i)
    hash = Math.imul(hash, 16777619)
  }
  return ((hash >>> 0) % 100000) / 100000
}

function currentBounds(controller) {
  const store = state(controller)
  if (store.boundsStale) {
    store.bounds = getViewportBounds(controller.viewer)
    store.boundsStale = false
  }
  return store.bounds
}

function inView(bounds, lat, lng) {
  if (!bounds) return true
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false
  if (lat < bounds.lamin || lat > bounds.lamax) return false
  // A viewport straddling the antimeridian comes back with lomin > lomax.
  if (bounds.lomin > bounds.lomax) return lng >= bounds.lomin || lng <= bounds.lomax
  return lng >= bounds.lomin && lng <= bounds.lomax
}

function pulse01(controller, key) {
  const entry = state(controller).entries.get(key)
  if (!entry) return 0.5
  const seconds = performance.now() / 1000
  const wave = Math.sin(((seconds / entry.period) + entry.phase) * Math.PI * 2)
  return (wave + 1) / 2
}

// -1..1 around the resting value, so callers can swing a property symmetrically.
function signed(controller, key) {
  return (pulse01(controller, key) - 0.5) * 2
}

function forgetKeys(store, keys) {
  if (!keys) return
  for (const key of keys) store.entries.delete(key)
}

// ── Layer lifecycle ──────────────────────────────────────

export function beginAmbientLayer(controller, layer) {
  state(controller).staging.set(layer, new Set())
}

// Returns a key to animate against, or null when this point should stay static
// because it is off screen or the layer is already at its animation budget.
export function registerAmbient(controller, layer, id, { lat, lng, weight } = {}) {
  const store = state(controller)
  const staged = store.staging.get(layer)
  if (!staged) return null
  if (staged.size >= MAX_ANIMATED_PER_LAYER) return null
  if (!inView(currentBounds(controller), lat, lng)) return null

  const key = `${layer}:${id}`
  const seed = ambientHash01(key)
  store.entries.set(key, {
    phase: seed,
    period: MIN_PERIOD + (ambientHash01(`${key}#period`) * PERIOD_SPREAD),
    weight: Number.isFinite(weight) ? weight : 0,
  })
  staged.add(key)
  return key
}

export function commitAmbientLayer(controller, layer) {
  const store = state(controller)
  const staged = store.staging.get(layer)
  if (!staged) return

  const previous = store.layers.get(layer)
  if (previous) {
    for (const key of previous) {
      if (!staged.has(key)) store.entries.delete(key)
    }
  }
  store.layers.set(layer, staged)
  store.staging.delete(layer)
  startPump(controller)
}

export function clearAmbientLayer(controller, layer) {
  const store = controller._ambient
  if (!store) return
  forgetKeys(store, store.layers.get(layer))
  forgetKeys(store, store.staging.get(layer))
  store.layers.delete(layer)
  store.staging.delete(layer)
  if (store.entries.size === 0) stopPump(controller)
}

export function clearAllAmbient(controller) {
  const store = controller._ambient
  if (!store) return
  stopPump(controller)
  store.entries.clear()
  store.layers.clear()
  store.staging.clear()
}

export function destroyAmbient(controller) {
  clearAllAmbient(controller)
  controller._ambient = null
}

// A new viewport means a different set of points is worth animating, so the
// cached bounds are dropped and recomputed on the next registration pass.
export function onAmbientCameraChange(controller) {
  const store = controller._ambient
  if (!store) return
  store.boundsStale = true
}

// ── Weight thresholds ────────────────────────────────────

// The weight at or above which a point earns a halo. Returns Infinity when
// there is nothing to rank, which reads as "no halos" at every call site.
export function haloWeightCutoff(weights) {
  const ranked = (weights || []).filter(Number.isFinite).sort((a, b) => b - a)
  if (ranked.length === 0) return Infinity

  const index = Math.max(0, Math.floor(ranked.length * HALO_SHARE) - 1)
  return ranked[Math.min(index, ranked.length - 1)]
}

// ── Animated properties ──────────────────────────────────

// amplitude is a fraction of the base size, so 0.16 breathes by ±16%.
export function ambientPointSize(controller, key, base, amplitude) {
  return new (C().CallbackProperty)(() => base * (1 + (amplitude * signed(controller, key))), false)
}

// amplitude is a fraction of baseAlpha; the colour itself is left alone.
//
// `opacity` is an optional function returning a 0..1 multiplier read on every
// frame. It exists so a layer can be dimmed as a whole without replacing these
// callbacks -- assigning a plain Color over one would freeze the pulse, which
// is exactly why _setNewsDotOpacity skips CallbackProperty colours.
export function ambientColor(controller, key, color, baseAlpha, amplitude, opacity) {
  return new (C().CallbackProperty)(() => {
    const dim = typeof opacity === "function" ? opacity() : 1
    const alpha = baseAlpha * (1 + (amplitude * signed(controller, key))) * (Number.isFinite(dim) ? dim : 1)
    return color.withAlpha(Math.min(1, Math.max(0, alpha)))
  }, false)
}

// amplitude is in pixels here rather than a fraction, because an outline that
// scales proportionally disappears on the small points and screams on the big ones.
export function ambientOutlineWidth(controller, key, base, amplitude) {
  return new (C().CallbackProperty)(() => base + (amplitude * pulse01(controller, key)), false)
}

// An expanding, fading ring behind a point. Returns a point graphics config to
// hand straight to entities.add({ point: ... }), or null if the key is unknown.
export function ambientHaloPoint(controller, key, color, { minSize = 8, maxSize = 36, peakAlpha = 0.3, opacity } = {}) {
  if (!controller._ambient?.entries.has(key)) return null

  return {
    pixelSize: new (C().CallbackProperty)(() => {
      const progress = pulse01(controller, key)
      return minSize + ((maxSize - minSize) * progress)
    }, false),
    color: new (C().CallbackProperty)(() => {
      // Fades as it grows, so the ring reads as a ping rather than a blob.
      // `opacity` has to be honoured here too: without it a dimmed layer keeps
      // full-strength halos around quarter-strength dots, and the bloom ends up
      // brighter than the thing it is supposed to be blooming around.
      const progress = pulse01(controller, key)
      const dim = typeof opacity === "function" ? opacity() : 1
      return color.withAlpha(peakAlpha * (1 - progress) * (Number.isFinite(dim) ? dim : 1))
    }, false),
    outlineWidth: 0,
    disableDepthTestDistance: Number.POSITIVE_INFINITY,
  }
}
