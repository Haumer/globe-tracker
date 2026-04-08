import { EVENT_ARRIVAL_PULSE_MS } from "globe/controller/timeline/constants"

export function attachArrivalPulses(controller, layerKey, events) {
  if (!Array.isArray(events) || events.length === 0) {
    clearArrivalPulseLayer(controller, layerKey)
    return []
  }

  if (!controller._timelinePulseStarts) controller._timelinePulseStarts = new Map()

  const now = performance.now()
  const nextKeys = new Set()
  let hasActivePulse = false

  const pulsed = events.map((event) => {
    const pulseKey = stableArrivalPulseKey(layerKey, event)
    nextKeys.add(pulseKey)

    if (!controller._timelinePulseStarts.has(pulseKey)) {
      controller._timelinePulseStarts.set(pulseKey, now)
    }

    const pulse = arrivalPulseFactor(controller._timelinePulseStarts.get(pulseKey), now)
    if (pulse > 0.02) hasActivePulse = true

    return {
      ...event,
      timelinePulse: pulse,
    }
  })

  for (const key of Array.from(controller._timelinePulseStarts.keys())) {
    if (!key.startsWith(`${layerKey}:`)) continue
    if (nextKeys.has(key)) continue
    controller._timelinePulseStarts.delete(key)
  }

  controller._timelinePulseAnimationActive ||= hasActivePulse
  return pulsed
}

export function clearArrivalPulseLayer(controller, layerKey) {
  if (!controller._timelinePulseStarts) return
  for (const key of Array.from(controller._timelinePulseStarts.keys())) {
    if (key.startsWith(`${layerKey}:`)) controller._timelinePulseStarts.delete(key)
  }
}

function stableArrivalPulseKey(layerKey, event) {
  const id = event?.id ?? event?.external_id ?? event?.code ?? ""
  const time = event?.time || event?.date_start || event?.effective_start || ""
  const lat = Number.isFinite(event?.lat) ? event.lat.toFixed(4) : ""
  const lng = Number.isFinite(event?.lng) ? event.lng.toFixed(4) : ""
  const title = event?.title || event?.name || event?.region || ""
  return `${layerKey}:${id}|${time}|${lat}|${lng}|${title}`
}

function arrivalPulseFactor(startMs, nowMs) {
  if (!Number.isFinite(startMs) || !Number.isFinite(nowMs)) return 0
  const ageMs = nowMs - startMs
  if (ageMs < 0 || ageMs > EVENT_ARRIVAL_PULSE_MS) return 0
  return 1 - (ageMs / EVENT_ARRIVAL_PULSE_MS)
}
