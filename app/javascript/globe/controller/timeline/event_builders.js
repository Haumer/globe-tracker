import {
  CONFLICT_TIMELINE_WINDOW_MS,
  EVENT_ARRIVAL_PULSE_BUCKET_MS,
  EVENT_RENDER_BUCKET_MS,
  EVENT_TIMELINE_WINDOWS_MS,
  STRIKE_TIMELINE_WINDOW_MS,
} from "globe/controller/timeline/constants"
import {
  collapseTimelineGpsJammingEvents,
  filterVisibleTimelineEvents,
  groupTimelineEventsByType,
  timelineAppearProgress,
  timelineStrikeWindowContains,
  timelineWindowAlpha,
} from "globe/controller/timeline/event_utils"
import { attachArrivalPulses } from "globe/controller/timeline/pulse"

export function buildTimelineRenderKey(controller, cursorMs) {
  const renderBucket = Math.floor(cursorMs / EVENT_RENDER_BUCKET_MS)
  const arrivalPulseBucket = controller._timelinePulseAnimationActive
    ? Math.floor(performance.now() / EVENT_ARRIVAL_PULSE_BUCKET_MS)
    : 0

  return [
    renderBucket,
    arrivalPulseBucket,
    controller.newsVisible ? 1 : 0,
    controller.earthquakesVisible ? 1 : 0,
    controller.naturalEventsVisible ? 1 : 0,
    controller.gpsJammingVisible ? 1 : 0,
    controller.outagesVisible ? 1 : 0,
    controller.weatherVisible ? 1 : 0,
    controller.notamsVisible ? 1 : 0,
    controller.conflictsVisible ? 1 : 0,
    controller.fireHotspotsVisible ? 1 : 0,
    controller._heatSignaturesLayerVisible ? (controller._heatSignaturesLayerVisible() ? 1 : 0) : (controller.heatSignaturesVisible ? 1 : 0),
    controller._verifiedStrikesLayerVisible ? (controller._verifiedStrikesLayerVisible() ? 1 : 0) : (controller.verifiedStrikesVisible ? 1 : 0),
  ].join("|")
}

export function groupPlaybackEvents(events) {
  return groupTimelineEventsByType(events)
}

export function buildEarthquakeTimelineData(controller, events, cursorMs) {
  return buildPulsedMappedEvents(controller, "earthquake", events, cursorMs, EVENT_TIMELINE_WINDOWS_MS.earthquake, (event) => ({
    id: event.id,
    title: event.title,
    mag: event.mag,
    magType: event.magType,
    lat: event.lat,
    lng: event.lng,
    depth: event.depth,
    url: event.url,
    time: event.time ? new Date(event.time).getTime() : null,
    timelineAlpha: timelineWindowAlpha(event.time, cursorMs, EVENT_TIMELINE_WINDOWS_MS.earthquake),
  }))
}

export function buildNaturalEventTimelineData(controller, events, cursorMs) {
  return buildPulsedMappedEvents(controller, "natural_event", events, cursorMs, EVENT_TIMELINE_WINDOWS_MS.natural_event, (event) => ({
    id: event.id,
    title: event.title,
    categoryId: event.categoryId,
    categoryTitle: event.categoryTitle,
    lat: event.lat,
    lng: event.lng,
    date: event.time,
    magnitudeValue: event.magnitudeValue,
    timelineAlpha: timelineWindowAlpha(event.time, cursorMs, EVENT_TIMELINE_WINDOWS_MS.natural_event),
  }))
}

export function buildNewsTimelineData(controller, events, cursorMs) {
  return buildPulsedMappedEvents(controller, "news", events, cursorMs, EVENT_TIMELINE_WINDOWS_MS.news, (event) => ({
    id: event.id,
    lat: event.lat,
    lng: event.lng,
    title: event.title,
    name: event.name,
    url: event.url,
    tone: event.tone,
    level: event.level,
    category: event.category,
    themes: event.themes || [],
    source: event.source,
    threat: event.threat,
    cluster_id: event.cluster_id,
    time: event.time,
    timelineAlpha: timelineWindowAlpha(event.time, cursorMs, EVENT_TIMELINE_WINDOWS_MS.news),
    timelineAppear: timelineAppearProgress(event.time, cursorMs),
  }))
}

export function buildGpsJammingTimelineData(controller, events, cursorMs, cursor) {
  const mappedEvents = buildMappedVisibleEvents(events, cursorMs, EVENT_TIMELINE_WINDOWS_MS.gps_jamming, (event) => ({
    lat: event.lat,
    lng: event.lng,
    total: event.total,
    bad: event.bad,
    pct: event.pct,
    level: event.level,
    time: event.time,
    timelineAlpha: timelineWindowAlpha(event.time, cursorMs, EVENT_TIMELINE_WINDOWS_MS.gps_jamming),
  }))

  return attachArrivalPulses(controller, "gps_jamming", collapseTimelineGpsJammingEvents(mappedEvents, cursor))
}

export function buildOutageTimelineRenderData(controller, events, cursorMs) {
  const outageEvents = buildPulsedMappedEvents(controller, "internet_outage", events, cursorMs, EVENT_TIMELINE_WINDOWS_MS.internet_outage, (event) => ({
    id: event.id,
    code: event.code,
    name: event.name,
    score: event.score,
    level: event.level,
    time: event.time,
    timelineAlpha: timelineWindowAlpha(event.time, cursorMs, EVENT_TIMELINE_WINDOWS_MS.internet_outage),
  }))

  const summary = controller._deriveOutageSummary ? controller._deriveOutageSummary(outageEvents) : outageEvents
  return { summary, events: outageEvents }
}

export function buildWeatherAlertTimelineData(events, cursorMs) {
  return buildMappedVisibleEvents(events, cursorMs, EVENT_TIMELINE_WINDOWS_MS.weather_alert, (event) => ({
    event: event.event,
    severity: event.severity,
    urgency: event.urgency,
    certainty: event.certainty,
    headline: event.headline,
    description: event.description,
    areas: event.areas,
    onset: event.onset,
    expires: event.expires,
    sender: event.sender,
    lat: event.lat,
    lng: event.lng,
    timelineAlpha: timelineWindowAlpha(event.time, cursorMs, EVENT_TIMELINE_WINDOWS_MS.weather_alert),
  }))
}

export function buildNotamTimelineData(events, cursorMs) {
  return buildMappedVisibleEvents(events, cursorMs, EVENT_TIMELINE_WINDOWS_MS.notam, (event) => ({
    id: event.id,
    lat: event.lat,
    lng: event.lng,
    radius_nm: event.radius_nm,
    radius_m: event.radius_m,
    alt_low_ft: event.alt_low_ft,
    alt_high_ft: event.alt_high_ft,
    reason: event.reason,
    text: event.text,
    effective_start: event.effective_start,
    effective_end: event.effective_end,
    timelineAlpha: timelineWindowAlpha(event.time, cursorMs, EVENT_TIMELINE_WINDOWS_MS.notam),
  }))
}

export function buildStrikeTimelineState(controller, strikeEvents, cursorMs, { showHeatSignatures, showVerifiedStrikes }) {
  const oldestStrikeMs = cursorMs - STRIKE_TIMELINE_WINDOW_MS

  return {
    strikeDetections: showHeatSignatures
      ? attachArrivalPulses(controller, "fire", strikeEvents
        .filter((event) => event?.type === "fire")
        .filter((event) => timelineStrikeWindowContains(event, oldestStrikeMs, cursorMs))
        .map((event) => timelineFireToStrikeDetection(event)))
      : [],
    gcDetections: showVerifiedStrikes
      ? attachArrivalPulses(controller, "geoconfirmed", strikeEvents
        .filter((event) => event?.type === "geoconfirmed")
        .filter((event) => timelineStrikeWindowContains(event, oldestStrikeMs, cursorMs))
        .map((event) => timelineGeoconfirmedToDetection(event)))
      : [],
  }
}

export function buildFireHotspotTimelineData(controller, strikeEvents, cursorMs) {
  const oldestFireMs = cursorMs - STRIKE_TIMELINE_WINDOW_MS
  const hotspotData = strikeEvents
    .filter((event) => event?.type === "fire")
    .filter((event) => timelineStrikeWindowContains(event, oldestFireMs, cursorMs))
    .map((event) => ({
      id: event.external_id || event.id,
      lat: event.lat,
      lng: event.lng,
      brightness: event.brightness,
      confidence: event.confidence,
      satellite: event.satellite,
      instrument: event.instrument,
      frp: event.frp,
      daynight: event.daynight,
      time: event.time,
      strike: false,
      timelineAlpha: timelineWindowAlpha(event.time, cursorMs, STRIKE_TIMELINE_WINDOW_MS),
    }))

  return attachArrivalPulses(controller, "fire_hotspot", hotspotData)
}

export function buildConflictTimelineData(controller, conflictEvents, cursorMs) {
  const visibleEvents = filterVisibleTimelineEvents(conflictEvents, cursorMs, CONFLICT_TIMELINE_WINDOW_MS)
    .map((event) => ({
      ...event,
      timelineAlpha: timelineWindowAlpha(event.time || event.date_start, cursorMs, CONFLICT_TIMELINE_WINDOW_MS),
    }))
  return attachArrivalPulses(controller, "conflicts", visibleEvents)
}

function buildMappedVisibleEvents(events, cursorMs, windowMs, mapper) {
  return filterVisibleTimelineEvents(events, cursorMs, windowMs).map(mapper)
}

function buildPulsedMappedEvents(controller, layerKey, events, cursorMs, windowMs, mapper) {
  return attachArrivalPulses(controller, layerKey, buildMappedVisibleEvents(events, cursorMs, windowMs, mapper))
}

function timelineFireToStrikeDetection(event) {
  return {
    id: event.external_id || `timeline-fire-${event.id}`,
    lat: event.lat,
    lng: event.lng,
    brightness: event.brightness,
    confidence: event.confidence,
    satellite: event.satellite,
    instrument: event.instrument,
    frp: event.frp,
    daynight: event.daynight,
    time: event.time,
    strikeConfidence: null,
    clusterSize: 0,
    gcMatch: null,
    detectionKind: "heat_signature",
    timelineAlpha: event.timelineAlpha,
  }
}

function timelineGeoconfirmedToDetection(event) {
  return {
    id: event.external_id || `timeline-gc-${event.id}`,
    lat: event.lat,
    lng: event.lng,
    title: event.title,
    region: event.region,
    time: event.time,
    sourceUrls: event.sourceUrls || [],
    description: event.description,
    geoUrls: event.geoUrls || [],
    detectionKind: "verified_strike",
    timelineAlpha: event.timelineAlpha,
  }
}
