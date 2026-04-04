function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function firstPresent(...values) {
  return values.find(value => {
    if (value == null) return false
    if (typeof value === "number") return !Number.isNaN(value)
    return `${value}`.trim() !== ""
  })
}

function toNumber(value) {
  if (value == null || value === "") return null
  const parsed = typeof value === "number" ? value : parseFloat(value)
  return Number.isFinite(parsed) ? parsed : null
}

function validPoint(value) {
  return !!value && Number.isFinite(value.x) && Number.isFinite(value.y)
}

function clampRectPosition(left, top, width, height, bounds) {
  return {
    left: clamp(left, bounds.left, bounds.right - width),
    top: clamp(top, bounds.top, bounds.bottom - height),
  }
}

function rectOverflowPenalty(left, top, width, height, bounds) {
  const overLeft = Math.max(0, bounds.left - left)
  const overRight = Math.max(0, left + width - bounds.right)
  const overTop = Math.max(0, bounds.top - top)
  const overBottom = Math.max(0, top + height - bounds.bottom)
  return overLeft + overRight + overTop + overBottom
}

function pointDistance(a, b) {
  if (!a || !b) return Number.POSITIVE_INFINITY
  return Math.hypot(a.x - b.x, a.y - b.y)
}

function compactFacts(values, limit = 2) {
  return values.filter(value => value != null && `${value}`.trim() !== "").slice(0, limit)
}

function chip(label, tone = "neutral") {
  if (!label) return null
  return { label, tone }
}

function kindLabel(kind) {
  return (kind || "item").replace(/_/g, " ").replace(/\b\w/g, char => char.toUpperCase())
}

function upperLabel(value) {
  return value ? `${value}`.replace(/_/g, " ").toUpperCase() : null
}

function shortLine(value, maxLength = 96) {
  if (value == null) return null
  const normalized = `${value}`.replace(/\s+/g, " ").trim()
  if (!normalized) return null
  if (normalized.length <= maxLength) return normalized
  return `${normalized.slice(0, Math.max(0, maxLength - 1)).trimEnd()}\u2026`
}

function propertyValue(prop, currentTime) {
  if (prop == null) return null
  if (typeof prop.getValue === "function") {
    try {
      return prop.getValue(currentTime)
    } catch {
      return null
    }
  }
  return prop
}

function nearFarScaleValue(nearFar, distance) {
  if (!nearFar || !Number.isFinite(distance)) return 1
  const near = Number(nearFar.near)
  const nearValue = Number(nearFar.nearValue)
  const far = Number(nearFar.far)
  const farValue = Number(nearFar.farValue)
  if (![near, nearValue, far, farValue].every(Number.isFinite)) return 1
  if (distance <= near) return nearValue
  if (distance >= far) return farValue
  if (far <= near) return farValue
  const t = (distance - near) / (far - near)
  return nearValue + (farValue - nearValue) * t
}

function conflictPulseStroke(score) {
  if (score >= 70) return "#f44336"
  if (score >= 50) return "#ff9800"
  return "#ffc107"
}

export function applyDetailOverlayMethods(GlobeController) {
  GlobeController.prototype._showCompactEntityDetail = function(kind, data, options = {}) {
    const payload = this._buildAnchoredDetailPayload(kind, data, options)
    if (!payload) return false

    if (options.focusSelection) {
      this._focusedSelection = options.focusSelection
      this._renderSelectionTray?.()
    }

    if (this.hasDetailPanelTarget) {
      this.detailPanelTarget.style.display = "none"
    }

    this._showAnchoredDetail(payload)
    return true
  }

  GlobeController.prototype._showAnchoredDetail = function(payload) {
    if (!this.hasAnchorOverlayTarget || !this.hasAnchorPanelTarget || !this.hasAnchorContentTarget) return

    this._anchoredDetailState = {
      ...payload,
      hiddenSince: null,
    }
    const stroke = payload.stroke || payload.accent || "#8bd8ff"
    const strokeWidth = payload.strokeWidth || 2.25
    this.anchorOverlayTarget.style.display = ""
    this.anchorPanelTarget.style.display = ""
    this.anchorPanelTarget.dataset.mode = "anchored"
    this.anchorPanelTarget.dataset.kind = payload.kind || ""
    this.anchorOverlayTarget.style.setProperty("--anchor-accent", payload.accent || "#8bd8ff")
    this.anchorOverlayTarget.style.setProperty("--anchor-stroke", stroke)
    this.anchorOverlayTarget.style.setProperty("--anchor-border-width", `${strokeWidth}px`)
    this.anchorPanelTarget.style.setProperty("--anchor-accent", payload.accent || "#8bd8ff")
    this.anchorPanelTarget.style.setProperty("--anchor-stroke", stroke)
    this.anchorPanelTarget.style.setProperty("--anchor-border-width", `${strokeWidth}px`)
    this.anchorContentTarget.innerHTML = this._renderAnchoredDetailHtml(payload)

    this._refreshAnchoredDetailPosition(true)
    this._requestRender?.()
  }

  GlobeController.prototype.closeAnchoredDetail = function() {
    this._anchoredDetailState = null
    if (this.hasAnchorPanelTarget) {
      this.anchorPanelTarget.style.display = "none"
      this.anchorPanelTarget.style.left = ""
      this.anchorPanelTarget.style.top = ""
      this.anchorPanelTarget.dataset.mode = "anchored"
      delete this.anchorPanelTarget.dataset.kind
      this.anchorPanelTarget.style.removeProperty("--anchor-accent")
      this.anchorPanelTarget.style.removeProperty("--anchor-stroke")
      this.anchorPanelTarget.style.removeProperty("--anchor-border-width")
    }
    if (this.hasAnchorOverlayTarget) {
      this.anchorOverlayTarget.style.display = "none"
      this.anchorOverlayTarget.style.removeProperty("--anchor-accent")
      this.anchorOverlayTarget.style.removeProperty("--anchor-stroke")
      this.anchorOverlayTarget.style.removeProperty("--anchor-border-width")
    }
    if (this.hasAnchorLeaderTarget) {
      this.anchorLeaderTarget.style.display = "none"
    }
    if (this.hasAnchorLeaderPathTarget) {
      this.anchorLeaderPathTarget.setAttribute("d", "")
    }
    if (this.hasAnchorLeaderSocketTarget) {
      this.anchorLeaderSocketTarget.style.display = "none"
      this.anchorLeaderSocketTarget.setAttribute("r", "0")
    }
  }

  GlobeController.prototype._renderAnchoredDetailHtml = function(payload) {
    const chipsHtml = (payload.chips || [])
      .filter(Boolean)
      .slice(0, 2)
      .map(item => `<span class="anchor-chip anchor-chip--${this._escapeHtml(item.tone || "neutral")}">${this._escapeHtml(item.label)}</span>`)
      .join("")

    const subtitleHtml = payload.subtitle
      ? `<div class="anchor-subtitle">${this._escapeHtml(payload.subtitle)}</div>`
      : ""

    const briefHtml = payload.brief
      ? `<div class="anchor-brief">${this._escapeHtml(payload.brief)}</div>`
      : ""

    return `
      <div class="anchor-head">
        <div class="anchor-chip-row">${chipsHtml}</div>
        ${payload.timeLabel ? `<div class="anchor-time">${this._escapeHtml(payload.timeLabel)}</div>` : ""}
      </div>
      <div class="anchor-title">${this._escapeHtml(payload.title || kindLabel(payload.kind))}</div>
      ${subtitleHtml}
      ${briefHtml}
    `
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

  GlobeController.prototype._anchoredDetailPlacement = function(point, panelWidth, panelHeight) {
    const bounds = {
      left: 14,
      right: window.innerWidth - 14,
      top: 54,
      bottom: window.innerHeight - 56,
    }
    const gapY = 36
    const maxHorizontalDrift = 28
    const maxVerticalDrift = 20
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
    if (!force && window.getComputedStyle(this.anchorPanelTarget).display === "none") return

    const panel = this.anchorPanelTarget
    const overlay = this.hasAnchorOverlayTarget ? this.anchorOverlayTarget : null
    const leader = this.hasAnchorLeaderTarget ? this.anchorLeaderTarget : null
    const leaderPath = this.hasAnchorLeaderPathTarget ? this.anchorLeaderPathTarget : null
    const leaderSocket = this.hasAnchorLeaderSocketTarget ? this.anchorLeaderSocketTarget : null

    const mobile = window.innerWidth <= 960
    const state = this._anchoredDetailState
    const livePoint = this._anchoredDetailScreenPoint(state.anchor)
    const point = livePoint || null

    if (overlay) overlay.style.display = ""
    panel.style.display = ""

    const markHidden = () => {
      panel.style.display = "none"
      if (leader) leader.style.display = "none"
      if (leaderPath) leaderPath.setAttribute("d", "")
      if (leaderSocket) {
        leaderSocket.style.display = "none"
        leaderSocket.setAttribute("r", "0")
      }
    }

    if (mobile) {
      state.hiddenSince = null
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

    if (!point) {
      const now = performance.now()
      state.hiddenSince ||= now
      markHidden()
      if (now - state.hiddenSince > 220) {
        this.closeAnchoredDetail()
      }
      return
    }

    if (!this._anchoredDetailAnchorVisible(state.anchor, point)) {
      const now = performance.now()
      state.hiddenSince ||= now
      markHidden()
      if (now - state.hiddenSince > 220) {
        this.closeAnchoredDetail()
      }
      return
    }

    state.hiddenSince = null

    panel.dataset.mode = "anchored"
    panel.style.visibility = "hidden"
    panel.style.left = "0px"
    panel.style.top = "0px"
    const panelRect = panel.getBoundingClientRect()
    panel.style.visibility = ""

    const panelWidth = panelRect.width || 248
    const panelHeight = panelRect.height || 112
    const placement = this._anchoredDetailPlacement(point, panelWidth, panelHeight)
    if (!placement || placement.drift > 140) {
      const now = performance.now()
      state.hiddenSince ||= now
      markHidden()
      if (now - state.hiddenSince > 220) {
        this.closeAnchoredDetail()
      }
      return
    }

    const join = this._anchoredDetailJoinPoint(point, placement, panelWidth, panelHeight)
    const liveMarkerRadius = this._anchoredDetailLiveMarkerRadius(state)
    const socketRadius = this._anchoredDetailSocketRadius(state)
    const origin = this._anchoredDetailSocketCenter(
      point,
      join,
      liveMarkerRadius,
      socketRadius,
      this._anchoredDetailMarkerOverlap(state)
    )
    if (pointDistance(origin, join) > 168) {
      const now = performance.now()
      state.hiddenSince ||= now
      markHidden()
      if (now - state.hiddenSince > 220) {
        this.closeAnchoredDetail()
      }
      return
    }

    const left = placement.left
    const top = placement.top

    panel.style.left = `${Math.round(left)}px`
    panel.style.top = `${Math.round(top)}px`
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
  }

  GlobeController.prototype._anchoredDetailMarkerStroke = function(kind, data) {
    switch (kind) {
      case "conflict_pulse":
        return conflictPulseStroke(toNumber(data?.pulse_score) || 0)
      case "strategic_situation": {
        return {
          critical: "#ff7043",
          elevated: "#ffca28",
          monitoring: "#26c6da",
        }[data?.status] || "#26c6da"
      }
      case "insight":
        return { critical: "#f44336", high: "#ff9800", medium: "#ffc107", low: "#4caf50" }[data?.severity] || "#8bd8ff"
      default:
        return null
    }
  }

  GlobeController.prototype._anchoredDetailMarkerRadius = function(kind, data) {
    switch (kind) {
      case "conflict_pulse": {
        const score = toNumber(data?.pulse_score) || 0
        const iconSize = score >= 70 ? 48 : score >= 50 ? 44 : 36
        return Math.max(0, iconSize * 0.34 + 3)
      }
      case "strategic_situation":
        return data?.status === "critical" ? 12.5 : 11
      case "insight":
        return 13
      case "news":
        return 10
      case "chokepoint":
        return 12
      default:
        return 0
    }
  }

  GlobeController.prototype._anchoredDetailDefaultAltitude = function(kind, data) {
    const explicitAltitude = toNumber(firstPresent(
      data?.altitude,
      data?.alt,
      data?.height,
      data?.currentAlt,
      data?.elevation,
      data?.position?.alt,
    ))
    if (explicitAltitude != null) return explicitAltitude

    switch (kind) {
      case "conflict_pulse":
      case "strategic_situation":
      case "insight":
        return 5600
      case "hex_cell":
        return 5200
      case "news":
      case "news_arc":
      case "strike":
      case "conflict_event":
        return 3200
      case "earthquake":
      case "natural_event":
      case "weather_alert":
      case "outage":
      case "chokepoint":
      case "commodity":
        return 2400
      case "ship":
      case "naval_vessel":
      case "train":
      case "webcam":
        return 180
      case "satellite":
        return 25000
      default:
        return 1800
    }
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

    const hours = parsed.getUTCHours().toString().padStart(2, "0")
    const minutes = parsed.getUTCMinutes().toString().padStart(2, "0")
    return `${hours}:${minutes} UTC`
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
      ].includes(kind),
    }

    if (picked?.id && (picked.id.position?.getValue || picked.id.polyline?.positions?.getValue)) {
      anchor.entity = picked.id
    }

    if (anchor.entity || (lat != null && lng != null)) return anchor
    return null
  }

  GlobeController.prototype._buildAnchoredDetailPayload = function(kind, data, options = {}) {
    const anchor = this._anchoredDetailAnchor(kind, data, options)
    const timeLabel = this._anchoredDetailTimeLabel(
      firstPresent(
        data?.time,
        data?.published_at,
        data?.publishedAt,
        data?.event_time,
        data?.effective_start,
        data?.recorded_at,
        data?.updated_at,
        data?.fetched_at,
        data?.created_at,
      )
    )

    const genericTitle = firstPresent(data?.title, data?.name, data?.reason, data?.id, options.id, kindLabel(kind))
    const genericSubtitle = firstPresent(
      data?.location,
      data?.place,
      data?.country && data?.region ? `${data.country} · ${data.region}` : null,
      data?.country,
      data?.region,
      data?.publisher,
      data?.source,
      data?.category,
    )
    const genericFacts = compactFacts([
      firstPresent(data?.status, data?.type_label, data?.event_type, data?.ship_type, data?.severity),
      firstPresent(data?.code, data?.symbol, data?.publisher_name, data?.source),
    ])
    const genericBrief = shortLine(genericFacts.join(" · "))

    const markerStroke = this._anchoredDetailMarkerStroke(kind, data)
    const markerRadius = this._anchoredDetailMarkerRadius(kind, data)

    const makePayload = ({ title, subtitle, brief, facts = [], chips = [], accent, stroke, strokeWidth, timeLabel: payloadTimeLabel = timeLabel }) => ({
      kind,
      title: title || genericTitle,
      subtitle: shortLine(subtitle || genericSubtitle, 84),
      brief: shortLine(brief || compactFacts(facts.length ? facts : genericFacts).join(" · ") || genericBrief),
      facts: compactFacts(facts.length ? facts : genericFacts),
      chips: chips.filter(Boolean).slice(0, 2),
      timeLabel: payloadTimeLabel,
      accent: accent || "#8bd8ff",
      stroke: stroke || markerStroke || accent || "#8bd8ff",
      strokeWidth: strokeWidth || 2.25,
      markerRadius,
      anchor,
    })

    switch (kind) {
      case "flight": {
        const emergency = this._isEmergencyFlight?.(data)
        const altitude = toNumber(data?.currentAlt ?? data?.altitude)
        const speed = toNumber(data?.speed ?? data?.velocity)
        return makePayload({
          title: firstPresent(data?.callsign, options.id, data?.registration, "Flight"),
          subtitle: firstPresent(data?.originCountry, data?.registration, data?.aircraftType, "Airborne track"),
          facts: [
            altitude != null ? `${Math.round(altitude).toLocaleString()} m` : null,
            speed != null ? `${Math.round(speed * 3.6)} km/h` : null,
          ],
          chips: [
            chip(emergency ? "Emergency" : (kind === "flight" ? "Flight" : "Track"), emergency ? "critical" : "accent"),
            chip(data?.onGround ? "Ground" : "Airborne", "neutral"),
          ],
          accent: emergency ? "#ff9800" : "#4fc3f7",
        })
      }
      case "ship":
      case "naval_vessel": {
        const speed = toNumber(data?.speed)
        const shipType = this.getShipTypeName?.(data?.shipType)
        return makePayload({
          title: firstPresent(data?.name, data?.mmsi, "Vessel"),
          subtitle: firstPresent(data?.flag, shipType, "Maritime track"),
          facts: [
            speed != null ? `${speed.toFixed(1)} kn` : null,
            firstPresent(data?.destination, data?.mmsi ? `MMSI ${data.mmsi}` : null),
          ],
          chips: [
            chip(kind === "naval_vessel" ? "Naval" : "Ship", kind === "naval_vessel" ? "critical" : "accent"),
            shipType ? chip(shipType, "neutral") : null,
          ],
          accent: kind === "naval_vessel" ? "#ef5350" : "#26c6da",
        })
      }
      case "satellite": {
        return makePayload({
          title: firstPresent(data?.name, data?.norad_id ? `NORAD ${data.norad_id}` : null, "Satellite"),
          subtitle: firstPresent(data?.country, data?.operator, data?.category, "Orbital track"),
          facts: [
            firstPresent(data?.purpose, data?.orbit_type, data?.classification),
            data?.norad_id ? `NORAD ${data.norad_id}` : null,
          ],
          chips: [chip("Satellite", "accent")],
          accent: "#64b5f6",
        })
      }
      case "train": {
        const speed = toNumber(data?.speed_kph ?? data?.speed)
        return makePayload({
          title: firstPresent(data?.line_name, data?.name, data?.id, "Train"),
          subtitle: firstPresent(data?.operator, data?.route_name, data?.origin && data?.destination ? `${data.origin} → ${data.destination}` : null, "Rail service"),
          facts: [
            firstPresent(data?.status, data?.delay_minutes != null ? `${data.delay_minutes} min delay` : null),
            speed != null ? `${Math.round(speed)} km/h` : null,
          ],
          chips: [chip("Train", "accent")],
          accent: "#4fc3f7",
        })
      }
      case "airport": {
        return makePayload({
          title: firstPresent(data?.name, data?.icao || options.id, "Airport"),
          subtitle: firstPresent(data?.municipality && data?.country ? `${data.municipality}, ${data.country}` : null, data?.country, "Airport"),
          facts: [
            data?.icao ? `ICAO ${data.icao}` : options.id ? `ICAO ${options.id}` : null,
            firstPresent(data?.military ? "Military" : null, data?.type),
          ],
          chips: [chip(data?.military ? "Airbase" : "Airport", data?.military ? "critical" : "accent")],
          accent: data?.military ? "#ff7043" : "#ffd54f",
        })
      }
      case "earthquake": {
        const mag = toNumber(data?.mag ?? data?.magnitude)
        const depth = toNumber(data?.depth)
        return makePayload({
          title: mag != null ? `M${mag.toFixed(1)} Earthquake` : firstPresent(data?.title, "Earthquake"),
          subtitle: firstPresent(data?.title, data?.place, "Seismic event"),
          facts: [
            depth != null ? `${depth.toFixed(0)} km depth` : null,
            firstPresent(data?.source, "USGS"),
          ],
          chips: [
            chip(mag != null ? `M${mag.toFixed(1)}` : "Quake", mag >= 5 ? "critical" : mag >= 4 ? "warning" : "accent"),
            chip("Seismic", "neutral"),
          ],
          accent: mag >= 5 ? "#ef5350" : "#ff9800",
        })
      }
      case "natural_event": {
        return makePayload({
          title: firstPresent(data?.title, data?.name, "Natural event"),
          subtitle: firstPresent(data?.category_title, data?.category, data?.location, "Natural event"),
          facts: [
            firstPresent(data?.status, data?.source),
            data?.days ? `${data.days} days active` : null,
          ],
          chips: [chip(firstPresent(data?.category_title, data?.category, "Event"), "warning")],
          accent: "#ff7043",
        })
      }
      case "news": {
        const actors = Array.isArray(data?.actors) ? data.actors.map(actor => actor.name).filter(Boolean) : []
        const location = firstPresent(data?.name, data?.location, data?.place, data?.publisher, data?.origin_source, "Reported event")
        const claimType = data?.claim_event_type ? `${data.claim_event_type}`.replace(/_/g, " ") : null
        const verification = data?.claim_verification_status ? `${data.claim_verification_status}`.replace(/_/g, " ") : null
        return makePayload({
          title: firstPresent(data?.title, data?.name, "News signal"),
          subtitle: location,
          brief: compactFacts([
            firstPresent(claimType, actors.slice(0, 2).join(", ")),
            firstPresent(verification, data?.publisher, data?.source),
          ]).join(" · "),
          chips: [
            chip(firstPresent(data?.category, "News"), data?.threat === "high" ? "critical" : "accent"),
            chip(firstPresent(data?.claim_verification_status, data?.credibility), "neutral"),
          ],
          accent: data?.threat === "high" ? "#ef5350" : "#8bd8ff",
        })
      }
      case "news_arc": {
        return makePayload({
          title: firstPresent(data?.evtName && data?.srcCity ? `${data.srcCity} → ${data.evtName}` : null, data?.evtName, "News flow"),
          subtitle: data?.count ? `${data.count} linked articles` : "Media attention",
          facts: [
            firstPresent(data?.articles?.[0]?.domain, data?.articles?.[0]?.category),
            data?.count ? `${data.count} sources` : null,
          ],
          chips: [chip("News Flow", "warning")],
          accent: "#ffab40",
        })
      }
      case "outage": {
        return makePayload({
          title: firstPresent(data?.name, data?.code, "Internet outage"),
          subtitle: "Internet outage",
          facts: [
            data?.level ? `${`${data.level}`.toUpperCase()} severity` : null,
            data?.score != null ? `Score ${data.score}` : null,
          ],
          chips: [
            chip(firstPresent(data?.level, "Outage"), data?.level === "critical" || data?.level === "severe" ? "critical" : "warning"),
            data?.code ? chip(data.code, "neutral") : null,
          ],
          accent: data?.level === "critical" || data?.level === "severe" ? "#f44336" : "#ffc107",
        })
      }
      case "cable": {
        return makePayload({
          title: firstPresent(data?.name, "Submarine cable"),
          subtitle: "Submarine cable",
          facts: [firstPresent(data?.source, "TeleGeography")],
          chips: [chip("Cable", "accent")],
          accent: "#00bcd4",
        })
      }
      case "pipeline": {
        return makePayload({
          title: firstPresent(data?.name, "Pipeline"),
          subtitle: firstPresent(data?.country, data?.status, "Energy infrastructure"),
          facts: [
            firstPresent(data?.type, data?.status),
            data?.length_km ? `${data.length_km.toLocaleString()} km` : null,
          ],
          chips: [chip(firstPresent(data?.type, "Pipeline"), "warning")],
          accent: data?.color || "#ff6d00",
        })
      }
      case "webcam": {
        return makePayload({
          title: firstPresent(data?.title, "Webcam"),
          subtitle: firstPresent(data?.city && data?.country ? `${data.city}, ${data.country}` : null, data?.country, "Live camera"),
          facts: [firstPresent(data?.source, data?.channel_title), "Live feed"],
          chips: [chip("Camera", "accent")],
          accent: "#4fc3f7",
        })
      }
      case "military_base": {
        return makePayload({
          title: firstPresent(data?.name, "Military base"),
          subtitle: firstPresent(data?.country, data?.branch, "Military site"),
          facts: [firstPresent(data?.type, data?.service), firstPresent(data?.operator, data?.country_code)],
          chips: [chip("Military", "critical")],
          accent: "#ef5350",
        })
      }
      case "airbase": {
        return makePayload({
          title: firstPresent(data?.name, options.id, "Airbase"),
          subtitle: firstPresent(data?.municipality && data?.country ? `${data.municipality}, ${data.country}` : null, data?.country, "Military airbase"),
          facts: [
            options.id ? `ICAO ${options.id}` : null,
            firstPresent(data?.type, data?.elevation ? `${data.elevation} ft` : null),
          ],
          chips: [chip("Airbase", "critical")],
          accent: "#ff7043",
        })
      }
      case "power_plant": {
        return makePayload({
          title: firstPresent(data?.name, "Power plant"),
          subtitle: firstPresent(data?.country, data?.fuel, "Energy site"),
          facts: [
            data?.capacity_mw ? `${Math.round(data.capacity_mw).toLocaleString()} MW` : null,
            firstPresent(data?.fuel, data?.status),
          ],
          chips: [chip(firstPresent(data?.fuel, "Power"), "warning")],
          accent: "#ffb300",
        })
      }
      case "chokepoint": {
        const ships = toNumber(data?.ships_transiting ?? data?.ships_daily ?? data?.ships_nearby?.total)
        return makePayload({
          title: firstPresent(data?.name, "Chokepoint"),
          subtitle: firstPresent(data?.region, data?.status, "Maritime chokepoint"),
          brief: compactFacts([
            ships != null ? `${Math.round(ships)} ships nearby` : null,
            firstPresent(data?.risk_factors?.[0], data?.commodity_signals?.[0]?.symbol),
          ]).join(" · "),
          chips: [
            chip(firstPresent(data?.status, "Monitoring"), data?.status === "critical" ? "critical" : data?.status === "elevated" ? "warning" : "accent"),
            chip("Chokepoint", "neutral"),
          ],
          accent: data?.status === "critical" ? "#f44336" : "#4fc3f7",
        })
      }
      case "railway": {
        const category = firstPresent(data?.category_label, data?.category != null ? `Category ${data.category}` : null)
        return makePayload({
          title: "Railway",
          subtitle: firstPresent(data?.continent, data?.country, "Rail segment"),
          facts: [category, data?.electrified === 1 ? "Electrified" : "Non-electrified"],
          chips: [chip("Rail", "accent")],
          accent: data?.electrified === 1 ? "#64b5f6" : "#b0bec5",
        })
      }
      case "strike": {
        return makePayload({
          title: firstPresent(data?.name, data?.title, "Strike detection"),
          subtitle: firstPresent(data?.location_name, data?.country, data?.confidence_label, "Maritime incident"),
          facts: [
            firstPresent(data?.classification, data?.event_type, data?.satellite),
            firstPresent(data?.status, data?.confidence_label),
          ],
          chips: [
            chip(firstPresent(data?.severity, data?.classification, "Strike"), data?.severity === "critical" ? "critical" : "warning"),
          ],
          accent: "#ff7043",
        })
      }
      case "strike_arc": {
        return makePayload({
          title: firstPresent(data?.label, data?.name, data?.headline, "Strike arc"),
          subtitle: firstPresent(data?.theater, data?.target_name, data?.origin_name, "Conflict corridor"),
          facts: [
            firstPresent(data?.trend, data?.projectile_type, data?.category),
            firstPresent(data?.source_name, data?.verification_status),
          ],
          chips: [chip("Strike Arc", "critical")],
          accent: "#ef5350",
        })
      }
      case "strategic_situation": {
        const clusterCount = data?.direct_cluster_count != null
          ? `${data.direct_cluster_count} corroborated cluster${data.direct_cluster_count === 1 ? "" : "s"}`
          : null
        return makePayload({
          title: firstPresent(data?.name, "Strategic situation"),
          subtitle: firstPresent(data?.theater, data?.country, "Strategic view"),
          brief: compactFacts([
            clusterCount,
            firstPresent(data?.pressure_summary, data?.verification_status, data?.event_type),
          ]).join(" • "),
          chips: [
            chip("Situation", "warning"),
            chip(firstPresent(data?.event_type, data?.verification_status), "neutral"),
          ],
          accent: this._anchoredDetailMarkerStroke(kind, data) || "#ffab40",
          timeLabel: null,
        })
      }
      case "conflict_pulse": {
        const stroke = conflictPulseStroke(toNumber(data?.pulse_score) || 0)
        const reportCount = data?.count_24h != null
          ? `${data.count_24h} report${data.count_24h === 1 ? "" : "s"} / 24h`
          : null
        return makePayload({
          title: firstPresent(data?.situation_name, data?.theater, data?.conflict_name, "Conflict theater"),
          subtitle: firstPresent(data?.theater, data?.country, "Conflict pulse"),
          brief: compactFacts([
            data?.pulse_score != null ? `Pulse ${Math.round(data.pulse_score)}` : null,
            reportCount,
            firstPresent(data?.top_headlines?.[0], data?.country),
          ]).join(" • "),
          chips: [
            chip(firstPresent(data?.escalation_trend, "Monitoring"), data?.escalation_trend === "surging" || data?.escalation_trend === "escalating" ? "critical" : "warning"),
            chip("Theater", "neutral"),
          ],
          accent: stroke,
          stroke,
          timeLabel: null,
        })
      }
      case "hex_cell": {
        return makePayload({
          title: firstPresent(data?.local_name, data?.theater, "Conflict theater"),
          subtitle: firstPresent(data?.theater, data?.country, "Activity cell"),
          facts: [
            data?.event_count != null ? `${data.event_count} events` : null,
            data?.article_count != null ? `${data.article_count} articles` : null,
          ],
          chips: [chip("Theater", "warning")],
          accent: "#ff7043",
        })
      }
      case "conflict_event": {
        return makePayload({
          title: firstPresent(data?.conflict, data?.headline, "Conflict event"),
          subtitle: firstPresent(data?.country && data?.type_label ? `${data.country} · ${data.type_label}` : null, data?.location, "Conflict event"),
          brief: compactFacts([
            data?.deaths != null ? `${data.deaths} deaths` : null,
            firstPresent(data?.side_a && data?.side_b ? `${data.side_a} vs ${data.side_b}` : null, data?.date_start),
          ]).join(" · "),
          chips: [chip(firstPresent(data?.type_label, "Conflict"), "critical")],
          accent: "#f44336",
        })
      }
      case "traffic": {
        return makePayload({
          title: firstPresent(data?.name, data?.country_name, data?.code, "Internet traffic"),
          subtitle: "Internet traffic snapshot",
          facts: [
            data?.traffic != null ? `${data.traffic.toFixed(2)}% traffic` : null,
            data?.attack_target > 0 ? `${data.attack_target.toFixed(2)}% targeted` : data?.attack_origin > 0 ? `${data.attack_origin.toFixed(2)}% origin` : null,
          ],
          chips: [chip("Traffic", "accent")],
          accent: "#69f0ae",
        })
      }
      case "notam": {
        const low = data?.alt_low_ft?.toLocaleString?.() || "SFC"
        const high = data?.alt_high_ft?.toLocaleString?.()
        return makePayload({
          title: firstPresent(data?.reason, data?.id, "NOTAM"),
          subtitle: firstPresent(data?.id, "Aviation restriction"),
          facts: [
            data?.radius_nm != null ? `${data.radius_nm} NM` : null,
            high ? `${low}–${high} ft` : null,
          ],
          chips: [chip("NOTAM", "critical")],
          accent: "#ef5350",
        })
      }
      case "weather_alert": {
        return makePayload({
          title: firstPresent(data?.event, data?.title, "Weather alert"),
          subtitle: firstPresent(data?.area_desc, data?.sender_name, data?.headline, "Weather alert"),
          facts: [
            firstPresent(data?.severity, data?.urgency),
            firstPresent(data?.certainty, data?.status),
          ],
          chips: [chip(firstPresent(data?.severity, "Alert"), "warning")],
          accent: "#ff9800",
        })
      }
      case "commodity": {
        const price = toNumber(data?.price)
        const change = toNumber(data?.change_pct)
        return makePayload({
          title: firstPresent(data?.name, data?.symbol, "Commodity"),
          subtitle: firstPresent(data?.region, data?.category, "Market signal"),
          brief: compactFacts([
            price != null ? `$${price.toFixed(data?.category === "currency" ? 4 : 2)}` : null,
            change != null ? `${change > 0 ? "+" : ""}${change.toFixed(2)}%` : null,
          ]).join(" · "),
          chips: [chip(firstPresent(data?.category, "Market"), change < 0 ? "critical" : change > 0 ? "accent" : "neutral")],
          accent: change < 0 ? "#ef5350" : change > 0 ? "#4caf50" : "#ffc107",
        })
      }
      case "insight": {
        const theater = firstPresent(data?.entities?.theater?.name, data?.entities?.pulse?.theater, data?.location)
        return makePayload({
          title: firstPresent(data?.title, "Insight"),
          subtitle: firstPresent(theater, data?.category, "Derived insight"),
          brief: firstPresent(
            data?.description,
            data?.summary,
            compactFacts([
              data?.confidence != null ? `${Math.round(data.confidence * 100)}% confidence` : null,
              firstPresent(data?.kind, data?.severity),
            ]).join(" · ")
          ),
          chips: [chip(firstPresent(data?.severity, "Insight"), data?.severity === "critical" ? "critical" : "accent")],
          accent: "#8bd8ff",
        })
      }
      case "fire_hotspot": {
        return makePayload({
          title: "Fire hotspot",
          subtitle: firstPresent(data?.satellite, data?.country, data?.daynight, "Thermal anomaly"),
          facts: [
            firstPresent(data?.confidence, data?.confidence_label),
            firstPresent(data?.brightness, data?.frp != null ? `FRP ${data.frp}` : null),
          ],
          chips: [chip("Fire", "warning")],
          accent: "#ff7043",
        })
      }
      case "fire_cluster": {
        return makePayload({
          title: data?.count != null ? `${data.count} hotspots` : "Fire cluster",
          subtitle: firstPresent(data?.name, data?.country, "Clustered fire activity"),
          facts: [
            firstPresent(data?.confidence, data?.high_confidence_count != null ? `${data.high_confidence_count} high confidence` : null),
            firstPresent(data?.latest_time, data?.satellite),
          ],
          chips: [chip("Fire Cluster", "warning")],
          accent: "#ff8a65",
        })
      }
      default:
        return makePayload({
          title: genericTitle,
          subtitle: genericSubtitle,
          facts: genericFacts,
          chips: [chip(kindLabel(kind), "neutral")],
        })
    }
  }
}
