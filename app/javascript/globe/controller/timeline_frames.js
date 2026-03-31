import { getViewportBounds } from "../camera"
import { getDataSource } from "../utils"

export function applyTimelineFrameMethods(GlobeController) {
  GlobeController.prototype._timelineLoadFrames = async function() {
    if (!this._timelineActive) return
    const from = this._timelineRangeStart.toISOString()
    const to = this._timelineRangeEnd.toISOString()

    this._timelineLastKnown = null
    this._ds["timeline"]?.entities.removeAll()

    let playbackType = "all"
    if (this.flightsVisible && !this.shipsVisible) playbackType = "flight"
    else if (this.shipsVisible && !this.flightsVisible) playbackType = "ship"
    else if (!this.flightsVisible && !this.shipsVisible) playbackType = "none"

    if (playbackType === "none") {
      this._timelineFrames = {}
      this._timelineKeys = []
      this._timelineFrameIndex = 0
      return { frameCount: 0, movementEnabled: false }
    }

    let url = `/api/playback?from=${from}&to=${to}&type=${playbackType}`
    const bounds = this.hasActiveFilter() ? this.getFilterBounds() : getViewportBounds(this.viewer)
    if (bounds) {
      url += `&lamin=${bounds.lamin}&lamax=${bounds.lamax}&lomin=${bounds.lomin}&lomax=${bounds.lomax}`
    }

    try {
      const response = await fetch(url)
      const data = await response.json()
      syncTimelineRangeFromResponse.call(this, data)
      this._timelineFrames = data.frames || {}
      this._timelineKeys = Object.keys(this._timelineFrames).sort()
      this._timelineFrameIndex = 0
      if (this._timelineKeys.length > 0) this._renderTimelineFrame(0)
      return { frameCount: this._timelineKeys.length, movementEnabled: true }
    } catch (error) {
      console.error("Timeline frame load error:", error)
      return { frameCount: 0, movementEnabled: true, error: true }
    }
  }

  GlobeController.prototype._renderNearestFrame = function() {
    if (this._timelineKeys.length === 0) return
    const cursorIso = this._timelineCursor.toISOString()
    let low = 0
    let high = this._timelineKeys.length - 1

    while (low < high) {
      const mid = (low + high) >> 1
      if (this._timelineKeys[mid] < cursorIso) low = mid + 1
      else high = mid
    }

    if (low > 0) {
      const prev = new Date(this._timelineKeys[low - 1]).getTime()
      const current = new Date(this._timelineKeys[low]).getTime()
      const target = this._timelineCursor.getTime()
      if (Math.abs(target - prev) < Math.abs(target - current)) low -= 1
    }

    this._timelineFrameIndex = low
    this._renderTimelineFrame(low)
  }

  GlobeController.prototype._renderTimelineFrame = function(index) {
    const Cesium = window.Cesium
    const key = this._timelineKeys[index]
    if (!key) return

    const frameEntities = this._timelineFrames[key] || []
    const cursorMs = this._timelineCursor ? this._timelineCursor.getTime() : new Date(key).getTime()
    if (!this._timelineLastKnown) this._timelineLastKnown = new Map()

    frameEntities.forEach(entity => {
      this._timelineLastKnown.set(`${entity.type}-${entity.id}`, {
        ...entity,
        seenAt: cursorMs,
      })
    })

    const nextKey = this._timelineKeys[index + 1]
    const nextMap = new Map()
    if (nextKey) {
      ;(this._timelineFrames[nextKey] || []).forEach(entity => nextMap.set(`${entity.type}-${entity.id}`, entity))
    }

    const dataSource = getDataSource(this.viewer, this._ds, "timeline")
    const activeIds = new Set()
    const hasFilter = this.hasActiveFilter()
    const maxStaleMs = 120000

    this._timelineLastKnown.forEach((entity, entityKey) => {
      const ageSinceSnapshot = cursorMs - entity.seenAt
      if (ageSinceSnapshot > maxStaleMs) {
        this._timelineLastKnown.delete(entityKey)
        return
      }

      const state = projectTimelineEntity.call(this, entity, entityKey, nextKey, nextMap, cursorMs)
      if (hasFilter && !this.pointPassesFilter(state.lat, state.lng)) return

      const isFlight = entity.type === "flight"
      const id = `tl-${entity.type}-${entity.id}`
      activeIds.add(id)
      const position = Cesium.Cartesian3.fromDegrees(state.lng, state.lat, state.alt + 100)
      let timelineEntity = dataSource.entities.getById(id)

      if (timelineEntity) {
        timelineEntity.position = position
        timelineEntity.billboard.rotation = -Cesium.Math.toRadians(state.hdg)
        if (timelineEntity.label) timelineEntity.label.text = entity.callsign || entity.id
      } else {
        timelineEntity = dataSource.entities.add({
          id,
          position,
          billboard: {
            image: isFlight ? (entity.gnd ? this.planeIconGround : this.planeIcon) : this._timelineShipIcon(),
            scale: isFlight ? 1.0 : 0.8,
            rotation: -Cesium.Math.toRadians(state.hdg),
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            heightReference: Cesium.HeightReference.NONE,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
          label: {
            text: entity.callsign || entity.id,
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

    const toRemove = []
    for (let index = 0; index < dataSource.entities.values.length; index++) {
      const entity = dataSource.entities.values[index]
      if (!activeIds.has(entity.id)) toRemove.push(entity)
    }
    toRemove.forEach(entity => dataSource.entities.remove(entity))
    this._requestRender()
  }

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
    const date = typeof dateOrStr === "string" ? new Date(dateOrStr) : dateOrStr
    if (!date || isNaN(date)) return "--"
    const month = String(date.getUTCMonth() + 1).padStart(2, "0")
    const day = String(date.getUTCDate()).padStart(2, "0")
    const hours = String(date.getUTCHours()).padStart(2, "0")
    const minutes = String(date.getUTCMinutes()).padStart(2, "0")
    return `${month}-${day} ${hours}:${minutes}`
  }
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

function projectTimelineEntity(entity, entityKey, nextKey, nextMap, cursorMs) {
  let lat = entity.lat
  let lng = entity.lng
  let alt = entity.alt || 0
  let hdg = entity.hdg || 0
  const next = nextMap.get(entityKey)

  if (next && nextKey) {
    const nextMs = new Date(nextKey).getTime()
    const spanMs = nextMs - entity.seenAt
    if (spanMs > 0) {
      const t = Math.max(0, Math.min(1, (cursorMs - entity.seenAt) / spanMs))
      lat = entity.lat + (next.lat - entity.lat) * t
      lng = entity.lng + (next.lng - entity.lng) * t
      alt = (entity.alt || 0) + ((next.alt || 0) - (entity.alt || 0)) * t
      hdg = this._lerpAngle(entity.hdg || 0, next.hdg || 0, t)
    }
  } else if (cursorMs > entity.seenAt && entity.spd > 0) {
    const dt = (cursorMs - entity.seenAt) / 1000
    const dLat = (entity.spd * Math.cos((entity.hdg || 0) * Math.PI / 180) * dt) / 111320
    const dLng = (entity.spd * Math.sin((entity.hdg || 0) * Math.PI / 180) * dt) / (111320 * Math.cos(entity.lat * Math.PI / 180))
    lat += dLat
    lng += dLng
  }

  return { lat, lng, alt, hdg }
}
