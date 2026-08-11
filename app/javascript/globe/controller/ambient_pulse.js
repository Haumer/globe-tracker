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

// How long a newly arrived mark announces itself for, and the window its start
// is spread across so a refresh does not light the whole map at one instant.
const ARRIVAL_MS = 3000
const ARRIVAL_STAGGER_MS = 1400

// A refresh that brings in two hundred clusters should not ping two hundred
// times. Ranked by weight, so the cap keeps the ones worth announcing.
const MAX_ARRIVALS_PER_COMMIT = 40

function state(controller) {
  if (!controller._ambient) {
    controller._ambient = {
      entries: new Map(),
      layers: new Map(),
      // The key set as of the last commit, kept apart from `layers` because a
      // re-render clears that before it rebuilds. Without somewhere the clear
      // does not reach, every commit looks like the layer's first and nothing
      // is ever new.
      previous: new Map(),
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
  // Stops as soon as the last arrival finishes. This used to run for as long as
  // any entry existed at all -- which, with the old endless sine, meant forever:
  // requestRenderMode was on but the scene never once got to idle.
  if (store.entries.size === 0 || !anyArrivalRunning(store)) {
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
  if (!anyArrivalRunning(store)) return
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

// 0 at rest, rising to 1 and back to 0 across ARRIVAL_MS after a mark arrives.
//
// The attack is deliberately faster than the decay -- pow(u, 0.32) front-loads
// the curve, so the mark snaps into notice and then lets go. It lands exactly on
// zero at the end, so the pin hands over to its static self without a step.
export function arrival01(controller, key) {
  const u = arrivalPhase(controller, key)
  if (u === null) return 0
  return Math.sin(Math.PI * Math.pow(u, 0.32))
}

// Raw 0..1 progress through the arrival window, or null when the mark is at
// rest. The halo wants this rather than the bump, because a ring has to expand
// in one direction rather than swell and come back.
function arrivalPhase(controller, key) {
  const entry = controller._ambient?.entries.get(key)
  if (!entry?.arriveAt) return null
  const u = (performance.now() - entry.arriveAt) / ARRIVAL_MS
  if (u <= 0 || u >= 1) return null
  return u
}

function anyArrivalRunning(store) {
  const now = performance.now()
  for (const entry of store.entries.values()) {
    if (entry.arriveAt && now < entry.arriveAt + ARRIVAL_MS) return true
  }
  return false
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

  const current = store.layers.get(layer)
  if (current) {
    for (const key of current) {
      if (!staged.has(key)) store.entries.delete(key)
    }
  }
  markArrivals(store, staged, store.previous.get(layer))
  store.layers.set(layer, staged)
  store.previous.set(layer, new Set(staged))
  store.staging.delete(layer)
  startPump(controller)
}

// The other direction of the same set difference the loop above uses to expire
// departed keys: staged minus previous is everything that just showed up.
//
// This is what a ping is supposed to mean. Every point used to breathe on an
// endless sine, so the map pinged continuously whether or not anything had
// happened -- which makes the ping worth nothing. Now a mark announces itself
// once, when it arrives, and is then still.
//
// `previous` being undefined means this is the layer's first commit, and every
// key is technically new. Treating that as arrivals would flash the entire map
// on load, which is exactly what the jitter exists to avoid, so it counts as
// nothing arriving.
//
// One thing to keep in mind if news ever re-renders on camera idle: keys are
// only staged for points in view, so panning somewhere new would make every
// key there an arrival and the pinging would be back in a different costume.
// That case wants comparing against every key seen recently, not the last
// commit.
function markArrivals(store, staged, previous) {
  if (!previous) return

  const arrivals = []
  for (const key of staged) {
    if (previous.has(key)) continue
    const entry = store.entries.get(key)
    if (entry) arrivals.push({ key, entry })
  }
  if (arrivals.length === 0) return

  // A refresh that replaces most of the map should not become a light show.
  // Heaviest first, so if the cap bites it keeps the arrivals worth seeing.
  arrivals.sort((a, b) => b.entry.weight - a.entry.weight)

  const now = performance.now()
  for (let i = 0; i < arrivals.length && i < MAX_ARRIVALS_PER_COMMIT; i++) {
    const { key, entry } = arrivals[i]
    // Deterministic per key, so the stagger is spread rather than random and a
    // given cluster starts at the same offset every time.
    entry.arriveAt = now + (ambientHash01(`${key}#arrive`) * ARRIVAL_STAGGER_MS)
  }
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
  // Unlike clearAmbientLayer, this is a hard reset -- switching into timeline
  // playback and back should start over rather than treat everything that
  // returns as newly arrived.
  store.previous.clear()
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
//
// Every one of these is at its resting value except during the three seconds
// after its mark arrives. They used to run an endless sine, which is why the
// map pinged continuously and the render pump never got to stop.

// amplitude is a fraction of the base size: 0.16 swells by 16% on arrival.
export function ambientPointSize(controller, key, base, amplitude) {
  return new (C().CallbackProperty)(
    () => base * (1 + (amplitude * 1.6 * arrival01(controller, key))),
    false,
  )
}

// amplitude is a fraction of baseAlpha; the colour itself is left alone.
//
// `opacity` is an optional function returning a 0..1 multiplier read on every
// frame. It exists so a layer can be dimmed as a whole without replacing these
// callbacks -- assigning a plain Color over one would freeze the property, which
// is exactly why _setNewsDotOpacity skips CallbackProperty colours.
export function ambientColor(controller, key, color, baseAlpha, amplitude, opacity) {
  return new (C().CallbackProperty)(() => {
    const dim = typeof opacity === "function" ? opacity() : 1
    const alpha = baseAlpha * (1 + (amplitude * arrival01(controller, key))) * (Number.isFinite(dim) ? dim : 1)
    return color.withAlpha(Math.min(1, Math.max(0, alpha)))
  }, false)
}

// amplitude is in pixels here rather than a fraction, because an outline that
// scales proportionally disappears on the small points and screams on the big ones.
export function ambientOutlineWidth(controller, key, base, amplitude) {
  return new (C().CallbackProperty)(
    () => base + (amplitude * arrival01(controller, key)),
    false,
  )
}

// The ping: a ring that expands out of the mark and fades as it goes, once,
// when the mark arrives.
//
// At rest its size is zero. That matters for more than looks -- a transparent
// ring tens of pixels across is still pickable, and an invisible click target
// sitting over the neighbouring pins is exactly the bug the pick preference
// pass had to be written to survive. Nothing is drawn, so nothing is hit.
export function ambientHaloPoint(controller, key, color, { minSize = 8, maxSize = 36, peakAlpha = 0.3, opacity } = {}) {
  if (!controller._ambient?.entries.has(key)) return null

  return {
    pixelSize: new (C().CallbackProperty)(() => {
      const progress = arrivalPhase(controller, key)
      if (progress === null) return 0
      return minSize + ((maxSize - minSize) * progress)
    }, false),
    color: new (C().CallbackProperty)(() => {
      // `opacity` has to be honoured here too: without it a dimmed layer keeps
      // full-strength halos around quarter-strength marks, and the bloom ends up
      // brighter than the thing it is supposed to be blooming around.
      const progress = arrivalPhase(controller, key)
      if (progress === null) return color.withAlpha(0)
      const dim = typeof opacity === "function" ? opacity() : 1
      return color.withAlpha(peakAlpha * (1 - progress) * (Number.isFinite(dim) ? dim : 1))
    }, false),
    outlineWidth: 0,
    disableDepthTestDistance: Number.POSITIVE_INFINITY,
  }
}
