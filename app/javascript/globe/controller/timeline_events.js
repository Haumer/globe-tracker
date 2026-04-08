import { getDataSource } from "globe/utils"

const EVENT_TIMELINE_WINDOWS_MS = {
  earthquake: 24 * 60 * 60 * 1000,
  natural_event: 24 * 60 * 60 * 1000,
  news: 24 * 60 * 60 * 1000,
  gps_jamming: 60 * 60 * 1000,
  internet_outage: 24 * 60 * 60 * 1000,
  weather_alert: 48 * 60 * 60 * 1000,
  notam: 48 * 60 * 60 * 1000,
}
const STRIKE_TIMELINE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000
const EVENT_APPEAR_WINDOW_MS = 12 * 60 * 1000
const EVENT_PULSE_WINDOW_MS = 6 * 60 * 1000
const GENERAL_EVENT_FETCH_BUCKET_MS = 5 * 60 * 1000
const STRIKE_EVENT_FETCH_BUCKET_MS = 15 * 60 * 1000

export function applyTimelineEventMethods(GlobeController) {
  GlobeController.prototype._timelineRenderCachedState = function() {
    if (!this._timelineActive) return
    const cursorMs = this._timelineCursor?.getTime?.()
    if (!Number.isFinite(cursorMs) || cursorMs === this._timelineLastRenderedCursorMs) return
    this._timelineLastRenderedCursorMs = cursorMs
    this._renderUnifiedTimelineEvents(this._timelineFetchedGeneralEvents || [], this._timelineFetchedStrikeEvents || [])
  }

  GlobeController.prototype._timelineUpdateEvents = async function() {
    if (!this._timelineActive) return

    const cursor = this._timelineCursor
    const showHeatSignatures = this._heatSignaturesLayerVisible ? this._heatSignaturesLayerVisible() : !!(this.heatSignaturesVisible || this.strikesVisible)
    const showVerifiedStrikes = this._verifiedStrikesLayerVisible ? this._verifiedStrikesLayerVisible() : !!(this.verifiedStrikesVisible || this.strikesVisible)
    const generalTypes = []
    if (this.earthquakesVisible) generalTypes.push("earthquake")
    if (this.naturalEventsVisible) generalTypes.push("natural_event")
    if (this.newsVisible) generalTypes.push("news")
    if (this.gpsJammingVisible) generalTypes.push("gps_jamming")
    if (this.outagesVisible) generalTypes.push("internet_outage")
    if (this.weatherVisible) generalTypes.push("weather_alert")
    if (this.notamsVisible) generalTypes.push("notam")

    const strikeTypes = []
    if (showHeatSignatures) strikeTypes.push("fire")
    if (showVerifiedStrikes) strikeTypes.push("geoconfirmed")

    if (generalTypes.length === 0 && strikeTypes.length === 0) {
      this._timelineEventCount = 0
      getDataSource(this.viewer, this._ds, "timelineEvents").entities.removeAll()
      this._strikeDetections = []
      this._gcDetections = []
      this._clearStrikeEntities?.()
      return 0
    }

    // Playback events should be global by default. Only spatially scope them when the
    // analyst explicitly applies a country/area filter.
    const bounds = this.hasActiveFilter() ? this.getFilterBounds() : null
    const groupedTypes = groupTimelineTypesByWindow(generalTypes)
    const requestKey = buildTimelineEventFetchKey(cursor, groupedTypes, strikeTypes, bounds)

    try {
      if (requestKey === this._timelineEventFetchKey) {
        this._timelineEventCount = (this._timelineFetchedGeneralEvents?.length || 0) + (this._timelineFetchedStrikeEvents?.length || 0)
        this._timelineRenderCachedState()
        this._updateStats()
        return this._timelineEventCount
      }

      const generalPromise = groupedTypes.length > 0
        ? Promise.all(groupedTypes.map(({ windowMs, types }) => {
            const bucketEnd = timelineFetchBucketEnd(cursor.getTime(), GENERAL_EVENT_FETCH_BUCKET_MS)
            return fetchTimelineEventSet({
              from: new Date(bucketEnd - windowMs).toISOString(),
              to: new Date(bucketEnd).toISOString(),
              types,
              bounds,
            })
          })).then((groups) => groups.flat())
        : Promise.resolve([])
      const strikePromise = strikeTypes.length > 0
        ? (() => {
            const bucketEnd = timelineFetchBucketEnd(cursor.getTime(), STRIKE_EVENT_FETCH_BUCKET_MS)
            return fetchTimelineEventSet({
              from: new Date(bucketEnd - STRIKE_TIMELINE_WINDOW_MS).toISOString(),
              to: new Date(bucketEnd).toISOString(),
              types: strikeTypes,
              bounds,
            })
          })()
        : Promise.resolve([])

      const [events, strikeEvents] = await Promise.all([generalPromise, strikePromise])
      this._timelineEventFetchKey = requestKey
      this._timelineFetchedGeneralEvents = Array.isArray(events) ? events : []
      this._timelineFetchedStrikeEvents = Array.isArray(strikeEvents) ? strikeEvents : []
      this._timelineEventCount = this._timelineFetchedGeneralEvents.length + this._timelineFetchedStrikeEvents.length
      this._timelineRenderCachedState()
      this._updateStats()
      return this._timelineEventCount
    } catch (error) {
      console.error("Timeline events error:", error)
      this._timelineEventCount = 0
      return 0
    }
  }

  GlobeController.prototype._timelineUpdateConflictPulse = async function() {
    if (!this._timelineActive || !this._timelineCursor) return 0
    if (!this.situationsVisible) {
      this._timelineSituationCount = 0
      this._clearConflictPulseEntities?.()
      return 0
    }

    const cursorMs = this._timelineCursor.getTime()
    const bucket = cursorMs - (cursorMs % 3600000)
    if (bucket === this._lastConflictPulseBucket) return
    this._lastConflictPulseBucket = bucket

    const at = new Date(bucket).toISOString()
    try {
      const response = await fetch(`/api/playback/conflicts?at=${at}`)
      if (!response.ok) return
      const data = await response.json()

      this._conflictPulseData = data.zones || []
      this._conflictPulseZones = data.zones || []
      this._strikeArcData = data.strike_arcs || []
      this._hexCellData = data.hex_cells || []
      this._timelineSituationCount = this._conflictPulseZones.length
      this._renderConflictPulse?.()
      this._renderSituationPanel?.()
      if (this._syncRightPanels) this._syncRightPanels()
      return this._timelineSituationCount
    } catch (error) {
      console.warn("Timeline conflict pulse fetch failed:", error)
      this._timelineSituationCount = 0
      return 0
    }
  }

  GlobeController.prototype._renderUnifiedTimelineEvents = function(events, strikeEvents = []) {
    getDataSource(this.viewer, this._ds, "timelineEvents").entities.removeAll()
    const cursor = this._timelineCursor
    const showHeatSignatures = this._heatSignaturesLayerVisible ? this._heatSignaturesLayerVisible() : !!(this.heatSignaturesVisible || this.strikesVisible)
    const showVerifiedStrikes = this._verifiedStrikesLayerVisible ? this._verifiedStrikesLayerVisible() : !!(this.verifiedStrikesVisible || this.strikesVisible)
    const byType = {}
    events.forEach(event => {
      if (!byType[event.type]) byType[event.type] = []
      byType[event.type].push(event)
    })

    if (byType.earthquake && this.earthquakesVisible) {
      this._earthquakeData = byType.earthquake.map(event => ({
        id: event.id,
        title: event.title,
        mag: event.mag,
        magType: event.magType,
        lat: event.lat,
        lng: event.lng,
        depth: event.depth,
        url: event.url,
        time: event.time ? new Date(event.time).getTime() : null,
        timelineAlpha: timelineWindowAlpha(event.time, cursor, EVENT_TIMELINE_WINDOWS_MS.earthquake),
      }))
      this.renderEarthquakes()
    } else if (this.earthquakesVisible) {
      this._earthquakeData = []
      this.renderEarthquakes()
    }

    if (byType.natural_event && this.naturalEventsVisible) {
      this._naturalEventData = byType.natural_event.map(event => ({
        id: event.id,
        title: event.title,
        categoryId: event.categoryId,
        categoryTitle: event.categoryTitle,
        lat: event.lat,
        lng: event.lng,
        date: event.time,
        magnitudeValue: event.magnitudeValue,
        timelineAlpha: timelineWindowAlpha(event.time, cursor, EVENT_TIMELINE_WINDOWS_MS.natural_event),
      }))
      this.renderNaturalEvents()
    } else if (this.naturalEventsVisible) {
      this._naturalEventData = []
      this.renderNaturalEvents()
    }

    if (byType.news && this.newsVisible) {
      const cursorMs = this._timelineCursor?.getTime() || Date.now()
      const newsData = byType.news
        .filter(event => {
          const eventMs = event.time ? new Date(event.time).getTime() : Number.NEGATIVE_INFINITY
          return !Number.isFinite(eventMs) || eventMs <= cursorMs
        })
        .map(event => ({
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
          timelinePulse: timelinePulseFactor(event.time, cursorMs),
      }))
      this._newsData = newsData
      this._renderTimelineNews(newsData)
    } else if (this.newsVisible) {
      this._newsData = []
      this._renderTimelineNews([])
    }

    if (byType.gps_jamming && this.gpsJammingVisible) {
      const jammingData = collapseTimelineGpsJammingEvents(byType.gps_jamming, this._timelineCursor).map(event => ({
        lat: event.lat,
        lng: event.lng,
        total: event.total,
        bad: event.bad,
        pct: event.pct,
        level: event.level,
        timelineAlpha: timelineWindowAlpha(event.time, this._timelineCursor, EVENT_TIMELINE_WINDOWS_MS.gps_jamming),
      }))
      this._gpsJammingData = jammingData
      this._renderGpsJamming(jammingData)
    } else if (this.gpsJammingVisible) {
      this._gpsJammingData = []
      this._renderGpsJamming([])
    }

    if (byType.internet_outage && this.outagesVisible) {
      const outageEvents = byType.internet_outage.map(event => ({
        id: event.id,
        code: event.code,
        name: event.name,
        score: event.score,
        level: event.level,
        time: event.time,
        timelineAlpha: timelineWindowAlpha(event.time, this._timelineCursor, EVENT_TIMELINE_WINDOWS_MS.internet_outage),
      }))
      const outageSummary = this._deriveOutageSummary ? this._deriveOutageSummary(outageEvents) : outageEvents
      this._outageData = outageSummary
      this._renderOutages({ summary: outageSummary, events: outageEvents })
    } else if (this.outagesVisible) {
      this._outageData = []
      this._renderOutages({ summary: [], events: [] })
    }

    if (byType.weather_alert && this.weatherVisible) {
      this._weatherAlerts = byType.weather_alert.map(event => ({
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
        timelineAlpha: timelineWindowAlpha(event.time, this._timelineCursor, EVENT_TIMELINE_WINDOWS_MS.weather_alert),
      }))
      this._renderWeatherAlerts()
    } else if (this.weatherVisible) {
      this._weatherAlerts = []
      this._clearWeatherAlertEntities?.()
    }

    if (byType.notam && this.notamsVisible) {
      this._notamData = byType.notam.map(event => ({
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
        timelineAlpha: timelineWindowAlpha(event.time, this._timelineCursor, EVENT_TIMELINE_WINDOWS_MS.notam),
      }))
      this.renderNotams()
    } else if (this.notamsVisible) {
      this._notamData = []
      this._clearNotamEntities?.()
    }

    if (showHeatSignatures || showVerifiedStrikes) {
      const cursorMs = this._timelineCursor?.getTime() || Date.now()
      const oldestStrikeMs = cursorMs - STRIKE_TIMELINE_WINDOW_MS

      this._strikeDetections = showHeatSignatures
        ? strikeEvents
          .filter(event => event?.type === "fire")
          .filter(event => timelineStrikeWindowContains(event, oldestStrikeMs, cursorMs))
          .map(event => timelineFireToStrikeDetection(event))
        : []

      this._gcDetections = showVerifiedStrikes
        ? strikeEvents
          .filter(event => event?.type === "geoconfirmed")
          .filter(event => timelineStrikeWindowContains(event, oldestStrikeMs, cursorMs))
          .map(event => timelineGeoconfirmedToDetection(event))
        : []

      this.renderStrikes()
    } else if (this._timelineActive) {
      this._strikeDetections = []
      this._gcDetections = []
      this._clearStrikeEntities?.()
    }
  }
}

function collapseTimelineGpsJammingEvents(events, cursor) {
  const cursorMs = cursor instanceof Date ? cursor.getTime() : Date.now()
  const byCell = new Map()

  events.forEach(event => {
    const key = `${event.lat},${event.lng}`
    const current = byCell.get(key)
    if (!current || gpsJammingCursorDistance(event, cursorMs) < gpsJammingCursorDistance(current, cursorMs)) {
      byCell.set(key, event)
      return
    }

    if (gpsJammingCursorDistance(event, cursorMs) === gpsJammingCursorDistance(current, cursorMs) &&
      gpsJammingEventTime(event) > gpsJammingEventTime(current)) {
      byCell.set(key, event)
    }
  })

  return [...byCell.values()]
}

function gpsJammingCursorDistance(event, cursorMs) {
  const eventMs = gpsJammingEventTime(event)
  return Number.isFinite(eventMs) ? Math.abs(eventMs - cursorMs) : Number.POSITIVE_INFINITY
}

function gpsJammingEventTime(event) {
  const eventMs = event?.time ? new Date(event.time).getTime() : Number.NaN
  return Number.isFinite(eventMs) ? eventMs : Number.NEGATIVE_INFINITY
}

async function fetchTimelineEventSet({ from, to, types, bounds }) {
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

function groupTimelineTypesByWindow(types) {
  const grouped = new Map()

  types.forEach((type) => {
    const windowMs = EVENT_TIMELINE_WINDOWS_MS[type] || (24 * 60 * 60 * 1000)
    if (!grouped.has(windowMs)) grouped.set(windowMs, [])
    grouped.get(windowMs).push(type)
  })

  return [...grouped.entries()].map(([windowMs, groupedTypes]) => ({
    windowMs: Number(windowMs),
    types: groupedTypes,
  }))
}

function timelineStrikeWindowContains(event, fromMs, toMs) {
  const eventMs = event?.time ? new Date(event.time).getTime() : Number.NaN
  return Number.isFinite(eventMs) && eventMs >= fromMs && eventMs <= toMs
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

function timelineWindowAlpha(eventTime, cursorOrMs, windowMs) {
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

function timelineAppearProgress(eventTime, cursorOrMs) {
  const eventMs = eventTime ? new Date(eventTime).getTime() : Number.NaN
  const cursorMs = cursorOrMs instanceof Date ? cursorOrMs.getTime() : Number(cursorOrMs)
  if (!Number.isFinite(eventMs) || !Number.isFinite(cursorMs)) return 1

  const ageMs = cursorMs - eventMs
  if (ageMs <= 0) return 0
  return Math.min(ageMs / EVENT_APPEAR_WINDOW_MS, 1)
}

function timelinePulseFactor(eventTime, cursorOrMs) {
  const eventMs = eventTime ? new Date(eventTime).getTime() : Number.NaN
  const cursorMs = cursorOrMs instanceof Date ? cursorOrMs.getTime() : Number(cursorOrMs)
  if (!Number.isFinite(eventMs) || !Number.isFinite(cursorMs)) return 0

  const ageMs = cursorMs - eventMs
  if (ageMs < 0 || ageMs > EVENT_PULSE_WINDOW_MS) return 0
  return 1 - (ageMs / EVENT_PULSE_WINDOW_MS)
}

function timelineFetchBucketEnd(cursorMs, bucketMs) {
  return Math.ceil(cursorMs / bucketMs) * bucketMs || bucketMs
}

function buildTimelineEventFetchKey(cursor, groupedTypes, strikeTypes, bounds) {
  const cursorMs = cursor?.getTime?.()
  const generalKeys = groupedTypes.map(({ windowMs, types }) => (
    `${windowMs}:${timelineFetchBucketEnd(cursorMs, GENERAL_EVENT_FETCH_BUCKET_MS)}:${types.slice().sort().join(",")}`
  ))
  const strikeKey = strikeTypes.length > 0
    ? `${timelineFetchBucketEnd(cursorMs, STRIKE_EVENT_FETCH_BUCKET_MS)}:${strikeTypes.slice().sort().join(",")}`
    : ""
  return JSON.stringify({
    bounds: bounds ? `${bounds.lamin},${bounds.lamax},${bounds.lomin},${bounds.lomax}` : "global",
    generalKeys,
    strikeKey,
  })
}
