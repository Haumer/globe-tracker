export async function fetchTimelineEventSet({ from, to, types, bounds }) {
  if (!types.length) return []

  let url = `/api/playback/events?from=${from}&to=${to}&types=${types.join(",")}`
  if (bounds) {
    url += `&lamin=${bounds.lamin}&lamax=${bounds.lamax}&lomin=${bounds.lomin}&lomax=${bounds.lomax}`
  }

  const response = await fetch(url)
  if (!response.ok) throw new Error(`Timeline events request failed with ${response.status}`)
  const events = await response.json()
  return Array.isArray(events) ? events : []
}

export async function fetchTimelineConflictSet({ from, to, bounds }) {
  const params = new URLSearchParams({ from, to })
  if (bounds) {
    params.set("lamin", bounds.lamin)
    params.set("lamax", bounds.lamax)
    params.set("lomin", bounds.lomin)
    params.set("lomax", bounds.lomax)
  }

  const response = await fetch(`/api/conflict_events?${params.toString()}`)
  if (!response.ok) throw new Error(`Timeline conflict request failed with ${response.status}`)
  const events = await response.json()
  return Array.isArray(events) ? events.map(normalizeConflictEvent) : []
}

export function buildTimelineEventFetchKey(rangeStart, rangeEnd, request, bounds) {
  return JSON.stringify({
    from: rangeStart?.toISOString?.(),
    to: rangeEnd?.toISOString?.(),
    bounds: bounds ? `${bounds.lamin},${bounds.lamax},${bounds.lomin},${bounds.lomax}` : "global",
    general: request.generalTypes.slice().sort(),
    strikes: request.strikeTypes.slice().sort(),
    conflicts: request.wantsConflictEvents ? 1 : 0,
  })
}

function normalizeConflictEvent(event) {
  return {
    ...event,
    time: event?.time || event?.date_start || event?.date_end || null,
    lat: event?.lat,
    lng: event?.lng,
  }
}
