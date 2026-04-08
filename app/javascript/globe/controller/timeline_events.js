import { getDataSource } from "globe/utils"
import { playbackEphemeralRequest } from "globe/controller/timeline_contract"
import { TIMELINE_CONFLICT_BUCKET_MS } from "globe/controller/timeline/constants"
import {
  buildConflictTimelineData,
  buildEarthquakeTimelineData,
  buildFireHotspotTimelineData,
  buildGpsJammingTimelineData,
  buildNaturalEventTimelineData,
  buildNewsTimelineData,
  buildNotamTimelineData,
  buildOutageTimelineRenderData,
  buildStrikeTimelineState,
  buildTimelineRenderKey,
  buildWeatherAlertTimelineData,
  groupPlaybackEvents,
} from "globe/controller/timeline/event_builders"
import {
  buildTimelineEventFetchKey,
  fetchTimelineConflictSet,
  fetchTimelineEventSet,
} from "globe/controller/timeline/event_fetch"

export function applyTimelineEventMethods(GlobeController) {
  GlobeController.prototype._timelineRenderCachedState = function(force = false) {
    if (!this._timelineActive) return
    const cursorMs = this._timelineCursor?.getTime?.()
    if (!Number.isFinite(cursorMs)) return
    const renderKey = buildTimelineRenderKey(this, cursorMs)
    if (!force && renderKey === this._timelineLastRenderedCursorKey) return
    this._timelineLastRenderedCursorKey = renderKey
    this._timelineLastRenderedCursorMs = cursorMs
    this._renderUnifiedTimelineEvents(
      this._timelineFetchedGeneralEvents || [],
      this._timelineFetchedStrikeEvents || [],
      this._timelineFetchedConflictEvents || []
    )
  }

  GlobeController.prototype._timelineUpdateEvents = async function() {
    if (!this._timelineActive) return

    const request = playbackEphemeralRequest(this)
    if (!request.hasAny) {
      this._timelineEventCount = 0
      this._timelineEventFetchKey = null
      this._timelineConflictFetchKey = null
      this._timelineFetchedGeneralEvents = []
      this._timelineFetchedStrikeEvents = []
      this._timelineFetchedConflictEvents = []
      getDataSource(this.viewer, this._ds, "timelineEvents").entities.removeAll()
      this._conflictData = []
      this._clearConflictEntities?.()
      this._fireHotspotData = []
      this._clearFireHotspotEntities?.()
      this._strikeDetections = []
      this._gcDetections = []
      this._clearStrikeEntities?.()
      return 0
    }

    const bounds = this.hasActiveFilter() ? this.getFilterBounds() : null
    const requestKey = buildTimelineEventFetchKey(
      this._timelineRangeStart,
      this._timelineRangeEnd,
      request,
      bounds
    )

    try {
      if (requestKey === this._timelineEventFetchKey) {
        this._timelineEventCount =
          (this._timelineFetchedGeneralEvents?.length || 0) +
          (this._timelineFetchedStrikeEvents?.length || 0) +
          (this._timelineFetchedConflictEvents?.length || 0)
        this._timelineRenderCachedState()
        this._updateStats()
        return this._timelineEventCount
      }

      const from = this._timelineRangeStart?.toISOString?.()
      const to = this._timelineRangeEnd?.toISOString?.()
      const generalPromise = request.generalTypes.length > 0
        ? fetchTimelineEventSet({
            from,
            to,
            types: request.generalTypes,
            bounds,
          })
        : Promise.resolve([])
      const strikePromise = request.strikeTypes.length > 0
        ? fetchTimelineEventSet({
            from,
            to,
            types: request.strikeTypes,
            bounds,
          })
        : Promise.resolve([])
      const conflictPromise = request.wantsConflictEvents
        ? fetchTimelineConflictSet({ from, to, bounds })
        : Promise.resolve([])

      const [events, strikeEvents, conflictEvents] = await Promise.all([generalPromise, strikePromise, conflictPromise])
      this._timelineEventFetchKey = requestKey
      this._timelineFetchedGeneralEvents = Array.isArray(events) ? events : []
      this._timelineFetchedStrikeEvents = Array.isArray(strikeEvents) ? strikeEvents : []
      this._timelineFetchedConflictEvents = Array.isArray(conflictEvents) ? conflictEvents : []
      this._timelineEventCount =
        this._timelineFetchedGeneralEvents.length +
        this._timelineFetchedStrikeEvents.length +
        this._timelineFetchedConflictEvents.length
      this._timelineRenderCachedState(true)
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
    const bucket = cursorMs - (cursorMs % TIMELINE_CONFLICT_BUCKET_MS)
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

  GlobeController.prototype._renderUnifiedTimelineEvents = function(events, strikeEvents = [], conflictEvents = []) {
    getDataSource(this.viewer, this._ds, "timelineEvents").entities.removeAll()
    const cursorMs = this._timelineCursor?.getTime() || Date.now()
    this._timelinePulseAnimationActive = false
    const showHeatSignatures = this._heatSignaturesLayerVisible ? this._heatSignaturesLayerVisible() : !!(this.heatSignaturesVisible || this.strikesVisible)
    const showVerifiedStrikes = this._verifiedStrikesLayerVisible ? this._verifiedStrikesLayerVisible() : !!(this.verifiedStrikesVisible || this.strikesVisible)
    const byType = groupPlaybackEvents(events)

    if (byType.earthquake && this.earthquakesVisible) {
      this._earthquakeData = buildEarthquakeTimelineData(this, byType.earthquake, cursorMs)
      this.renderEarthquakes()
    } else if (this.earthquakesVisible) {
      this._earthquakeData = []
      this.renderEarthquakes()
    }

    if (byType.natural_event && this.naturalEventsVisible) {
      this._naturalEventData = buildNaturalEventTimelineData(this, byType.natural_event, cursorMs)
      this.renderNaturalEvents()
    } else if (this.naturalEventsVisible) {
      this._naturalEventData = []
      this.renderNaturalEvents()
    }

    if (byType.news && this.newsVisible) {
      const newsData = buildNewsTimelineData(this, byType.news, cursorMs)
      this._newsData = newsData
      this._renderTimelineNews(newsData)
    } else if (this.newsVisible) {
      this._newsData = []
      this._renderTimelineNews([])
    }

    if (byType.gps_jamming && this.gpsJammingVisible) {
      const jammingData = buildGpsJammingTimelineData(this, byType.gps_jamming, cursorMs, this._timelineCursor)
      this._gpsJammingData = jammingData
      this._renderGpsJamming(jammingData)
    } else if (this.gpsJammingVisible) {
      this._gpsJammingData = []
      this._renderGpsJamming([])
    }

    if (byType.internet_outage && this.outagesVisible) {
      const { summary: outageSummary, events: outageEvents } = buildOutageTimelineRenderData(this, byType.internet_outage, cursorMs)
      this._outageData = outageSummary
      this._renderOutages({ summary: outageSummary, events: outageEvents })
    } else if (this.outagesVisible) {
      this._outageData = []
      this._renderOutages({ summary: [], events: [] })
    }

    if (byType.weather_alert && this.weatherVisible) {
      this._weatherAlerts = buildWeatherAlertTimelineData(byType.weather_alert, cursorMs)
      this._renderWeatherAlerts()
    } else if (this.weatherVisible) {
      this._weatherAlerts = []
      this._clearWeatherAlertEntities?.()
    }

    if (byType.notam && this.notamsVisible) {
      this._notamData = buildNotamTimelineData(byType.notam, cursorMs)
      this.renderNotams()
    } else if (this.notamsVisible) {
      this._notamData = []
      this._clearNotamEntities?.()
    }

    if (showHeatSignatures || showVerifiedStrikes) {
      const strikeState = buildStrikeTimelineState(this, strikeEvents, cursorMs, {
        showHeatSignatures,
        showVerifiedStrikes,
      })
      this._strikeDetections = strikeState.strikeDetections
      this._gcDetections = strikeState.gcDetections
      this.renderStrikes()
    } else if (this._timelineActive) {
      this._strikeDetections = []
      this._gcDetections = []
      this._clearStrikeEntities?.()
    }

    if (this.fireHotspotsVisible) {
      this._fireHotspotData = buildFireHotspotTimelineData(this, strikeEvents, cursorMs)
      this._fireHotspotClusterData = []
      this.renderFireHotspots()
    }

    if (this.conflictsVisible) {
      this._conflictData = buildConflictTimelineData(this, conflictEvents, cursorMs)
      this.renderConflicts()
    }

    this._requestRender?.()
    if (this._timelinePulseAnimationActive) this._timelineEnsurePulseLoop?.()
  }

  GlobeController.prototype._timelineEnsurePulseLoop = function() {
    if (!this._timelineActive || !this._timelinePulseAnimationActive || this._timelinePulseRaf) return

    this._timelinePulseRaf = requestAnimationFrame(() => {
      this._timelinePulseRaf = null
      if (!this._timelineActive || !this._timelinePulseAnimationActive) return
      this._timelineRenderCachedState(true)
      this._requestRender?.()
      if (this._timelinePulseAnimationActive) this._timelineEnsurePulseLoop()
    })
  }
}
