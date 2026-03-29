import { getViewportBounds } from "../camera"
import { getDataSource } from "../utils"

export function applyTimelineEventMethods(GlobeController) {
  GlobeController.prototype._timelineUpdateEvents = async function() {
    if (!this._timelineActive) return

    const cursor = this._timelineCursor
    const windowMs = 3600000
    const from = new Date(cursor.getTime() - windowMs).toISOString()
    const to = new Date(cursor.getTime() + windowMs).toISOString()
    const types = []
    if (this.earthquakesVisible) types.push("earthquake")
    if (this.naturalEventsVisible) types.push("natural_event")
    if (this.newsVisible) types.push("news")
    if (this.gpsJammingVisible) types.push("gps_jamming")
    if (this.outagesVisible) types.push("internet_outage")
    if (types.length === 0) return

    let url = `/api/playback/events?from=${from}&to=${to}&types=${types.join(",")}`
    const bounds = this.hasActiveFilter() ? this.getFilterBounds() : getViewportBounds(this.viewer)
    if (bounds) {
      url += `&lamin=${bounds.lamin}&lamax=${bounds.lamax}&lomin=${bounds.lomin}&lomax=${bounds.lomax}`
    }

    try {
      const response = await fetch(url)
      const events = await response.json()
      this._renderUnifiedTimelineEvents(events)
      this._updateStats()
    } catch (error) {
      console.error("Timeline events error:", error)
    }
  }

  GlobeController.prototype._timelineUpdateConflictPulse = async function() {
    if (!this._timelineActive || !this._timelineCursor || !this.situationsVisible) return

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
      this._renderConflictPulse?.()
      this._renderSituationPanel?.()
      if (this._syncRightPanels) this._syncRightPanels()
    } catch (error) {
      console.warn("Timeline conflict pulse fetch failed:", error)
    }
  }

  GlobeController.prototype._renderUnifiedTimelineEvents = function(events) {
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
      const newsData = byType.news.map(event => ({
        lat: event.lat,
        lng: event.lng,
        name: event.name,
        url: event.url,
        tone: event.tone,
        level: event.level,
        category: event.category,
        themes: event.themes || [],
        time: event.time,
      }))
      this._newsData = newsData
      this._renderNews(newsData)
    }

    if (byType.gps_jamming && this.gpsJammingVisible) {
      const jammingData = byType.gps_jamming.map(event => ({
        lat: event.lat,
        lng: event.lng,
        total: event.total,
        bad: event.bad,
        pct: event.pct,
        level: event.level,
      }))
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
  }
}
