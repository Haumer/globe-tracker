import { getDataSource } from "globe/utils"

export function applyTimelineFrameMethods(GlobeController) {
  GlobeController.prototype._timelineLoadFrames = async function() {
    if (!this._timelineActive) return
    const from = this._timelineRangeStart.toISOString()
    const to = this._timelineRangeEnd.toISOString()

    this._timelineLastKnown = null
    this._timelineAppliedFrameIndex = -1
    this._ds["timeline"]?.entities.removeAll()

    const wantsFlightPlayback = this.flightsVisible || this._milFlightsActive
    const wantsShipPlayback = this.shipsVisible || this.navalVesselsVisible

    let playbackType = "all"
    if (wantsFlightPlayback && !wantsShipPlayback) playbackType = "flight"
    else if (wantsShipPlayback && !wantsFlightPlayback) playbackType = "ship"
    else if (!wantsFlightPlayback && !wantsShipPlayback) playbackType = "none"

    if (playbackType === "none") {
      this._timelineFrames = {}
      this._timelineKeys = []
      this._timelineFrameIndex = 0
      return { frameCount: 0, movementEnabled: false }
    }

    let url = `/api/playback?from=${from}&to=${to}&type=${playbackType}`
    const bounds = resolveTimelineBounds.call(this)
    if (bounds) {
      url += `&lamin=${bounds.lamin}&lamax=${bounds.lamax}&lomin=${bounds.lomin}&lomax=${bounds.lomax}`
    }

    try {
      const response = await fetch(url)
      if (!response.ok) throw new Error(`Timeline playback request failed with ${response.status}`)
      const data = await response.json()
      if (data?.error === "viewport_bounds_required") {
        this._timelineFrames = {}
        this._timelineKeys = []
        this._timelineFrameIndex = 0
        return { frameCount: 0, movementEnabled: false, boundsRequired: true }
      }
      syncTimelineRangeFromResponse.call(this, data)
      this._timelineFrames = data.frames || {}
      this._timelineKeys = Object.keys(this._timelineFrames).sort()
      this._timelineFrameIndex = 0
      this._timelineLastKnown = new Map()
      this._timelineAppliedFrameIndex = -1
      this._renderNearestFrame()
      return { frameCount: this._timelineKeys.length, movementEnabled: true }
    } catch (error) {
      console.error("Timeline frame load error:", error)
      return { frameCount: 0, movementEnabled: true, error: true }
    }
  }

  GlobeController.prototype._renderNearestFrame = function() {
    if (this._timelineKeys.length === 0) {
      this._renderTimelineFrame(-1)
      return
    }

    const cursorIso = this._timelineCursor.toISOString()
    let low = 0
    let high = this._timelineKeys.length - 1

    while (low < high) {
      const mid = ((low + high + 1) >> 1)
      if (this._timelineKeys[mid] <= cursorIso) low = mid
      else high = mid - 1
    }

    if (this._timelineKeys[low] > cursorIso) {
      this._timelineFrameIndex = -1
      this._renderTimelineFrame(-1)
      return
    }

    this._timelineFrameIndex = low
    this._renderTimelineFrame(low)
  }

  GlobeController.prototype._renderTimelineFrame = function(index) {
    const Cesium = window.Cesium
    const dataSource = getDataSource(this.viewer, this._ds, "timeline")
    if (index < 0) {
      this._timelineLastKnown = new Map()
      this._timelineAppliedFrameIndex = -1
      dataSource.entities.removeAll()
      this._requestRender()
      return
    }

    const key = this._timelineKeys[index]
    if (!key) return

    const cursorMs = this._timelineCursor ? this._timelineCursor.getTime() : new Date(key).getTime()
    applyTimelineFramesThrough.call(this, index)
    const activeIds = new Set()
    const hasFilter = this.hasActiveFilter()

    this._timelineLastKnown.forEach((entity, entityKey) => {
      const ageSinceSnapshot = cursorMs - entity.seenAt
      const staleMs = timelineEntityStaleMs(entity.type)
      if (ageSinceSnapshot < 0 || ageSinceSnapshot > staleMs) {
        this._timelineLastKnown.delete(entityKey)
        return
      }

      if (hasFilter && !this.pointPassesFilter(entity.lat, entity.lng)) return

      const isFlight = entity.type === "flight"
      if (!timelineEntityVisible(this, entity)) return

      const isMilitaryFlight = isFlight && timelineEntityIsMilitaryFlight(this, entity)
      const isNavalVessel = entity.type === "ship" && timelineEntityIsNavalVessel(entity)
      const visibilityAlpha = timelineEntityVisibilityAlpha(ageSinceSnapshot, staleMs)
      const labelColor = isFlight
        ? (isMilitaryFlight ? `rgba(239,83,80,${Math.max(visibilityAlpha, 0.28)})` : `rgba(200,210,225,${Math.max(visibilityAlpha, 0.24)})`)
        : (isNavalVessel ? `rgba(66,165,245,${Math.max(visibilityAlpha, 0.28)})` : `rgba(38,198,218,${Math.max(visibilityAlpha, 0.24)})`)
      const id = `tl-${entity.type}-${entity.id}`
      activeIds.add(id)
      const position = Cesium.Cartesian3.fromDegrees(entity.lng, entity.lat, (entity.alt || 0) + 100)
      let timelineEntity = dataSource.entities.getById(id)

      if (timelineEntity) {
        timelineEntity.position = position
        timelineEntity.billboard.rotation = -Cesium.Math.toRadians(entity.hdg || 0)
        timelineEntity.billboard.image = timelineBillboardImage(this, entity, { isMilitaryFlight, isNavalVessel })
        timelineEntity.billboard.color = Cesium.Color.WHITE.withAlpha(visibilityAlpha)
        if (timelineEntity.label) timelineEntity.label.text = entity.callsign || entity.id
        if (timelineEntity.label) timelineEntity.label.fillColor = Cesium.Color.fromCssColorString(labelColor)
      } else {
        timelineEntity = dataSource.entities.add({
          id,
          position,
          billboard: {
            image: timelineBillboardImage(this, entity, { isMilitaryFlight, isNavalVessel }),
            scale: isFlight ? 1.0 : 0.8,
            rotation: -Cesium.Math.toRadians(entity.hdg || 0),
            color: Cesium.Color.WHITE.withAlpha(visibilityAlpha),
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            heightReference: Cesium.HeightReference.NONE,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
          label: {
            text: entity.callsign || entity.id,
            font: "12px JetBrains Mono, monospace",
            fillColor: Cesium.Color.fromCssColorString(labelColor),
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

    const toRemove = []
    for (let index = 0; index < dataSource.entities.values.length; index++) {
      const entity = dataSource.entities.values[index]
      if (!activeIds.has(entity.id)) toRemove.push(entity)
    }
    toRemove.forEach(entity => dataSource.entities.remove(entity))
    this._requestRender()
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

  GlobeController.prototype._timelineNavalShipIcon = function() {
    if (this._cachedTimelineNavalShipIcon) return this._cachedTimelineNavalShipIcon
    const canvas = document.createElement("canvas")
    canvas.width = 20
    canvas.height = 20
    const ctx = canvas.getContext("2d")
    ctx.fillStyle = "#42a5f5"
    ctx.beginPath()
    ctx.moveTo(10, 2)
    ctx.lineTo(16, 16)
    ctx.lineTo(10, 13)
    ctx.lineTo(4, 16)
    ctx.closePath()
    ctx.fill()
    ctx.strokeStyle = "#bbdefb"
    ctx.lineWidth = 1
    ctx.stroke()
    this._cachedTimelineNavalShipIcon = canvas.toDataURL()
    return this._cachedTimelineNavalShipIcon
  }

  GlobeController.prototype._fmtTimelineDateTime = function(dateOrStr) {
    const date = typeof dateOrStr === "string" ? new Date(dateOrStr) : dateOrStr
    if (!date || isNaN(date)) return "--"
    const month = String(date.getUTCMonth() + 1).padStart(2, "0")
    const day = String(date.getUTCDate()).padStart(2, "0")
    const hours = String(date.getUTCHours()).padStart(2, "0")
    const minutes = String(date.getUTCMinutes()).padStart(2, "0")
    return `${month}-${day} ${hours}:${minutes}`
  }
}

function applyTimelineFramesThrough(index) {
  if (!this._timelineLastKnown || index < this._timelineAppliedFrameIndex) {
    this._timelineLastKnown = new Map()
    this._timelineAppliedFrameIndex = -1
  }

  for (let frameIndex = this._timelineAppliedFrameIndex + 1; frameIndex <= index; frameIndex++) {
    const frameKey = this._timelineKeys[frameIndex]
    const frameTimeMs = new Date(frameKey).getTime()
    const frameEntities = this._timelineFrames[frameKey] || []

    frameEntities.forEach(entity => {
      this._timelineLastKnown.set(`${entity.type}-${entity.id}`, {
        ...entity,
        seenAt: frameTimeMs,
      })
    })
  }

  this._timelineAppliedFrameIndex = index
}

function timelineEntityStaleMs(entityType) {
  return entityType === "ship" ? 6 * 60 * 60 * 1000 : 30 * 60 * 1000
}

function timelineEntityVisibilityAlpha(ageMs, staleMs) {
  if (!(staleMs > 0)) return 1
  const progress = Math.min(Math.max(ageMs / staleMs, 0), 1)
  return 0.18 + (1 - progress) * 0.82
}

function timelineEntityVisible(controller, entity) {
  if (entity.type === "flight") {
    const isMilitary = timelineEntityIsMilitaryFlight(controller, entity)
    return isMilitary ? !!controller._milFlightsActive : !!controller.flightsVisible
  }

  if (entity.type === "ship") {
    const isNaval = timelineEntityIsNavalVessel(entity)
    return isNaval ? !!controller.navalVesselsVisible : !!controller.shipsVisible
  }

  return true
}

function timelineEntityIsMilitaryFlight(controller, entity) {
  const milFlag = entity?.x?.mil === 1 || entity?.x?.mil === true
  return controller._isMilitaryFlight?.({
    id: entity.id,
    callsign: entity.callsign,
    military: milFlag,
  }) || false
}

function timelineEntityIsNavalVessel(entity) {
  const shipType = Number(entity?.x?.ship_type)
  return shipType === 35 || shipType === 55
}

function timelineBillboardImage(controller, entity, { isMilitaryFlight, isNavalVessel }) {
  if (entity.type === "flight") {
    if (entity.gnd) return controller.planeIconGround
    return isMilitaryFlight ? controller.planeIconMil : controller.planeIcon
  }

  return isNavalVessel ? controller._timelineNavalShipIcon() : controller._timelineShipIcon()
}

function resolveTimelineBounds() {
  if (this.hasActiveFilter()) {
    const bounds = this.getFilterBounds()
    if (bounds) this._timelinePlaybackBounds = bounds
    return bounds
  }
  return null
}

function syncTimelineRangeFromResponse(data) {
  const from = data?.from ? new Date(data.from) : null
  const to = data?.to ? new Date(data.to) : null
  if (!from || !to || isNaN(from) || isNaN(to)) return

  this._timelineRangeStart = from
  this._timelineRangeEnd = to
  if (!this._timelineCursor || this._timelineCursor < from || this._timelineCursor > to) {
    this._timelineCursor = new Date(from.getTime())
  }

  this.timelineTimeStartTarget.textContent = this._fmtTimelineDateTime(from)
  this.timelineTimeEndTarget.textContent = this._fmtTimelineDateTime(to)
  this._updateTimelineCursorDisplay()
  this._syncScrubberToCursor()
}
