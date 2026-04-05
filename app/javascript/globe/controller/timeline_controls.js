export function applyTimelineControlMethods(GlobeController) {
  GlobeController.prototype.timelineOpen = async function() {
    if (this._timelineActive) {
      this.timelineClose()
      return
    }

    try {
      const response = await fetch("/api/playback/range")
      const range = await response.json()
      if (!range.oldest) {
        console.warn("No timeline data available yet")
        return
      }

      initializeTimelineState.call(this, range)
      autoEnablePlaybackLayers.call(this)
      this._timelinePauseLive()

      this.timelineBarTarget.style.display = ""
      this.timelineTimeStartTarget.textContent = this._fmtTimelineDateTime(this._timelineRangeStart)
      this.timelineTimeEndTarget.textContent = this._fmtTimelineDateTime(this._timelineRangeEnd)
      this._updateTimelineCursorDisplay()

      this._toast("Loading time travel data...")
      const frameStatus = await this._timelineLoadFrames()
      const eventCount = await this._timelineUpdateEvents()
      const situationCount = await this._timelineUpdateConflictPulse()

      showTimelineAvailabilityToast.call(this, frameStatus, eventCount, situationCount, true)
    } catch (error) {
      console.error("Timeline open error:", error)
    }
  }

  GlobeController.prototype._timelinePauseLive = function() {
    this._timelinePausedIntervals = {
      flight: !!this.flightInterval,
      ship: !!this.shipInterval,
      strikes: !!this._strikesInterval,
      gpsJamming: !!this._gpsJammingInterval,
      news: !!this._newsInterval,
      events: !!this._eventsInterval,
      outages: !!this._outageInterval,
    }

    clearLiveIntervals.call(this)

    if (this._conflictPulseInterval) {
      clearInterval(this._conflictPulseInterval)
      this._conflictPulseInterval = null
    }
    this._clearConflictPulseEntities?.()
    this._lastConflictPulseBucket = null

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
    restoreHiddenSources.call(this)

    if (this.flightsVisible) {
      this.fetchFlights()
      this.flightInterval = setInterval(() => this.fetchFlights(), 10000)
    }
    if (this.shipsVisible) {
      this.fetchShips()
      this.shipInterval = setInterval(() => this.fetchShips(), 60000)
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
    if (this.strikesVisible) {
      this.fetchStrikes()
      this._strikesInterval = setInterval(() => {
        if (this.strikesVisible) this.fetchStrikes()
      }, 300000)
    }
    if (this.situationsVisible && this._fetchConflictPulse) {
      this._fetchConflictPulse()
      this._conflictPulseInterval = setInterval(() => this._fetchConflictPulse(), 10 * 60 * 1000)
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
    } else if (this._timelineRaf) {
      cancelAnimationFrame(this._timelineRaf)
    }
  }

  GlobeController.prototype._timelineTick = function() {
    if (!this._timelinePlaying || !this._timelineActive) return

    const now = performance.now()
    const dt = (now - this._timelineLastTick) / 1000
    this._timelineLastTick = now

    const advanceMs = dt * this._timelineSpeed * 10000
    const newCursorMs = Math.min(
      this._timelineCursor.getTime() + advanceMs,
      this._timelineRangeEnd.getTime()
    )
    this._timelineCursor = new Date(newCursorMs)
    this._syncScrubberToCursor()
    this._updateTimelineCursorDisplay()
    this._renderNearestFrame()
    this._timelineEventDebounce()

    if (newCursorMs >= this._timelineRangeEnd.getTime()) {
      this._timelinePlaying = false
      if (this.hasTimelinePlayBtnTarget) this.timelinePlayBtnTarget.classList.remove("playing")
      if (this.hasTimelinePlayIconTarget) this.timelinePlayIconTarget.className = "fa-solid fa-play"
      return
    }

    this._timelineRaf = requestAnimationFrame(() => this._timelineTick())
  }

  GlobeController.prototype.timelineStepBack = function() {
    stepTimeline.call(this, -1)
  }

  GlobeController.prototype.timelineStepForward = function() {
    stepTimeline.call(this, 1)
  }

  GlobeController.prototype.timelineScrub = function() {
    if (!this._timelineActive || !this.hasTimelineScrubberTarget) return
    const value = parseInt(this.timelineScrubberTarget.value)
    const range = this._timelineRangeEnd.getTime() - this._timelineRangeStart.getTime()
    const cursorMs = this._timelineRangeStart.getTime() + (value / 10000) * range
    this._timelineCursor = new Date(cursorMs)
    this._updateTimelineCursorDisplay()
    this._renderNearestFrame()
    this._timelineEventDebounce()
  }

  GlobeController.prototype.timelineSetSpeed = function() {
    if (this.hasTimelineSpeedTarget) this._timelineSpeed = parseInt(this.timelineSpeedTarget.value)
  }

  GlobeController.prototype.timelineGoLive = function() {
    this.timelineClose()
    this._toast("Back to live", "success")
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

    this._timelineLastKnown = null
    this._timelineAppliedFrameIndex = -1
    this._ds["timeline"]?.entities.removeAll()
    this._ds["timelineEvents"]?.entities.removeAll()

    this._lastConflictPulseBucket = null
    this._clearConflictPulseEntities?.()
    clearLiveEntities.call(this)
    if (this.flightData) this.flightData.clear()
    if (this.shipData) this.shipData.clear()
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
    const cursor = this._timelineCursor
    if (this.hasTimelineCursorDateTarget) this.timelineCursorDateTarget.textContent = cursor.toISOString().slice(0, 10)
    if (this.hasTimelineCursorTimeTarget) this.timelineCursorTimeTarget.textContent = cursor.toUTCString().slice(17, 25)
  }

  GlobeController.prototype._timelineEventDebounce = function() {
    if (this._timelineEventTimer) clearTimeout(this._timelineEventTimer)
    this._timelineEventTimer = setTimeout(() => this._timelineUpdateEvents(), 400)
    this._timelineUpdateConflictPulse()
  }

  GlobeController.prototype.timelinePickDate = function() {
    if (!this._timelineActive) return

    const input = document.createElement("input")
    input.type = "datetime-local"
    input.style.cssText = "position:fixed;top:-9999px;"
    const oldest = this._timelineOldest || this._timelineRangeStart
    input.min = oldest.toISOString().slice(0, 16)
    input.max = new Date().toISOString().slice(0, 16)
    input.value = this._timelineRangeStart.toISOString().slice(0, 16)
    document.body.appendChild(input)
    input.addEventListener("change", () => {
      const picked = new Date(`${input.value}Z`)
      if (!isNaN(picked)) this._timelineSetRange(picked, new Date())
      input.remove()
    })
    input.addEventListener("blur", () => setTimeout(() => input.remove(), 200))
    input.showPicker()
  }

  GlobeController.prototype._timelineSetRange = async function(start, end) {
    this._timelineRangeStart = start
    this._timelineRangeEnd = end
    this._timelineCursor = new Date(start.getTime())
    this._timelineFrameIndex = 0

    this.timelineTimeStartTarget.textContent = this._fmtTimelineDateTime(start)
    this.timelineTimeEndTarget.textContent = this._fmtTimelineDateTime(end)
    this._updateTimelineCursorDisplay()
    this._syncScrubberToCursor()

    this._toast("Loading time travel data...")
    const frameStatus = await this._timelineLoadFrames()
    const eventCount = await this._timelineUpdateEvents()
    const situationCount = await this._timelineUpdateConflictPulse()

    showTimelineAvailabilityToast.call(this, frameStatus, eventCount, situationCount, false)
  }

  GlobeController.prototype._timelineOnLayerToggle = function() {
    if (!this._timelineActive) return
    if (this._timelineLayerReloadTimer) clearTimeout(this._timelineLayerReloadTimer)
    this._timelineLayerReloadTimer = setTimeout(async () => {
      await this._timelineLoadFrames()
      this._renderNearestFrame()
      await this._timelineUpdateEvents()
      await this._timelineUpdateConflictPulse()
    }, 300)
  }
}

function initializeTimelineState(range) {
  this._timelineActive = true
  this._timelinePlaying = false
  this._timelineSpeed = 5
  this._timelineFrames = {}
  this._timelineKeys = []
  this._timelineFrameIndex = 0
  this._timelineAppliedFrameIndex = -1
  this._timelineEventCount = 0
  this._timelineSituationCount = 0

  const oldest = new Date(range.oldest)
  const newest = new Date(Math.min(new Date(range.newest).getTime(), Date.now()))
  const oneDayAgo = new Date(newest.getTime() - 24 * 60 * 60 * 1000)
  this._timelineRangeStart = oneDayAgo > oldest ? oneDayAgo : oldest
  this._timelineRangeEnd = newest
  this._timelineOldest = oldest
  this._timelineCursor = new Date(this._timelineRangeStart.getTime())
}

function autoEnablePlaybackLayers() {
  if (this.flightsVisible || this.shipsVisible || !this.hasFlightsToggleTarget) return
  this.flightsToggleTarget.checked = true
  this.flightsVisible = true
}

function clearLiveIntervals() {
  if (this.flightInterval) { clearInterval(this.flightInterval); this.flightInterval = null }
  if (this.shipInterval) { clearInterval(this.shipInterval); this.shipInterval = null }
  if (this._strikesInterval) { clearInterval(this._strikesInterval); this._strikesInterval = null }
  if (this._gpsJammingInterval) { clearInterval(this._gpsJammingInterval); this._gpsJammingInterval = null }
  if (this._newsInterval) { clearInterval(this._newsInterval); this._newsInterval = null }
  if (this._eventsInterval) { clearInterval(this._eventsInterval); this._eventsInterval = null }
  if (this._outageInterval) { clearInterval(this._outageInterval); this._outageInterval = null }
}

function restoreHiddenSources() {
  if (!this._timelineHiddenSources) return

  const activeDs = new Set()
  if (this.flightsVisible) activeDs.add("flights")
  if (this.shipsVisible) activeDs.add("ships")
  if (this.airportsVisible) activeDs.add("airports")
  if (this.earthquakesVisible || this.naturalEventsVisible) activeDs.add("events")
  if (this.gpsJammingVisible) activeDs.add("gpsJamming")
  if (this.newsVisible) activeDs.add("news")
  if (this.outagesVisible) activeDs.add("outages")
  if (this.strikesVisible) activeDs.add("strikes")
  if (this.trailsVisible) activeDs.add("trails")

  for (const name of this._timelineHiddenSources) {
    if (this._ds[name]) this._ds[name].show = activeDs.has(name)
  }
  this._timelineHiddenSources = null
}

function clearLiveEntities() {
  const liveDataSources = new Set(["flights", "ships", "trails", "events", "gpsJamming", "news", "outages", "traffic", "conflictEvents"])
  for (const [name, source] of Object.entries(this._ds)) {
    if (liveDataSources.has(name) && source) source.entities.removeAll()
  }
}

function stepTimeline(direction) {
  if (!this._timelineActive || this._timelineKeys.length === 0) return
  this._timelineFrameIndex = Math.max(0, Math.min(this._timelineKeys.length - 1, this._timelineFrameIndex + direction))
  const key = this._timelineKeys[this._timelineFrameIndex]
  if (!key) return
  this._timelineCursor = new Date(key)
  this._syncScrubberToCursor()
  this._updateTimelineCursorDisplay()
  this._renderTimelineFrame(this._timelineFrameIndex)
  this._timelineEventDebounce()
}

function showTimelineAvailabilityToast(frameStatus, eventCount, situationCount, opening) {
  const frameCount = frameStatus?.frameCount || 0
  const hasEventPlayback = this.earthquakesVisible || this.naturalEventsVisible || this.newsVisible ||
    this.gpsJammingVisible || this.outagesVisible || this.situationsVisible || this.strikesVisible

  if (frameStatus?.boundsRequired) {
    this._toast("Zoom in or apply a region filter to load movement playback.")
    return
  }

  if (frameCount > 0) {
    const suffix = opening ? " — press play" : ""
    this._toast(`Time travel: ${frameCount} movement frames loaded${suffix}`, "success")
    return
  }

  if (hasEventPlayback) {
    if ((eventCount || 0) > 0 || (situationCount || 0) > 0) {
      const parts = []
      if ((eventCount || 0) > 0) parts.push(`${eventCount} timeline events`)
      if ((situationCount || 0) > 0) parts.push(`${situationCount} situation zones`)
      this._toast(`Event playback ready: ${parts.join(" · ")}`)
      return
    }

    if (frameStatus?.movementEnabled === false) {
      this._toast("Event playback ready. Enable flights or ships if you also want movement snapshots.")
      return
    }

    this._toast("No flight or ship snapshots in this range. Event playback is still available.")
    return
  }

  this._toast("No playback data found for this time range", "error")
}
