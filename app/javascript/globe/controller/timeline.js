import { getViewportBounds } from "../camera"
import { getDataSource } from "../utils"

export function applyTimelineMethods(GlobeController) {
  GlobeController.prototype.timelineOpen = async function() {
    if (this._timelineActive) { this.timelineClose(); return }

    try {
      const res = await fetch("/api/playback/range")
      const range = await res.json()
      if (!range.oldest) {
        console.warn("No timeline data available yet")
        return
      }

      this._timelineActive = true
      this._timelinePlaying = false
      this._timelineSpeed = 5
      this._timelineFrames = {}
      this._timelineKeys = []
      this._timelineFrameIndex = 0

      const oldest = new Date(range.oldest)
      const newest = new Date(range.newest)
      // Default to last 1 hour for a manageable playback window
      const oneHourAgo = new Date(newest.getTime() - 60 * 60 * 1000)
      this._timelineRangeStart = oneHourAgo > oldest ? oneHourAgo : oldest
      this._timelineRangeEnd = newest
      this._timelineCursor = new Date(this._timelineRangeStart.getTime())

      // Pause all live refresh intervals
      this._timelinePauseLive()

      this.timelineBarTarget.style.display = ""
      this.timelineTimeStartTarget.textContent = this._fmtTimelineDateTime(oldest)
      this.timelineTimeEndTarget.textContent = this._fmtTimelineDateTime(newest)
      this._updateTimelineCursorDisplay()

      // Load position snapshot frames for the full range
      await this._timelineLoadFrames()

      // Load event data for current cursor position
      this._timelineUpdateEvents()
    } catch (e) {
      console.error("Timeline open error:", e)
    }
  }

  GlobeController.prototype._timelineLoadFrames = async function() {
    if (!this._timelineActive) return
    const from = this._timelineRangeStart.toISOString()
    const to = this._timelineRangeEnd.toISOString()

    // Only fetch entity types that were active before entering playback
    let playbackType = "all"
    if (this.flightsVisible && !this.shipsVisible) playbackType = "flight"
    else if (this.shipsVisible && !this.flightsVisible) playbackType = "ship"
    let url = `/api/playback?from=${from}&to=${to}&type=${playbackType}`
    // Use country/circle filter bounds if active, otherwise viewport
    const bounds = this.hasActiveFilter() ? this.getFilterBounds() : getViewportBounds(this.viewer)
    if (bounds) {
      url += `&lamin=${bounds.lamin}&lamax=${bounds.lamax}&lomin=${bounds.lomin}&lomax=${bounds.lomax}`
    }

    try {
      const res = await fetch(url)
      const data = await res.json()
      this._timelineFrames = data.frames || {}
      this._timelineKeys = Object.keys(this._timelineFrames).sort()
      this._timelineFrameIndex = 0

      if (this._timelineKeys.length > 0) {
        this._renderTimelineFrame(0)
      }
    } catch (e) {
      console.error("Timeline frame load error:", e)
    }
  }

  GlobeController.prototype._timelinePauseLive = function() {
    // Store which intervals were active so we can restore them
    this._timelinePausedIntervals = {
      flight: !!this.flightInterval,
      ship: !!this.shipInterval,
      gpsJamming: !!this._gpsJammingInterval,
      news: !!this._newsInterval,
      events: !!this._eventsInterval,
      outages: !!this._outageInterval,
    }
    if (this.flightInterval) { clearInterval(this.flightInterval); this.flightInterval = null }
    if (this.shipInterval) { clearInterval(this.shipInterval); this.shipInterval = null }
    if (this._gpsJammingInterval) { clearInterval(this._gpsJammingInterval); this._gpsJammingInterval = null }
    if (this._newsInterval) { clearInterval(this._newsInterval); this._newsInterval = null }
    if (this._eventsInterval) { clearInterval(this._eventsInterval); this._eventsInterval = null }
    if (this._outageInterval) { clearInterval(this._outageInterval); this._outageInterval = null }

    // Hide only live-data sources that conflict with playback entities
    // Keep static overlays (borders, airports, cities, notams, etc.) visible
    const liveDataSources = new Set(["flights", "ships", "trails", "events", "gpsJamming", "news", "outages", "traffic", "conflictEvents"])
    this._timelineHiddenSources = []
    for (const [name, ds] of Object.entries(this._ds)) {
      if (!liveDataSources.has(name)) continue
      if (ds && ds.show) {
        ds.show = false
        this._timelineHiddenSources.push(name)
      }
    }
  }

  GlobeController.prototype._timelineResumeLive = function() {
    // Restore only data sources whose layer is still toggled on
    if (this._timelineHiddenSources) {
      const activeDs = new Set()
      if (this.flightsVisible) activeDs.add("flights")
      if (this.shipsVisible) activeDs.add("ships")
      if (this.airportsVisible) activeDs.add("airports")
      if (this.earthquakesVisible || this.naturalEventsVisible) activeDs.add("events")
      if (this.gpsJammingVisible) activeDs.add("gpsJamming")
      if (this.newsVisible) activeDs.add("news")
      if (this.outagesVisible) activeDs.add("outages")
      if (this.trailsVisible) activeDs.add("trails")
      for (const name of this._timelineHiddenSources) {
        if (this._ds[name]) this._ds[name].show = activeDs.has(name)
      }
      this._timelineHiddenSources = null
    }
    // Restart live fetch intervals for active layers
    if (this.flightsVisible) {
      this.fetchFlights()
      this.flightInterval = setInterval(() => this.fetchFlights(), 10000)
    }
    if (this.shipsVisible) {
      this.fetchShips()
      this.shipInterval = setInterval(() => this.fetchShips(), 15000)
    }
    if (this.gpsJammingVisible) {
      this.fetchGpsJamming()
      this._gpsJammingInterval = setInterval(() => this.fetchGpsJamming(), 60000)
    }
    if (this.newsVisible) {
      this.fetchNews()
      this._newsInterval = setInterval(() => this.fetchNews(), 900000)
    }
    if (this.earthquakesVisible || this.naturalEventsVisible) {
      if (this.earthquakesVisible) this.fetchEarthquakes()
      if (this.naturalEventsVisible) this.fetchNaturalEvents()
      this._eventsInterval = setInterval(() => {
        if (this.earthquakesVisible) this.fetchEarthquakes()
        if (this.naturalEventsVisible) this.fetchNaturalEvents()
      }, 300000)
    }
    if (this.outagesVisible) {
      this.fetchOutages()
      this._outageInterval = setInterval(() => this.fetchOutages(), 300000)
    }
  }

  GlobeController.prototype.timelineToggle = function() {
    if (!this._timelineActive) return
    this._timelinePlaying = !this._timelinePlaying

    if (this.hasTimelinePlayBtnTarget) this.timelinePlayBtnTarget.classList.toggle("playing", this._timelinePlaying)
    if (this.hasTimelinePlayIconTarget) this.timelinePlayIconTarget.className = this._timelinePlaying ? "fa-solid fa-pause" : "fa-solid fa-play"

    if (this._timelinePlaying) {
      this._timelineLastTick = performance.now()
      this._timelineTick()
    } else {
      if (this._timelineRaf) cancelAnimationFrame(this._timelineRaf)
    }
  }

  GlobeController.prototype._timelineTick = function() {
    if (!this._timelinePlaying || !this._timelineActive) return

    const now = performance.now()
    const dt = (now - this._timelineLastTick) / 1000
    this._timelineLastTick = now

    // Advance cursor by dt * speed * 10 seconds per real second
    const advanceMs = dt * this._timelineSpeed * 10000
    const newCursorMs = Math.min(
      this._timelineCursor.getTime() + advanceMs,
      this._timelineRangeEnd.getTime()
    )
    this._timelineCursor = new Date(newCursorMs)

    // Update scrubber position
    this._syncScrubberToCursor()
    this._updateTimelineCursorDisplay()

    // Find and render the nearest position frame
    this._renderNearestFrame()

    // Debounced event updates
    this._timelineEventDebounce()

    // Stop at end
    if (newCursorMs >= this._timelineRangeEnd.getTime()) {
      this._timelinePlaying = false
      if (this.hasTimelinePlayBtnTarget) this.timelinePlayBtnTarget.classList.remove("playing")
      if (this.hasTimelinePlayIconTarget) this.timelinePlayIconTarget.className = "fa-solid fa-play"
      return
    }

    this._timelineRaf = requestAnimationFrame(() => this._timelineTick())
  }

  GlobeController.prototype.timelineStepBack = function() {
    if (!this._timelineActive || this._timelineKeys.length === 0) return
    this._timelineFrameIndex = Math.max(0, this._timelineFrameIndex - 1)
    const key = this._timelineKeys[this._timelineFrameIndex]
    if (key) {
      this._timelineCursor = new Date(key)
      this._syncScrubberToCursor()
      this._updateTimelineCursorDisplay()
      this._renderTimelineFrame(this._timelineFrameIndex)
      this._timelineEventDebounce()
    }
  }

  GlobeController.prototype.timelineStepForward = function() {
    if (!this._timelineActive || this._timelineKeys.length === 0) return
    this._timelineFrameIndex = Math.min(this._timelineKeys.length - 1, this._timelineFrameIndex + 1)
    const key = this._timelineKeys[this._timelineFrameIndex]
    if (key) {
      this._timelineCursor = new Date(key)
      this._syncScrubberToCursor()
      this._updateTimelineCursorDisplay()
      this._renderTimelineFrame(this._timelineFrameIndex)
      this._timelineEventDebounce()
    }
  }

  GlobeController.prototype.timelineScrub = function() {
    if (!this._timelineActive || !this.hasTimelineScrubberTarget) return
    const val = parseInt(this.timelineScrubberTarget.value)
    const range = this._timelineRangeEnd.getTime() - this._timelineRangeStart.getTime()
    const cursorMs = this._timelineRangeStart.getTime() + (val / 10000) * range
    this._timelineCursor = new Date(cursorMs)
    this._updateTimelineCursorDisplay()
    this._renderNearestFrame()
    this._timelineEventDebounce()
  }

  GlobeController.prototype.timelineSetSpeed = function() {
    if (this.hasTimelineSpeedTarget) {
      this._timelineSpeed = parseInt(this.timelineSpeedTarget.value)
    }
  }

  GlobeController.prototype.timelineGoLive = function() {
    this._timelineCursor = new Date(this._timelineRangeEnd.getTime())
    this._syncScrubberToCursor()
    this._updateTimelineCursorDisplay()
    this._renderNearestFrame()
    this._timelineUpdateEvents()
  }

  GlobeController.prototype.timelineExport = function() {
    if (!this._timelineRangeStart || !this._timelineRangeEnd) return
    const from = this._timelineRangeStart.toISOString()
    const to = this._timelineRangeEnd.toISOString()

    const layers = []
    if (this.flightsVisible) layers.push("flights")
    if (this.shipsVisible) layers.push("ships")
    if (this.earthquakesVisible) layers.push("earthquakes")
    if (this.conflictsVisible) layers.push("conflicts")
    if (layers.length === 0) layers.push("flights")

    const url = `/api/exports/geojson?layers=${layers.join(",")}&from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`
    window.open(url, "_blank")
  }

  GlobeController.prototype.timelineClose = function() {
    this._timelineActive = false
    this._timelinePlaying = false
    if (this._timelineRaf) cancelAnimationFrame(this._timelineRaf)
    if (this._timelineEventTimer) clearTimeout(this._timelineEventTimer)
    this.timelineBarTarget.style.display = "none"

    // Clear timeline entities (positions + events)
    const ds = this._ds["timeline"]
    if (ds) ds.entities.removeAll()
    const evDs = this._ds["timelineEvents"]
    if (evDs) evDs.entities.removeAll()

    // Clear only live-data entities before resuming — they'll be re-fetched fresh
    const liveDataSources = new Set(["flights", "ships", "trails", "events", "gpsJamming", "news", "outages", "traffic", "conflictEvents"])
    for (const [name, source] of Object.entries(this._ds)) {
      if (!liveDataSources.has(name)) continue
      if (source) source.entities.removeAll()
    }
    // Clear flight/ship tracking maps so renderFlights/renderShips rebuild cleanly
    if (this.flightData) this.flightData.clear()
    if (this.shipData) this.shipData.clear()

    // Resume live data
    this._timelineResumeLive()
  }

  GlobeController.prototype._syncScrubberToCursor = function() {
    if (!this.hasTimelineScrubberTarget) return
    const range = this._timelineRangeEnd.getTime() - this._timelineRangeStart.getTime()
    if (range <= 0) return
    const pos = ((this._timelineCursor.getTime() - this._timelineRangeStart.getTime()) / range) * 10000
    this.timelineScrubberTarget.value = Math.round(pos)
  }

  GlobeController.prototype._updateTimelineCursorDisplay = function() {
    if (!this._timelineCursor) return
    const d = this._timelineCursor
    if (this.hasTimelineCursorDateTarget) {
      this.timelineCursorDateTarget.textContent = d.toISOString().slice(0, 10)
    }
    if (this.hasTimelineCursorTimeTarget) {
      this.timelineCursorTimeTarget.textContent = d.toUTCString().slice(17, 25)
    }
  }

  GlobeController.prototype._renderNearestFrame = function() {
    if (this._timelineKeys.length === 0) return
    // Binary search for nearest frame key
    const cursorIso = this._timelineCursor.toISOString()
    let lo = 0, hi = this._timelineKeys.length - 1
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (this._timelineKeys[mid] < cursorIso) lo = mid + 1
      else hi = mid
    }
    // Check if previous frame is closer
    if (lo > 0) {
      const prev = new Date(this._timelineKeys[lo - 1]).getTime()
      const curr = new Date(this._timelineKeys[lo]).getTime()
      const target = this._timelineCursor.getTime()
      if (Math.abs(target - prev) < Math.abs(target - curr)) lo = lo - 1
    }
    this._timelineFrameIndex = lo
    this._renderTimelineFrame(lo)
  }

  GlobeController.prototype._timelineEventDebounce = function() {
    if (this._timelineEventTimer) clearTimeout(this._timelineEventTimer)
    this._timelineEventTimer = setTimeout(() => this._timelineUpdateEvents(), 400)
  }

  GlobeController.prototype._timelineUpdateEvents = async function() {
    if (!this._timelineActive) return
    const cursor = this._timelineCursor
    const windowMs = 3600000
    const from = new Date(cursor.getTime() - windowMs).toISOString()
    const to = new Date(cursor.getTime() + windowMs).toISOString()

    // Build type filter based on visible layers
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
      const res = await fetch(url)
      const events = await res.json()
      this._renderUnifiedTimelineEvents(events)
      this._updateStats()
    } catch (e) {
      console.error("Timeline events error:", e)
    }
  }

  GlobeController.prototype._renderUnifiedTimelineEvents = function(events) {
    const Cesium = window.Cesium
    const dataSource = getDataSource(this.viewer, this._ds, "timelineEvents")

    // Clear previous event markers
    dataSource.entities.removeAll()

    // Group by type for the existing render methods
    const byType = {}
    events.forEach(e => {
      if (!byType[e.type]) byType[e.type] = []
      byType[e.type].push(e)
    })

    // Dispatch to existing renderers with the right data shape
    if (byType.earthquake && this.earthquakesVisible) {
      this._earthquakeData = byType.earthquake.map(e => ({
        id: e.id, title: e.title, mag: e.mag, magType: e.magType,
        lat: e.lat, lng: e.lng, depth: e.depth, url: e.url,
        time: e.time ? new Date(e.time).getTime() : null,
      }))
      this.renderEarthquakes()
    }
    if (byType.natural_event && this.naturalEventsVisible) {
      this._naturalEventData = byType.natural_event.map(e => ({
        id: e.id, title: e.title, categoryId: e.categoryId,
        categoryTitle: e.categoryTitle, lat: e.lat, lng: e.lng,
        date: e.time, magnitudeValue: e.magnitudeValue,
      }))
      this.renderNaturalEvents()
    }
    if (byType.news && this.newsVisible) {
      const newsData = byType.news.map(e => ({
        lat: e.lat, lng: e.lng, name: e.name, url: e.url,
        tone: e.tone, level: e.level, category: e.category,
        themes: e.themes || [], time: e.time,
      }))
      this._newsData = newsData
      this._renderNews(newsData)
    }
    if (byType.gps_jamming && this.gpsJammingVisible) {
      const jammingData = byType.gps_jamming.map(e => ({
        lat: e.lat, lng: e.lng, total: e.total, bad: e.bad,
        pct: e.pct, level: e.level,
      }))
      this._renderGpsJamming(jammingData)
    }
    if (byType.internet_outage && this.outagesVisible) {
      const outageEvents = byType.internet_outage.map(e => ({
        id: e.id, code: e.code, name: e.name,
        score: e.score, level: e.level,
      }))
      this._outageData = outageEvents
      this._renderOutages({ summary: outageEvents, events: outageEvents })
    }
  }

  // Render a playback frame, interpolating positions between current and next frame

  GlobeController.prototype._renderTimelineFrame = function(index) {
    const Cesium = window.Cesium
    const key = this._timelineKeys[index]
    if (!key) return

    const entities = this._timelineFrames[key]
    if (!entities) return

    // Build lookup for next frame (for interpolation)
    const nextKey = this._timelineKeys[index + 1]
    const nextEntities = nextKey ? this._timelineFrames[nextKey] : null
    const nextMap = new Map()
    if (nextEntities) {
      nextEntities.forEach(e => nextMap.set(`${e.type}-${e.id}`, e))
    }

    // Compute interpolation factor (0-1) between current and next frame
    let t = 0
    if (nextKey && this._timelineCursor) {
      const curMs = new Date(key).getTime()
      const nextMs = new Date(nextKey).getTime()
      const cursorMs = this._timelineCursor.getTime()
      if (nextMs > curMs) t = Math.max(0, Math.min(1, (cursorMs - curMs) / (nextMs - curMs)))
    }

    const dataSource = getDataSource(this.viewer, this._ds, "timeline")
    const existingIds = new Set()
    const hasFilter = this.hasActiveFilter()

    entities.forEach(e => {
      // Interpolate with next frame if available
      const next = nextMap.get(`${e.type}-${e.id}`)
      const lat = next ? e.lat + (next.lat - e.lat) * t : e.lat
      const lng = next ? e.lng + (next.lng - e.lng) * t : e.lng
      const alt = next ? (e.alt || 0) + ((next.alt || 0) - (e.alt || 0)) * t : (e.alt || 0)
      const hdg = next ? this._lerpAngle(e.hdg || 0, next.hdg || 0, t) : (e.hdg || 0)

      // Apply precise country/circle filter
      if (hasFilter && !this.pointPassesFilter(lat, lng)) return

      const isFlight = e.type === "flight"
      const id = `tl-${e.type}-${e.id}`
      existingIds.add(id)

      let entity = dataSource.entities.getById(id)
      const position = Cesium.Cartesian3.fromDegrees(lng, lat, alt + 100)

      if (entity) {
        entity.position = position
        entity.billboard.rotation = -Cesium.Math.toRadians(hdg)
        if (entity.label) entity.label.text = e.callsign || e.id
      } else {
        entity = dataSource.entities.add({
          id,
          position,
          billboard: {
            image: isFlight
              ? (e.gnd ? this.planeIconGround : this.planeIcon)
              : this._timelineShipIcon(),
            scale: isFlight ? 1.0 : 0.8,
            rotation: -Cesium.Math.toRadians(hdg),
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            heightReference: Cesium.HeightReference.NONE,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
          label: {
            text: e.callsign || e.id,
            font: "12px JetBrains Mono, monospace",
            fillColor: Cesium.Color.fromCssColorString(isFlight ? "rgba(200,210,225,0.85)" : "rgba(38,198,218,0.85)"),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: new Cesium.Cartesian2(0, -18),
            scale: 0.8,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          }
        })
      }
    })

    // Remove entities not in this frame
    const toRemove = []
    for (let i = 0; i < dataSource.entities.values.length; i++) {
      const ent = dataSource.entities.values[i]
      if (!existingIds.has(ent.id)) toRemove.push(ent)
    }
    toRemove.forEach(ent => dataSource.entities.remove(ent))

    this._requestRender()
  }

  // Interpolate between two angles (degrees), handling 359°→1° wraparound

  GlobeController.prototype._lerpAngle = function(a, b, t) {
    let diff = b - a
    if (diff > 180) diff -= 360
    if (diff < -180) diff += 360
    return (a + diff * t + 360) % 360
  }

  GlobeController.prototype._timelineShipIcon = function() {
    if (this._cachedTimelineShipIcon) return this._cachedTimelineShipIcon
    const canvas = document.createElement("canvas")
    canvas.width = 20
    canvas.height = 20
    const ctx = canvas.getContext("2d")
    ctx.fillStyle = "#26c6da"
    ctx.beginPath()
    ctx.moveTo(10, 2)
    ctx.lineTo(16, 16)
    ctx.lineTo(10, 13)
    ctx.lineTo(4, 16)
    ctx.closePath()
    ctx.fill()
    this._cachedTimelineShipIcon = canvas.toDataURL()
    return this._cachedTimelineShipIcon
  }

  GlobeController.prototype._fmtTimelineDateTime = function(dateOrStr) {
    const d = typeof dateOrStr === "string" ? new Date(dateOrStr) : dateOrStr
    if (!d || isNaN(d)) return "--"
    const mo = String(d.getUTCMonth() + 1).padStart(2, "0")
    const dy = String(d.getUTCDate()).padStart(2, "0")
    const hh = String(d.getUTCHours()).padStart(2, "0")
    const mm = String(d.getUTCMinutes()).padStart(2, "0")
    return `${mo}-${dy} ${hh}:${mm}`
  }

}
