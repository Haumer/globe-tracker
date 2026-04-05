import { getPlaybackBounds } from "globe/camera"
import { getDataSource } from "globe/utils"

const GENERAL_TIMELINE_WINDOW_MS = 3600000
const STRIKE_TIMELINE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000

export function applyTimelineEventMethods(GlobeController) {
  GlobeController.prototype._timelineUpdateEvents = async function() {
    if (!this._timelineActive) return

    const cursor = this._timelineCursor
    const generalTypes = []
    if (this.earthquakesVisible) generalTypes.push("earthquake")
    if (this.naturalEventsVisible) generalTypes.push("natural_event")
    if (this.newsVisible) generalTypes.push("news")
    if (this.gpsJammingVisible) generalTypes.push("gps_jamming")
    if (this.outagesVisible) generalTypes.push("internet_outage")

    const strikeTypes = this.strikesVisible ? ["fire", "geoconfirmed"] : []

    if (generalTypes.length === 0 && strikeTypes.length === 0) {
      this._timelineEventCount = 0
      getDataSource(this.viewer, this._ds, "timelineEvents").entities.removeAll()
      this._strikeDetections = []
      this._gcDetections = []
      this._clearStrikeEntities?.()
      return 0
    }

    const bounds = this.hasActiveFilter() ? this.getFilterBounds() : (getPlaybackBounds(this.viewer) || this._timelinePlaybackBounds)

    try {
      const generalPromise = fetchTimelineEventSet({
        from: new Date(cursor.getTime() - GENERAL_TIMELINE_WINDOW_MS).toISOString(),
        to: new Date(cursor.getTime() + GENERAL_TIMELINE_WINDOW_MS).toISOString(),
        types: generalTypes,
        bounds,
      })
      const strikePromise = fetchTimelineEventSet({
        from: new Date(cursor.getTime() - STRIKE_TIMELINE_WINDOW_MS).toISOString(),
        to: cursor.toISOString(),
        types: strikeTypes,
        bounds,
      })

      const [events, strikeEvents] = await Promise.all([generalPromise, strikePromise])
      this._timelineEventCount = (Array.isArray(events) ? events.length : 0) + (Array.isArray(strikeEvents) ? strikeEvents.length : 0)
      this._renderUnifiedTimelineEvents(events, strikeEvents)
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
      }))
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
      }))
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
        }))
      this._newsData = newsData
      this._renderTimelineNews(newsData)
    }

    if (byType.gps_jamming && this.gpsJammingVisible) {
      const jammingData = collapseTimelineGpsJammingEvents(byType.gps_jamming, this._timelineCursor).map(event => ({
        lat: event.lat,
        lng: event.lng,
        total: event.total,
        bad: event.bad,
        pct: event.pct,
        level: event.level,
      }))
      this._gpsJammingData = jammingData
      this._renderGpsJamming(jammingData)
    }

    if (byType.internet_outage && this.outagesVisible) {
      const outageEvents = byType.internet_outage.map(event => ({
        id: event.id,
        code: event.code,
        name: event.name,
        score: event.score,
        level: event.level,
      }))
      this._outageData = outageEvents
      this._renderOutages({ summary: outageEvents, events: outageEvents })
    }

    if (this.strikesVisible) {
      const cursorMs = this._timelineCursor?.getTime() || Date.now()
      const oldestStrikeMs = cursorMs - STRIKE_TIMELINE_WINDOW_MS

      this._strikeDetections = strikeEvents
        .filter(event => event?.type === "fire")
        .filter(event => timelineStrikeWindowContains(event, oldestStrikeMs, cursorMs))
        .map(event => timelineFireToStrikeDetection(event))

      this._gcDetections = strikeEvents
        .filter(event => event?.type === "geoconfirmed")
        .filter(event => timelineStrikeWindowContains(event, oldestStrikeMs, cursorMs))
        .map(event => timelineGeoconfirmedToDetection(event))

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
  }
}
