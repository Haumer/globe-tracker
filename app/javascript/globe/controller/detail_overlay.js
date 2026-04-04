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
    this.anchorOverlayTarget.style.display = ""
    this.anchorPanelTarget.style.display = ""
    this.anchorPanelTarget.dataset.mode = "anchored"
    this.anchorPanelTarget.style.setProperty("--anchor-accent", payload.accent || "#8bd8ff")
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
    }
    if (this.hasAnchorOverlayTarget) {
      this.anchorOverlayTarget.style.display = "none"
    }
    if (this.hasAnchorLeaderTarget) {
      this.anchorLeaderTarget.style.display = "none"
    }
    if (this.hasAnchorLeaderPathTarget) {
      this.anchorLeaderPathTarget.setAttribute("d", "")
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

    const facts = compactFacts(payload.facts || [], 2)
    const factsHtml = facts.length
      ? `<div class="anchor-facts">${facts.map(value => `<span>${this._escapeHtml(value)}</span>`).join('<span class="anchor-dot">&middot;</span>')}</div>`
      : ""

    return `
      <div class="anchor-head">
        <div class="anchor-chip-row">${chipsHtml}</div>
        ${payload.timeLabel ? `<div class="anchor-time">${this._escapeHtml(payload.timeLabel)}</div>` : ""}
      </div>
      <div class="anchor-title">${this._escapeHtml(payload.title || kindLabel(payload.kind))}</div>
      ${subtitleHtml}
      ${factsHtml}
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

  GlobeController.prototype._refreshAnchoredDetailPosition = function(force = false) {
    if (!this._anchoredDetailState || !this.hasAnchorPanelTarget) return
    if (!force && window.getComputedStyle(this.anchorPanelTarget).display === "none") return

    const panel = this.anchorPanelTarget
    const overlay = this.hasAnchorOverlayTarget ? this.anchorOverlayTarget : null
    const leader = this.hasAnchorLeaderTarget ? this.anchorLeaderTarget : null
    const leaderPath = this.hasAnchorLeaderPathTarget ? this.anchorLeaderPathTarget : null

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
    }

    if (mobile) {
      state.hiddenSince = null
      panel.dataset.mode = "docked"
      panel.style.left = ""
      panel.style.top = ""
      if (leader) leader.style.display = "none"
      if (leaderPath) leaderPath.setAttribute("d", "")
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
    if (pointDistance(point, join) > 168) {
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
    const bendY = placement.vertical === "above" ? point.y - 12 : point.y + 12
    leaderPath.setAttribute("d", `M ${Math.round(point.x)} ${Math.round(point.y)} L ${Math.round(point.x)} ${Math.round(bendY)} L ${Math.round(join.x)} ${Math.round(bendY)} L ${Math.round(join.x)} ${Math.round(join.y)}`)
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

    const makePayload = ({ title, subtitle, facts = [], chips = [], accent }) => ({
      kind,
      title: title || genericTitle,
      subtitle: subtitle || genericSubtitle,
      facts: compactFacts(facts.length ? facts : genericFacts),
      chips: chips.filter(Boolean).slice(0, 2),
      timeLabel,
      accent: accent || "#8bd8ff",
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
        return makePayload({
          title: firstPresent(data?.title, data?.name, "News signal"),
          subtitle: firstPresent(data?.name, data?.publisher, data?.origin_source, "Reported event"),
          facts: [
            firstPresent(data?.claim_event_type && `${data.claim_event_type}`.replace(/_/g, " "), actors.slice(0, 2).join(", ")),
            firstPresent(data?.publisher, data?.source),
          ],
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
          subtitle: firstPresent(data?.status, data?.region, "Maritime chokepoint"),
          facts: [
            ships != null ? `${Math.round(ships)} ships` : null,
            firstPresent(data?.risk_factors?.[0], data?.commodity_signals?.[0]?.symbol),
          ],
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
        return makePayload({
          title: firstPresent(data?.name, "Strategic situation"),
          subtitle: firstPresent(data?.theater, data?.pressure_summary, "Strategic view"),
          facts: [
            data?.direct_cluster_count != null ? `${data.direct_cluster_count} corroborated clusters` : null,
            firstPresent(data?.verification_status, data?.event_type),
          ],
          chips: [
            chip("Situation", "warning"),
            chip(firstPresent(data?.event_type, data?.verification_status), "neutral"),
          ],
          accent: "#ffab40",
        })
      }
      case "conflict_pulse": {
        return makePayload({
          title: firstPresent(data?.situation_name, data?.theater, data?.conflict_name, "Conflict theater"),
          subtitle: firstPresent(data?.theater, data?.country, "Conflict pulse"),
          facts: [
            data?.pulse_score != null ? `Pulse ${Math.round(data.pulse_score)}` : null,
            firstPresent(data?.escalation_trend, data?.top_headlines?.[0]),
          ],
          chips: [
            chip(firstPresent(data?.escalation_trend, "Monitoring"), data?.escalation_trend === "surging" || data?.escalation_trend === "escalating" ? "critical" : "warning"),
            chip("Theater", "neutral"),
          ],
          accent: data?.escalation_trend === "surging" || data?.escalation_trend === "escalating" ? "#ef5350" : "#ff9800",
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
          facts: [
            data?.deaths != null ? `${data.deaths} deaths` : null,
            firstPresent(data?.date_start, data?.side_a && data?.side_b ? `${data.side_a} vs ${data.side_b}` : null),
          ],
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
          facts: [
            price != null ? `$${price.toFixed(data?.category === "currency" ? 4 : 2)}` : null,
            change != null ? `${change > 0 ? "+" : ""}${change.toFixed(2)}%` : null,
          ],
          chips: [chip(firstPresent(data?.category, "Market"), change < 0 ? "critical" : change > 0 ? "accent" : "neutral")],
          accent: change < 0 ? "#ef5350" : change > 0 ? "#4caf50" : "#ffc107",
        })
      }
      case "insight": {
        return makePayload({
          title: firstPresent(data?.title, "Insight"),
          subtitle: firstPresent(data?.summary, data?.category, "Derived insight"),
          facts: [
            data?.confidence != null ? `${Math.round(data.confidence * 100)}% confidence` : null,
            firstPresent(data?.kind, data?.severity),
          ],
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
