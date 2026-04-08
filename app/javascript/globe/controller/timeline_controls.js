import {
  autoEnablePlaybackLayers,
  debounceTimelineRefresh,
  initializeTimelineState,
  refreshTimelineCursorLayers,
  resetTimelineState,
  revertAutoEnabledPlaybackLayers,
  showTimelineAvailabilityToast,
  syncTimelineScrubber,
  updateTimelineCursorDisplay,
} from "globe/controller/timeline/playback_state"
import {
  clearTimelineLiveEntities,
  pauseTimelineLive,
  resumeTimelineLive,
} from "globe/controller/timeline/live_mode"

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

      initializeTimelineState(this, range)
      autoEnablePlaybackLayers(this)
      pauseTimelineLive(this)

      this.timelineBarTarget.style.display = ""
      this.timelineTimeStartTarget.textContent = this._fmtTimelineDateTime(this._timelineRangeStart)
      this.timelineTimeEndTarget.textContent = this._fmtTimelineDateTime(this._timelineRangeEnd)
      updateTimelineCursorDisplay(this)

      this._toast("Loading time travel data...")
      const frameStatus = await this._timelineLoadFrames()
      const { eventCount, situationCount } = await this._timelineRefreshPlaybackState()

      showTimelineAvailabilityToast(this, frameStatus, eventCount, situationCount, true)
    } catch (error) {
      console.error("Timeline open error:", error)
    }
  }

  GlobeController.prototype._timelinePauseLive = function() {
    pauseTimelineLive(this)
  }

  GlobeController.prototype._timelineResumeLive = function() {
    resumeTimelineLive(this)
  }

  GlobeController.prototype.timelineToggle = function() {
    if (!this._timelineActive) return
    this._timelinePlaying = !this._timelinePlaying
    if (this.hasTimelinePlayBtnTarget) this.timelinePlayBtnTarget.classList.toggle("playing", this._timelinePlaying)
    if (this.hasTimelinePlayIconTarget) this.timelinePlayIconTarget.className = this._timelinePlaying ? "fa-solid fa-pause" : "fa-solid fa-play"

    if (this._timelinePlaying) {
      this._timelineLastTick = performance.now()
      this._startTimelinePlaybackRefreshLoop()
      this._timelineTick()
    } else if (this._timelineRaf) {
      cancelAnimationFrame(this._timelineRaf)
      this._stopTimelinePlaybackRefreshLoop()
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
    syncTimelineScrubber(this)
    updateTimelineCursorDisplay(this)
    this._renderNearestFrame()
    this._timelineRenderCachedState?.()
    debounceTimelineRefresh(this)

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
    updateTimelineCursorDisplay(this)
    this._renderNearestFrame()
    this._timelineRenderCachedState?.()
    debounceTimelineRefresh(this)
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
    if (this._timelinePulseRaf) cancelAnimationFrame(this._timelinePulseRaf)
    if (this._timelineEventTimer) clearTimeout(this._timelineEventTimer)
    this._stopTimelinePlaybackRefreshLoop()
    this.timelineBarTarget.style.display = "none"

    resetTimelineState(this)
    this._ds["timeline"]?.entities.removeAll()
    this._ds["timelineEvents"]?.entities.removeAll()

    this._lastConflictPulseBucket = null
    this._clearConflictPulseEntities?.()
    revertAutoEnabledPlaybackLayers(this)
    clearTimelineLiveEntities(this)
    if (this.flightData) this.flightData.clear()
    if (this.shipData) this.shipData.clear()
    resumeTimelineLive(this)
    this._syncQuickBar?.()
    this._updateStats?.()
  }

  GlobeController.prototype._syncScrubberToCursor = function() {
    syncTimelineScrubber(this)
  }

  GlobeController.prototype._updateTimelineCursorDisplay = function() {
    updateTimelineCursorDisplay(this)
  }

  GlobeController.prototype._timelineEventDebounce = function() {
    debounceTimelineRefresh(this)
  }

  GlobeController.prototype._timelineRefreshPlaybackState = async function() {
    if (this._timelineRefreshPromise) return this._timelineRefreshPromise

    this._timelineRefreshPromise = (async () => {
      const eventCount = await this._timelineUpdateEvents()
      const situationCount = await this._timelineUpdateConflictPulse()
      await this._timelineRefreshCursorLayers()
      return { eventCount, situationCount }
    })()

    try {
      return await this._timelineRefreshPromise
    } finally {
      this._timelineRefreshPromise = null
    }
  }

  GlobeController.prototype._startTimelinePlaybackRefreshLoop = function() {}

  GlobeController.prototype._stopTimelinePlaybackRefreshLoop = function() {
    if (!this._timelinePlaybackRefreshInterval) return
    clearInterval(this._timelinePlaybackRefreshInterval)
    this._timelinePlaybackRefreshInterval = null
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
    updateTimelineCursorDisplay(this)
    syncTimelineScrubber(this)

    this._toast("Loading time travel data...")
    const frameStatus = await this._timelineLoadFrames()
    const { eventCount, situationCount } = await this._timelineRefreshPlaybackState()

    showTimelineAvailabilityToast(this, frameStatus, eventCount, situationCount, false)
  }

  GlobeController.prototype._timelineOnLayerToggle = function() {
    if (!this._timelineActive) return
    if (this._timelineLayerReloadTimer) clearTimeout(this._timelineLayerReloadTimer)
    this._timelineLayerReloadTimer = setTimeout(async () => {
      await this._timelineLoadFrames()
      this._renderNearestFrame()
      await this._timelineRefreshPlaybackState()
    }, 300)
  }

  GlobeController.prototype._timelineRefreshCursorLayers = async function() {
    await refreshTimelineCursorLayers(this)
  }
}

function stepTimeline(direction) {
  if (!this._timelineActive || this._timelineKeys.length === 0) return
  this._timelineFrameIndex = Math.max(0, Math.min(this._timelineKeys.length - 1, this._timelineFrameIndex + direction))
  const key = this._timelineKeys[this._timelineFrameIndex]
  if (!key) return
  this._timelineCursor = new Date(key)
  syncTimelineScrubber(this)
  updateTimelineCursorDisplay(this)
  this._renderTimelineFrame(this._timelineFrameIndex)
  debounceTimelineRefresh(this)
}
