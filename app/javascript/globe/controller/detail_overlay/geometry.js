import {
  clamp,
  clampRectPosition,
  firstPresent,
  nearFarScaleValue,
  propertyValue,
  toNumber,
  validPoint,
} from "globe/controller/detail_overlay/shared"

export function applyDetailOverlayGeometryMethods(GlobeController) {
  GlobeController.prototype._anchoredDetailScaleBounds = function(state) {
    switch (state?.kind) {
      case "strike":
      case "geoconfirmed":
        return { nearHeight: 120000, farHeight: 6500000, minScale: 0.76 }
      case "conflict_pulse":
      case "strategic_situation":
        return { nearHeight: 180000, farHeight: 6500000, minScale: 0.76 }
      default:
        return { nearHeight: 140000, farHeight: 5000000, minScale: 0.68 }
    }
  }

  GlobeController.prototype._anchoredDetailScale = function(state) {
    const height = toNumber(this.viewer?.camera?.positionCartographic?.height)
    if (!(height > 0)) return 1

    const { nearHeight, farHeight, minScale } = this._anchoredDetailScaleBounds(state)
    const nearLog = Math.log10(Math.max(1, nearHeight))
    const farLog = Math.log10(Math.max(nearHeight + 1, farHeight))
    const heightLog = Math.log10(Math.max(1, height))
    const progress = clamp((heightLog - nearLog) / Math.max(0.0001, farLog - nearLog), 0, 1)
    return Number((1 - (1 - minScale) * progress).toFixed(3))
  }

  GlobeController.prototype._applyAnchoredDetailScale = function(panel, state, options = {}) {
    if (!panel) return 1

    const scale = options.mobile ? 1 : this._anchoredDetailScale(state)
    panel.style.setProperty("--anchor-panel-scale", `${scale}`)
    return scale
  }

  GlobeController.prototype._anchoredDetailAllowsExtendedBounds = function(state) {
    return ["geoconfirmed", "strike"].includes(state?.kind)
  }

  GlobeController.prototype._anchoredDetailOffscreenGraceMs = function() {
    return 180
  }

  GlobeController.prototype._anchoredDetailPlacementTolerance = function(state) {
    if (state?.kind === "geoconfirmed") {
      return {
        maxHorizontalDrift: 48,
        maxVerticalDrift: 72,
        maxPlacementDrift: 300,
        maxJoinDistance: 320,
      }
    }

    return {
      maxHorizontalDrift: 28,
      maxVerticalDrift: 20,
      maxPlacementDrift: 140,
      maxJoinDistance: 168,
    }
  }

  GlobeController.prototype._anchoredDetailFallbackPlacement = function(panelWidth, panelHeight, point = null) {
    const preferredLeft = point ? point.x - panelWidth / 2 : window.innerWidth - panelWidth - 24
    const preferredTop = point ? point.y - panelHeight - 36 : 72

    return {
      left: clamp(preferredLeft, 14, Math.max(14, window.innerWidth - panelWidth - 14)),
      top: clamp(preferredTop, 54, Math.max(54, window.innerHeight - panelHeight - 56)),
      vertical: "above",
      drift: 0,
    }
  }

  GlobeController.prototype._anchoredDetailAnchorVisible = function(anchor, point) {
    if (!point) return false

    const topSafe = 46
    const bottomSafe = 52
    const sideSafe = 8
    if (point.x < sideSafe || point.x > window.innerWidth - sideSafe) return false
    if (point.y < topSafe || point.y > window.innerHeight - bottomSafe) return false

    const lat = toNumber(anchor?.lat ?? anchor?.latitude)
    const lng = toNumber(anchor?.lng ?? anchor?.longitude)
    if (lat != null && lng != null && this._isPointVisibleOnGlobe?.(lat, lng) === false) return false

    return true
  }

  GlobeController.prototype._anchoredDetailPlacement = function(point, panelWidth, panelHeight, options = {}) {
    const bounds = {
      left: 14,
      right: window.innerWidth - 14,
      top: 54,
      bottom: window.innerHeight - 56,
    }
    const gapY = 36
    const maxHorizontalDrift = options.maxHorizontalDrift ?? 28
    const maxVerticalDrift = options.maxVerticalDrift ?? 20
    const candidates = [
      { left: point.x - panelWidth / 2, top: point.y - panelHeight - gapY, vertical: "above" },
      { left: point.x - panelWidth / 2, top: point.y + gapY, vertical: "below" },
    ]

    for (const candidate of candidates) {
      const clamped = clampRectPosition(candidate.left, candidate.top, panelWidth, panelHeight, bounds)
      const driftX = Math.abs(clamped.left - candidate.left)
      const driftY = Math.abs(clamped.top - candidate.top)
      if (driftX > maxHorizontalDrift || driftY > maxVerticalDrift) continue

      return {
        ...candidate,
        left: clamped.left,
        top: clamped.top,
        drift: driftX + driftY,
      }
    }

    return null
  }

  GlobeController.prototype._anchoredDetailJoinPoint = function(point, placement, panelWidth, panelHeight) {
    const left = placement.left
    const top = placement.top
    const right = left + panelWidth
    const bottom = top + panelHeight

    if (placement.vertical === "above") {
      return { x: clamp(point.x, left + 24, right - 24), y: bottom }
    }
    return { x: clamp(point.x, left + 24, right - 24), y: top }
  }

  GlobeController.prototype._anchoredDetailOriginPoint = function(point, join, markerRadius = 0, overlap = 0) {
    if (!point || !join) return point
    if (!(markerRadius > 0)) return point

    const dx = join.x - point.x
    const dy = join.y - point.y
    const distance = Math.hypot(dx, dy)
    if (!Number.isFinite(distance) || distance <= 1) return point

    const offset = Math.min(Math.max(0, markerRadius - overlap), Math.max(0, distance - 1))
    return {
      x: point.x + (dx / distance) * offset,
      y: point.y + (dy / distance) * offset,
    }
  }

  GlobeController.prototype._anchoredDetailSocketCenter = function(point, join, markerRadius = 0, socketRadius = 0, overlap = 0) {
    if (!point || !join) return point
    if (!(socketRadius > 0)) return this._anchoredDetailOriginPoint(point, join, markerRadius, overlap)

    const dx = join.x - point.x
    const dy = join.y - point.y
    const distance = Math.hypot(dx, dy)
    if (!Number.isFinite(distance) || distance <= 1) return point

    const edgeOffset = Math.max(0, markerRadius + socketRadius * 0.92)
    const offset = Math.min(Math.max(0, edgeOffset), Math.max(0, distance - 1))
    return {
      x: point.x + (dx / distance) * offset,
      y: point.y + (dy / distance) * offset,
    }
  }

  GlobeController.prototype._anchoredDetailConnectorOrigin = function(state, point, join, markerRadius = 0, socketRadius = 0) {
    if (!point || !join) return point

    if (state?.kind === "strike" || state?.kind === "geoconfirmed") {
      return point
    }

    return this._anchoredDetailSocketCenter(
      point,
      join,
      markerRadius,
      socketRadius,
      this._anchoredDetailMarkerOverlap(state)
    )
  }

  GlobeController.prototype._anchoredDetailLiveMarkerRadius = function(state) {
    const fallback = state?.markerRadius || 0
    const entity = state?.anchor?.entity
    const billboard = entity?.billboard
    const Cesium = window.Cesium
    if (!billboard || !Cesium || !this.viewer?.camera) return fallback

    const currentTime = this.viewer.clock?.currentTime
    const width = toNumber(propertyValue(billboard.width, currentTime))
    const height = toNumber(propertyValue(billboard.height, currentTime))
    if (!(width > 0) || !(height > 0)) return fallback

    const scale = toNumber(propertyValue(billboard.scale, currentTime)) || 1
    const scaleByDistance = propertyValue(billboard.scaleByDistance, currentTime)

    let distanceScale = 1
    const cartesian = entity.position?.getValue?.(currentTime)
    if (cartesian && this.viewer.camera.positionWC) {
      const distance = Cesium.Cartesian3.distance(this.viewer.camera.positionWC, cartesian)
      distanceScale = nearFarScaleValue(scaleByDistance, distance)
    }

    const displayedSize = Math.min(width, height) * scale * distanceScale
    if (!(displayedSize > 0)) return fallback

    if (state.kind === "conflict_pulse") {
      return displayedSize * 0.34 + 3
    }

    const factor = state.kind === "strategic_situation"
      ? 0.4
      : 0.45

    return displayedSize * factor
  }

  GlobeController.prototype._anchoredDetailMarkerOverlap = function(state) {
    switch (state?.kind) {
      case "conflict_pulse":
        return 0
      case "strategic_situation":
        return 0
      default:
        return 1.5
    }
  }

  GlobeController.prototype._anchoredDetailSocketRadius = function(state) {
    switch (state?.kind) {
      case "conflict_pulse":
        return 0
      case "strategic_situation":
        return 0
      default:
        return 0
    }
  }

  GlobeController.prototype._refreshAnchoredDetailPosition = function(force = false) {
    if (!this._anchoredDetailState || !this.hasAnchorPanelTarget) return

    const panel = this.anchorPanelTarget
    const overlay = this.hasAnchorOverlayTarget ? this.anchorOverlayTarget : null
    const leader = this.hasAnchorLeaderTarget ? this.anchorLeaderTarget : null
    const leaderPath = this.hasAnchorLeaderPathTarget ? this.anchorLeaderPathTarget : null
    const leaderSocket = this.hasAnchorLeaderSocketTarget ? this.anchorLeaderSocketTarget : null
    const hideLeader = () => {
      if (leader) leader.style.display = "none"
      if (leaderPath) leaderPath.setAttribute("d", "")
      if (leaderSocket) {
        leaderSocket.style.display = "none"
        leaderSocket.setAttribute("r", "0")
      }
    }

    const mobile = window.innerWidth <= 960
    const state = this._anchoredDetailState
    const point = this._anchoredDetailScreenPoint(state.anchor)
    const anchorVisible = !!point && this._anchoredDetailAnchorVisible(state.anchor, point)

    if (anchorVisible && validPoint(point)) {
      state._lastScreenPoint = { x: point.x, y: point.y }
      state._offscreenSince = null
    } else {
      const now = this._anchoredDetailNow?.() || window.performance?.now?.() || Date.now()
      if (!Number.isFinite(state._offscreenSince)) state._offscreenSince = now
      panel.style.display = "none"
      hideLeader()
      if (now - state._offscreenSince >= this._anchoredDetailOffscreenGraceMs()) {
        this.closeAnchoredDetail?.({ force: true })
        return
      }

      return
    }

    if (overlay) overlay.style.display = ""
    panel.style.display = ""
    this._applyAnchoredDetailScale(panel, state, { mobile })

    if (mobile) {
      panel.dataset.mode = "docked"
      panel.style.left = ""
      panel.style.top = ""
      if (leader) leader.style.display = "none"
      if (leaderPath) leaderPath.setAttribute("d", "")
      if (leaderSocket) {
        leaderSocket.style.display = "none"
        leaderSocket.setAttribute("r", "0")
      }
      return
    }

    panel.dataset.mode = "anchored"
    panel.style.visibility = "hidden"
    panel.style.left = "0px"
    panel.style.top = "0px"
    const panelRect = panel.getBoundingClientRect()
    panel.style.visibility = ""

    const panelWidth = panelRect.width || 248
    const panelHeight = panelRect.height || 112
    const tolerance = this._anchoredDetailPlacementTolerance(state)
    let placement = anchorVisible ? this._anchoredDetailPlacement(point, panelWidth, panelHeight, tolerance) : null
    if (!placement || placement.drift > tolerance.maxPlacementDrift) {
      placement = state._lastPlacement || this._anchoredDetailFallbackPlacement(panelWidth, panelHeight, point || state._lastScreenPoint)
    }

    const left = placement.left
    const top = placement.top
    state._lastPlacement = { left, top, vertical: placement.vertical }

    panel.style.left = `${Math.round(left)}px`
    panel.style.top = `${Math.round(top)}px`
    panel.style.display = ""

    if (!leader || !leaderPath) return

    const join = this._anchoredDetailJoinPoint(point, placement, panelWidth, panelHeight)
    const liveMarkerRadius = this._anchoredDetailLiveMarkerRadius(state)
    const socketRadius = this._anchoredDetailSocketRadius(state)
    const origin = this._anchoredDetailConnectorOrigin(state, point, join, liveMarkerRadius, socketRadius)

    leader.style.display = ""
    const bendY = placement.vertical === "above" ? origin.y - 12 : origin.y + 12
    leaderPath.setAttribute("d", `M ${Math.round(origin.x)} ${Math.round(origin.y)} L ${Math.round(origin.x)} ${Math.round(bendY)} L ${Math.round(join.x)} ${Math.round(bendY)} L ${Math.round(join.x)} ${Math.round(join.y)}`)
    if (leaderSocket) {
      if (socketRadius > 0) {
        leaderSocket.style.display = ""
        leaderSocket.setAttribute("cx", `${Math.round(origin.x)}`)
        leaderSocket.setAttribute("cy", `${Math.round(origin.y)}`)
        leaderSocket.setAttribute("r", `${socketRadius}`)
      } else {
        leaderSocket.style.display = "none"
        leaderSocket.setAttribute("r", "0")
      }
    }
  }

  GlobeController.prototype._refreshPinnedAnchoredDetailPositions = function(force = false) {
    const pinnedStates = this._pinnedAnchoredDetails || []
    if (!pinnedStates.length) return

    const mobile = window.innerWidth <= 960

    pinnedStates.forEach(state => {
      const elements = this._ensurePinnedAnchoredDetailElements?.(state)
      if (!elements) return

      const panel = elements.panel
      const leader = elements.leader
      const leaderPath = elements.leaderPath
      const leaderSocket = elements.leaderSocket
      const wrapper = elements.wrapper

      const markHidden = () => {
        panel.style.display = "none"
        if (leader) leader.style.display = "none"
        if (leaderPath) leaderPath.setAttribute("d", "")
        if (leaderSocket) {
          leaderSocket.style.display = "none"
          leaderSocket.setAttribute("r", "0")
        }
      }

      if (!force && window.getComputedStyle(panel).display === "none" && !mobile) {
        // Continue anyway so off-screen pins can reappear when the camera moves back.
      }

      if (wrapper) wrapper.style.display = ""

      if (mobile) {
        markHidden()
        return
      }

      const point = this._anchoredDetailScreenPoint(state.anchor)
      const anchorVisible = !!point && this._anchoredDetailAnchorVisible(state.anchor, point)
      if (!anchorVisible) {
        markHidden()
        return
      }

      panel.dataset.mode = "anchored"
      this._applyAnchoredDetailScale(panel, state, { mobile })
      panel.style.visibility = "hidden"
      panel.style.left = "0px"
      panel.style.top = "0px"
      const panelRect = panel.getBoundingClientRect()
      panel.style.visibility = ""

      const panelWidth = panelRect.width || 248
      const panelHeight = panelRect.height || 112
      const tolerance = this._anchoredDetailPlacementTolerance(state)
      let placement = this._anchoredDetailPlacement(point, panelWidth, panelHeight, tolerance)
      if (!placement || placement.drift > tolerance.maxPlacementDrift) {
        placement = state._lastPlacement || this._anchoredDetailFallbackPlacement(panelWidth, panelHeight, point)
      }
      state._lastPlacement = { left: placement.left, top: placement.top, vertical: placement.vertical }

      const join = this._anchoredDetailJoinPoint(point, placement, panelWidth, panelHeight)
      const liveMarkerRadius = this._anchoredDetailLiveMarkerRadius(state)
      const socketRadius = this._anchoredDetailSocketRadius(state)
      const origin = this._anchoredDetailConnectorOrigin(state, point, join, liveMarkerRadius, socketRadius)

      panel.style.left = `${Math.round(placement.left)}px`
      panel.style.top = `${Math.round(placement.top)}px`
      panel.style.display = ""

      if (!leader || !leaderPath) return

      leader.style.display = ""
      const bendY = placement.vertical === "above" ? origin.y - 12 : origin.y + 12
      leaderPath.setAttribute("d", `M ${Math.round(origin.x)} ${Math.round(origin.y)} L ${Math.round(origin.x)} ${Math.round(bendY)} L ${Math.round(join.x)} ${Math.round(bendY)} L ${Math.round(join.x)} ${Math.round(join.y)}`)
      if (leaderSocket) {
        if (socketRadius > 0) {
          leaderSocket.style.display = ""
          leaderSocket.setAttribute("cx", `${Math.round(origin.x)}`)
          leaderSocket.setAttribute("cy", `${Math.round(origin.y)}`)
          leaderSocket.setAttribute("r", `${socketRadius}`)
        } else {
          leaderSocket.style.display = "none"
          leaderSocket.setAttribute("r", "0")
        }
      }
    })
  }

  GlobeController.prototype._anchoredDetailProjectCartesian = function(cartesian, Cesium) {
    if (!cartesian || !this.viewer?.scene) return null

    let coords = null

    try {
      coords = Cesium.SceneTransforms.wgs84ToWindowCoordinates(this.viewer.scene, cartesian)
    } catch {}

    if (!validPoint(coords) && typeof this.viewer.scene.cartesianToCanvasCoordinates === "function") {
      try {
        coords = this.viewer.scene.cartesianToCanvasCoordinates(cartesian)
      } catch {}
    }

    return validPoint(coords) ? { x: coords.x, y: coords.y } : null
  }

  GlobeController.prototype._anchoredDetailScreenPoint = function(anchor) {
    if (!anchor || !this.viewer?.scene || !window.Cesium) return null

    const Cesium = window.Cesium
    const currentTime = this.viewer.clock?.currentTime

    const projectEntity = () => {
      if (anchor.entity?.position?.getValue) {
        const cartesian = anchor.entity.position.getValue(currentTime)
        const projected = this._anchoredDetailProjectCartesian(cartesian, Cesium)
        if (projected) return projected
      }

      if (anchor.entity?.polyline?.positions?.getValue) {
        const positions = anchor.entity.polyline.positions.getValue(currentTime) || []
        const cartesian = positions[Math.floor(positions.length / 2)] || null
        const projected = this._anchoredDetailProjectCartesian(cartesian, Cesium)
        if (projected) return projected
      }

      return null
    }

    const projectGeo = () => {
      const lng = toNumber(anchor.lng ?? anchor.longitude)
      const lat = toNumber(anchor.lat ?? anchor.latitude)
      const alt = toNumber(anchor.alt ?? anchor.height) || 0
      if (lat == null || lng == null) return null
      const cartesian = Cesium.Cartesian3.fromDegrees(lng, lat, alt)
      return this._anchoredDetailProjectCartesian(cartesian, Cesium)
    }

    const strategies = anchor.geoFirst ? [projectGeo, projectEntity] : [projectEntity, projectGeo]
    for (const project of strategies) {
      const point = project()
      if (point) return point
    }

    return null
  }

  GlobeController.prototype._anchoredDetailTimeLabel = function(value) {
    if (!value) return null

    const parsed = value instanceof Date ? value : new Date(value)
    if (Number.isNaN(parsed.getTime())) return null

    const year = parsed.getUTCFullYear()
    const month = (parsed.getUTCMonth() + 1).toString().padStart(2, "0")
    const day = parsed.getUTCDate().toString().padStart(2, "0")
    const hours = parsed.getUTCHours().toString().padStart(2, "0")
    const minutes = parsed.getUTCMinutes().toString().padStart(2, "0")
    return `${year}-${month}-${day} ${hours}:${minutes} UTC`
  }

  GlobeController.prototype._anchoredDetailAnchor = function(kind, data, options = {}) {
    const picked = options.picked
    const lat = toNumber(firstPresent(
      data?.lat,
      data?.latitude,
      data?.currentLat,
      data?.cell_lat,
      data?.center_lat,
      data?.position?.lat,
    ))
    const lng = toNumber(firstPresent(
      data?.lng,
      data?.longitude,
      data?.currentLng,
      data?.cell_lng,
      data?.center_lng,
      data?.position?.lng,
    ))

    const anchor = {
      entity: null,
      lat,
      lng,
      alt: lat != null && lng != null ? this._anchoredDetailDefaultAltitude(kind, data) : null,
      geoFirst: [
        "conflict_pulse",
        "strategic_situation",
        "hex_cell",
        "insight",
        "news",
        "news_arc",
        "strike",
        "conflict_event",
        "earthquake",
        "natural_event",
        "weather_alert",
        "outage",
        "chokepoint",
        "commodity",
        "fire_hotspot",
        "fire_cluster",
        "geoconfirmed",
      ].includes(kind),
    }

    if (picked?.id && (picked.id.position?.getValue || picked.id.polyline?.positions?.getValue)) {
      anchor.entity = picked.id
    }

    if (anchor.entity || (lat != null && lng != null)) return anchor
    return null
  }
}
