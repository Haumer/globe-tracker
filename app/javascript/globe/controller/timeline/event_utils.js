import { EVENT_APPEAR_WINDOW_MS } from "globe/controller/timeline/constants"

export function groupTimelineEventsByType(events) {
  return events.reduce((groups, event) => {
    if (!groups[event.type]) groups[event.type] = []
    groups[event.type].push(event)
    return groups
  }, {})
}

export function collapseTimelineGpsJammingEvents(events, cursor) {
  const cursorMs = cursor instanceof Date ? cursor.getTime() : Date.now()
  const byCell = new Map()

  events.forEach((event) => {
    const key = `${event.lat},${event.lng}`
    const current = byCell.get(key)
    const eventDistance = gpsJammingCursorDistance(event, cursorMs)

    if (!current || eventDistance < gpsJammingCursorDistance(current, cursorMs)) {
      byCell.set(key, event)
      return
    }

    if (eventDistance === gpsJammingCursorDistance(current, cursorMs) &&
      gpsJammingEventTime(event) > gpsJammingEventTime(current)) {
      byCell.set(key, event)
    }
  })

  return [...byCell.values()]
}

export function timelineStrikeWindowContains(event, fromMs, toMs) {
  const eventMs = event?.time ? new Date(event.time).getTime() : Number.NaN
  return Number.isFinite(eventMs) && eventMs >= fromMs && eventMs <= toMs
}

export function timelineWindowAlpha(eventTime, cursorOrMs, windowMs) {
  const eventMs = eventTime ? new Date(eventTime).getTime() : Number.NaN
  const cursorMs = cursorOrMs instanceof Date ? cursorOrMs.getTime() : Number(cursorOrMs)
  if (!Number.isFinite(eventMs) || !Number.isFinite(cursorMs) || !(windowMs > 0)) return 1
  if (eventMs > cursorMs) return 0

  const ageMs = Math.max(cursorMs - eventMs, 0)
  const progress = Math.min(ageMs / windowMs, 1)
  const fadeOut = 0.18 + (1 - progress) * 0.82
  const fadeIn = 0.28 + timelineAppearProgress(eventTime, cursorMs) * 0.72
  return Math.min(1, fadeOut * fadeIn)
}

export function timelineAppearProgress(eventTime, cursorOrMs) {
  const eventMs = eventTime ? new Date(eventTime).getTime() : Number.NaN
  const cursorMs = cursorOrMs instanceof Date ? cursorOrMs.getTime() : Number(cursorOrMs)
  if (!Number.isFinite(eventMs) || !Number.isFinite(cursorMs)) return 1

  const ageMs = cursorMs - eventMs
  if (ageMs <= 0) return 0
  return Math.min(ageMs / EVENT_APPEAR_WINDOW_MS, 1)
}

export function filterVisibleTimelineEvents(events, cursorMs, windowMs) {
  return events.filter((event) => {
    const eventMs = timelineEventTimeMs(event)
    if (!Number.isFinite(eventMs)) return true
    return eventMs <= cursorMs && cursorMs - eventMs <= windowMs
  })
}

export function timelineEventTimeMs(event) {
  const time = event?.time || event?.date_start || event?.effective_start || null
  const eventMs = time ? new Date(time).getTime() : Number.NaN
  return Number.isFinite(eventMs) ? eventMs : Number.NaN
}

function gpsJammingCursorDistance(event, cursorMs) {
  const eventMs = gpsJammingEventTime(event)
  return Number.isFinite(eventMs) ? Math.abs(eventMs - cursorMs) : Number.POSITIVE_INFINITY
}

function gpsJammingEventTime(event) {
  const eventMs = event?.time ? new Date(event.time).getTime() : Number.NaN
  return Number.isFinite(eventMs) ? eventMs : Number.NEGATIVE_INFINITY
}
