import { getDataSource, findCountryAtPoint } from "../../utils"

export function applyConflictPulseMethods(GlobeController) {
  GlobeController.prototype._conflictPulseEntityKey = function(value, fallback = "unknown") {
    return encodeURIComponent(String(value ?? fallback))
  }

  // ── Lifecycle ──────────────────────────────────────────────

  GlobeController.prototype._startConflictPulse = function() {
    this._conflictPulseData = []
    this._strategicSituationData = []
    this._conflictPulseEntities = []
    this._conflictPulsePrev = {}  // track previous state for surge detection
    this._strikeArcsVisible = false
    this._hexTheaterVisible = false
    this._fetchConflictPulse()
    this._conflictPulseInterval = setInterval(() => this._fetchConflictPulse(), 10 * 60 * 1000) // 10 min
  }

  GlobeController.prototype._stopConflictPulse = function() {
    if (this._conflictPulseInterval) {
      clearInterval(this._conflictPulseInterval)
      this._conflictPulseInterval = null
    }
    this._clearConflictPulseEntities()
  }

  // ── Data fetch ─────────────────────────────────────────────

  GlobeController.prototype._fetchConflictPulse = async function() {
    try {
      const resp = await fetch("/api/conflict_pulse")
      if (!resp.ok) return
      const data = await resp.json()
      const zones = data.zones || []
      this._conflictPulseSnapshotStatus = data.snapshot_status || "ready"

      // Detect new surges — compare to previous state
      const prev = this._conflictPulsePrev || {}
      zones.forEach(zone => {
        const prevZone = prev[zone.cell_key]
        if (!prevZone && zone.escalation_trend === "surging") {
          // Brand new surging zone
          this._toastConflictPulse(zone)
        } else if (prevZone && prevZone.escalation_trend !== "surging" && zone.escalation_trend === "surging") {
          // Escalated to surging
          this._toastConflictPulse(zone)
        } else if (!prevZone && zone.pulse_score >= 70) {
          // High-scoring new zone
          this._toastConflictPulse(zone)
        }
      })

      // Cache current state for next comparison
      this._conflictPulsePrev = {}
      zones.forEach(z => { this._conflictPulsePrev[z.cell_key] = z })

      this._conflictPulseData = zones
      this._conflictPulseZones = zones
      this._strategicSituationData = data.strategic_situations || []
      this._strikeArcData = data.strike_arcs || []
      this._hexCellData = data.hex_cells || []
      this._renderConflictPulse()
      this._renderSituationPanel()
      if (this._syncRightPanels) this._syncRightPanels()
    } catch (e) {
      console.warn("Conflict pulse fetch failed:", e)
    }
  }

  // ── Toast notification for surging zones ────────────────────

  GlobeController.prototype._toastConflictPulse = function(zone) {
    const headline = zone.top_headlines?.[0] || "Developing situation detected"
    const trend = zone.escalation_trend.toUpperCase()
    const el = document.getElementById("gt-toast")
    if (!el) return

    clearTimeout(this._toastTimer)
    el.classList.remove("visible", "gt-toast--success", "gt-toast--error")
    el.innerHTML = ""
    el.classList.add("gt-toast--error") // red styling for urgency

    const container = document.createElement("div")
    container.style.cssText = "display:flex;flex-direction:column;gap:4px;max-width:400px;cursor:pointer;"
    container.innerHTML = `
      <div style="font:600 10px var(--gt-mono,monospace);letter-spacing:1px;color:#ff5252;">${trend} — CONFLICT PULSE ${zone.pulse_score}</div>
      <div style="font:400 11px var(--gt-mono,monospace);color:#fff;line-height:1.3;">${headline.slice(0, 100)}</div>
      <div style="font:400 9px var(--gt-mono,monospace);color:#aaa;">${zone.count_24h} reports · ${zone.source_count} sources · Click to focus</div>
    `
    container.addEventListener("click", () => {
      this._flyToConflictPulse(zone)
      this._toastHide()
    })

    const closeBtn = document.createElement("button")
    closeBtn.className = "gt-toast-close"
    closeBtn.innerHTML = "&times;"
    closeBtn.setAttribute("aria-label", "Dismiss")
    closeBtn.addEventListener("click", (e) => { e.stopPropagation(); this._toastHide() })

    el.appendChild(container)
    el.appendChild(closeBtn)
    el.style.pointerEvents = "auto"
    el.classList.add("visible")

    // Auto-hide after 15 seconds (longer than normal toast — this is important)
    this._toastTimer = setTimeout(() => el.classList.remove("visible"), 15000)
  }

  // ── Globe rendering ────────────────────────────────────────

  GlobeController.prototype._renderConflictPulse = function() {
    this._clearConflictPulseEntities()
    if (this._pulseAnimFrame) { cancelAnimationFrame(this._pulseAnimFrame); this._pulseAnimFrame = null }

    const Cesium = window.Cesium
    const ds = getDataSource(this.viewer, this._ds, "conflictPulse")

    if (!this._conflictPulseData?.length) return

    // Detect meaningful score increases since last render (not just new articles arriving)
    const prev = this._conflictPulsePrevScores || {}
    const increased = new Set()
    this._conflictPulseData.forEach(z => {
      const prevScore = prev[z.cell_key]
      // Only pulse if score increased by 5+ points (not just minor fluctuation from new poll)
      if (prevScore !== undefined && z.pulse_score >= prevScore + 5) increased.add(z.cell_key)
    })
    // Update score cache
    this._conflictPulsePrevScores = {}
    this._conflictPulseData.forEach(z => { this._conflictPulsePrevScores[z.cell_key] = z.pulse_score })

    // Track pulsing rings for animation
    this._pulsingRings = []

    ds.entities.suspendEvents()

    // ── Layer 1: Hex theater (background — shows geographic extent) ──
    if (this._hexCellData?.length && this._hexTheaterVisible !== false) {
      this._hexCellData.forEach((cell, idx) => {
        const t = cell.intensity
        if (t < 0.01) return
        if (!cell.vertices || cell.vertices.length !== 6) return
        // Color: orange (low) → red-orange (mid) → bright red (high)
        const r = 255
        const g = Math.round(180 * (1 - t * 0.8))
        const b = Math.round(50 * (1 - t))
        const hexColor = Cesium.Color.fromBytes(r, g, b)

        // Use pre-computed vertices from backend
        const positions = cell.vertices.map(v => Cesium.Cartesian3.fromDegrees(v[1], v[0]))

        const hex = ds.entities.add({
          id: `cpulse-hex-${idx}`,
          polygon: {
            hierarchy: new Cesium.PolygonHierarchy(positions),
            material: hexColor.withAlpha(0.18 + t * 0.35),
            outline: true,
            outlineColor: hexColor.withAlpha(0.5 + t * 0.4),
            outlineWidth: 2,
          },
          properties: {
            zone_key: cell.zone_key || "",
            situation: cell.situation || "",
            theater: cell.theater || "",
            count: cell.count,
          },
        })
        this._conflictPulseEntities.push(hex)
      })
    }

    // ── Layer 2: Strike arcs (directional attack flows) ──
    if (this._strikeArcData?.length && this._strikeArcsVisible !== false) {
      this._strikeArcData.forEach((arc, idx) => {
        if (arc.count < 2) return
        const t = Math.min(arc.count / 20, 1)
        const arcColor = Cesium.Color.fromCssColorString("#f44336")
        const width = Math.max(8, Math.min(1.5 + arc.count * 0.2, 12))

        // Build great-circle arc positions
        const arcPositions = this._buildArcPositions(arc.from_lat, arc.from_lng, arc.to_lat, arc.to_lng, 30)
        if (!arcPositions.length) return

        const line = ds.entities.add({
          id: `cpulse-arc-${idx}`,
          polyline: {
            positions: arcPositions,
            width: width,
            material: new Cesium.PolylineGlowMaterialProperty({
              glowPower: 0.15,
              color: arcColor.withAlpha(0.3 + t * 0.4),
            }),
          },
          properties: {
            arcIdx: idx,
            clickable: true,
          },
        })
        this._conflictPulseEntities.push(line)

        // Clickable midpoint billboard for interaction
        const midIdx = Math.floor(arcPositions.length / 2)
        const midLabel = ds.entities.add({
          id: `cpulse-arc-lbl-${idx}`,
          position: arcPositions[midIdx],
          label: {
            text: `${arc.from_name} → ${arc.to_name} (${arc.count})`,
            font: "bold 10px 'JetBrains Mono', monospace",
            fillColor: Cesium.Color.WHITE.withAlpha(0.8),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            pixelOffset: new Cesium.Cartesian2(0, -6),
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
            scaleByDistance: new Cesium.NearFarScalar(5e5, 0.8, 8e6, 0.0),
            translucencyByDistance: new Cesium.NearFarScalar(5e5, 0.8, 8e6, 0.0),
          },
          properties: {
            arcIdx: idx,
            clickable: true,
          },
        })
        this._conflictPulseEntities.push(midLabel)
      })
    }

    // ── Layer 3: Situation nodes (pulse zones with names) ──
    this._conflictPulseData.forEach((zone, idx) => {
      const zoneKey = this._conflictPulseEntityKey(zone.cell_key || `zone-${idx}`)
      const score = zone.pulse_score
      const t = Math.min((score - 20) / 60, 1)

      // Tiered visuals: developing (20-49) = yellow/dim, active (50-69) = orange, high (70+) = red/bright
      let r, g, b
      if (score >= 70) {
        r = 244; g = 67; b = 54    // red
      } else if (score >= 50) {
        r = 255; g = 152; b = 0    // orange
      } else {
        r = 255; g = 193; b = 7    // yellow
      }
      const color = Cesium.Color.fromBytes(r, g, b)

      // Radius: developing = smaller, active = larger
      const radius = score >= 50 ? (100000 + score * 2000) : (60000 + score * 1000)

      // Opacity: developing = very subtle, active = visible, surging = bright
      const baseAlpha = score >= 70 ? 0.15 : (score >= 50 ? 0.10 : 0.04)
      const outlineAlpha = score >= 70 ? 0.6 : (score >= 50 ? 0.4 : 0.15)

      // Outer ring
      const ring = ds.entities.add({
        id: `cpulse-ring-${zoneKey}`,
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
        ellipse: {
          semiMajorAxis: radius,
          semiMinorAxis: radius,
          material: color.withAlpha(baseAlpha),
          outline: true,
          outlineColor: color.withAlpha(outlineAlpha),
          outlineWidth: score >= 50 ? 2 : 1,
          height: 5100,
        },
      })
      this._conflictPulseEntities.push(ring)

      // Pulsing outer ring for surging zones or zones that just increased
      if (zone.escalation_trend === "surging" || zone.escalation_trend === "active" || increased.has(zone.cell_key)) {
        const pulseRing = ds.entities.add({
          id: `cpulse-pulse-${zoneKey}`,
          position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
          ellipse: {
            semiMajorAxis: radius,
            semiMinorAxis: radius,
            material: Cesium.Color.TRANSPARENT,
            outline: true,
            outlineColor: color.withAlpha(0.8),
            outlineWidth: 3,
            height: 5200,
          },
        })
        this._conflictPulseEntities.push(pulseRing)
        // Phase offset based on index — staggers simultaneous pulses so they don't look uniform
        this._pulsingRings.push({ entity: pulseRing, baseRadius: radius, color, phaseOffset: idx * 0.7 })
      }

      // Inner core (only for active zones 50+)
      if (score >= 50) {
        const core = ds.entities.add({
          id: `cpulse-core-${zoneKey}`,
          position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
          ellipse: {
            semiMajorAxis: radius * 0.25,
            semiMinorAxis: radius * 0.25,
            material: color.withAlpha(0.2 + t * 0.15),
            outline: false,
            height: 5100,
          },
        })
        this._conflictPulseEntities.push(core)
      }

      // Trend indicator for the icon
      const trendArrow = { surging: "▲", escalating: "↗", elevated: "→", active: "●", baseline: "↓" }[zone.escalation_trend] || ""

      // Clickable billboard — larger, bolder, always readable
      const iconSize = score >= 70 ? 48 : (score >= 50 ? 44 : 36)
      const point = ds.entities.add({
        id: `cpulse-${zoneKey}`,
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat, 5500),
        billboard: {
          image: this._makePulseIcon(trendArrow, color.toCssColorString(), score),
          width: iconSize,
          height: iconSize,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(3e5, 1.2, 8e6, 0.5),
        },
        label: {
          text: zone.situation_name || (zone.escalation_trend || "").toUpperCase(),
          font: "bold 13px 'JetBrains Mono', monospace",
          fillColor: Cesium.Color.WHITE,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 5,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, iconSize / 2 + 8),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(3e5, 1.0, 8e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(3e5, 1.0, 1e7, 0.0),
        },
      })
      this._conflictPulseEntities.push(point)
    })

    // ── Layer 4: Strategic situations (named strategic nodes under theater pressure) ──
    ;(this._strategicSituationData || []).forEach((item, idx) => {
      const strategicKey = this._conflictPulseEntityKey(item.id || item.node_id || item.name || `strategic-${idx}`)
      const statusColors = {
        critical: "#ff7043",
        elevated: "#ffca28",
        monitoring: "#26c6da",
      }
      const color = Cesium.Color.fromCssColorString(statusColors[item.status] || "#26c6da")
      const radius = 70000 + ((item.strategic_score || 0) * 1200)
      const iconSize = item.status === "critical" ? 34 : 30

      const ring = ds.entities.add({
        id: `cpulse-strat-ring-${strategicKey}`,
        position: Cesium.Cartesian3.fromDegrees(item.lng, item.lat),
        ellipse: {
          semiMajorAxis: radius,
          semiMinorAxis: radius,
          material: color.withAlpha(0.05),
          outline: true,
          outlineColor: color.withAlpha(0.5),
          outlineWidth: 2,
          height: 5300,
        },
      })
      this._conflictPulseEntities.push(ring)

      const point = ds.entities.add({
        id: `cpulse-strat-${strategicKey}`,
        position: Cesium.Cartesian3.fromDegrees(item.lng, item.lat, 5600),
        billboard: {
          image: this._makeStrategicSituationIcon(item, statusColors[item.status] || "#26c6da"),
          width: iconSize,
          height: iconSize,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(3e5, 1.1, 8e6, 0.45),
        },
        label: {
          text: item.name || "Strategic node",
          font: "bold 12px 'JetBrains Mono', monospace",
          fillColor: color.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 4,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, iconSize / 2 + 8),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(3e5, 1.0, 8e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(3e5, 1.0, 1e7, 0.0),
        },
      })
      this._conflictPulseEntities.push(point)
    })
    ds.entities.resumeEvents()
    if (this._updateGlobeOcclusion) this._updateGlobeOcclusion()

    // Start pulse animation if any rings need it
    if (this._pulsingRings.length > 0) {
      this._startPulseAnimation()
    }

    this._requestRender()
  }

  // ── Pulse animation loop ───────────────────────────────────
  // Surging zones and zones with increasing scores get an expanding/fading ring

  GlobeController.prototype._startPulseAnimation = function() {
    if (this._pulseAnimFrame) return
    const startTime = performance.now()

    const animate = () => {
      if (!this._pulsingRings?.length) return
      const elapsed = (performance.now() - startTime) / 1000
      const cycle = (elapsed % 3) / 3 // 0-1 over 3 seconds

      this._pulsingRings.forEach(({ entity, baseRadius, color, phaseOffset }) => {
        if (!entity.ellipse) return
        const phase = ((elapsed + phaseOffset) % 3) / 3 // staggered 0-1 cycle
        const expandFactor = 1.0 + phase * 0.5
        const alpha = 0.8 * (1 - phase)
        entity.ellipse.semiMajorAxis = baseRadius * expandFactor
        entity.ellipse.semiMinorAxis = baseRadius * expandFactor
        entity.ellipse.outlineColor = color.withAlpha(alpha)
      })

      this._requestRender()
      this._pulseAnimFrame = requestAnimationFrame(animate)
    }

    this._pulseAnimFrame = requestAnimationFrame(animate)
  }

  GlobeController.prototype._clearConflictPulseEntities = function() {
    if (this._pulseAnimFrame) { cancelAnimationFrame(this._pulseAnimFrame); this._pulseAnimFrame = null }
    this._pulsingRings = []
    const ds = this._ds["conflictPulse"]
    if (ds && this._conflictPulseEntities?.length) {
      ds.entities.suspendEvents()
      this._conflictPulseEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._conflictPulseEntities = []
  }

  // ── Great-circle arc builder ─────────────────────────────────

  GlobeController.prototype._buildArcPositions = function(lat1, lng1, lat2, lng2, segments) {
    const Cesium = window.Cesium
    const positions = []
    const start = Cesium.Cartographic.fromDegrees(lng1, lat1)
    const end = Cesium.Cartographic.fromDegrees(lng2, lat2)

    for (let i = 0; i <= segments; i++) {
      const t = i / segments
      // SLERP on the ellipsoid
      const lat = lat1 + (lat2 - lat1) * t
      const lng = lng1 + (lng2 - lng1) * t
      // Add altitude arc (peaks in the middle for visual clarity)
      const arcHeight = Math.sin(t * Math.PI) * 200000 // 200km peak
      positions.push(Cesium.Cartesian3.fromDegrees(lng, lat, arcHeight))
    }
    return positions
  }

  // ── Icon generation ─────────────────────────────────────────

  GlobeController.prototype._makePulseIcon = function(trendArrow, color, score) {
    const key = `pulse-${trendArrow}-${color}-${score}`
    if (this._iconCache?.[key]) return this._iconCache[key]
    if (!this._iconCache) this._iconCache = {}

    const size = 52
    const canvas = document.createElement("canvas")
    canvas.width = size; canvas.height = size
    const ctx = canvas.getContext("2d")
    const cx = size / 2
    const r = size / 2 - 2

    // Filled circle with colored tint
    ctx.beginPath()
    ctx.arc(cx, cx, r, 0, Math.PI * 2)
    ctx.fillStyle = "rgba(0,0,0,0.9)"
    ctx.fill()
    // Colored border
    ctx.strokeStyle = color
    ctx.lineWidth = 3
    ctx.stroke()

    // Score text — large and white
    ctx.font = "bold 18px 'JetBrains Mono', monospace"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = "#fff"
    ctx.fillText(score, cx, trendArrow ? cx - 4 : cx)

    // Trend arrow below score
    if (trendArrow) {
      ctx.font = "bold 11px sans-serif"
      ctx.fillStyle = color
      ctx.fillText(trendArrow, cx, cx + 12)
    }

    const url = canvas.toDataURL()
    this._iconCache[key] = url
    return url
  }

  GlobeController.prototype._makeStrategicSituationIcon = function(item, color) {
    const key = `strategic-${item.id}-${item.status}-${item.strategic_score}`
    if (this._iconCache?.[key]) return this._iconCache[key]
    if (!this._iconCache) this._iconCache = {}

    const size = 40
    const canvas = document.createElement("canvas")
    canvas.width = size; canvas.height = size
    const ctx = canvas.getContext("2d")

    ctx.beginPath()
    ctx.roundRect(4, 4, size - 8, size - 8, 8)
    ctx.fillStyle = "rgba(7,10,15,0.92)"
    ctx.fill()
    ctx.strokeStyle = color
    ctx.lineWidth = 2.5
    ctx.stroke()

    ctx.font = "bold 16px 'JetBrains Mono', monospace"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = color
    ctx.fillText("S", size / 2, 14)

    ctx.font = "bold 11px 'JetBrains Mono', monospace"
    ctx.fillStyle = "#fff"
    ctx.fillText(`${item.strategic_score || 0}`, size / 2, 27)

    const url = canvas.toDataURL()
    this._iconCache[key] = url
    return url
  }

  // ── Click handler + detail panel ───────────────────────────

  GlobeController.prototype._flyToConflictPulse = function(zone) {
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat, 1500000),
      duration: 1.5,
    })
    this.showConflictPulseDetail(zone)
  }

  GlobeController.prototype._flyToStrategicSituation = function(item) {
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(item.lng, item.lat, 1400000),
      duration: 1.5,
    })
    this.showStrategicSituationDetail(item)
  }

  GlobeController.prototype.showConflictPulseDetail = function(zone) {
    if (this._buildTheaterContext && this._setSelectedContext) {
      this._setSelectedContext(this._buildTheaterContext(zone))
    }

    const trendColors = { surging: "#f44336", active: "#f44336", escalating: "#ff9800", elevated: "#ffc107", baseline: "#66bb6a" }
    const color = trendColors[zone.escalation_trend] || "#ff9800"

    // Cross-layer signal chips (clickable — fly to area with relevant layer)
    let signalHtml = ""
    const s = zone.cross_layer_signals || {}
    if (s.military_flights) signalHtml += `<span class="detail-chip" style="cursor:pointer;background:rgba(239,83,80,0.15);color:#ef5350;" data-action="click->globe#pulseSignalClick" data-signal="flights" data-lat="${zone.lat}" data-lng="${zone.lng}"><i class="fa-solid fa-jet-fighter"></i> ${s.military_flights} mil flights</span>`
    if (s.gps_jamming) signalHtml += `<span class="detail-chip" style="cursor:pointer;background:rgba(255,193,7,0.15);color:#ffc107;" data-action="click->globe#pulseSignalClick" data-signal="gpsJamming" data-lat="${zone.lat}" data-lng="${zone.lng}"><i class="fa-solid fa-satellite-dish"></i> ${s.gps_jamming}% jamming</span>`
    if (s.internet_outage) signalHtml += `<span class="detail-chip" style="background:rgba(156,39,176,0.15);color:#ce93d8;"><i class="fa-solid fa-plug"></i> outage: ${s.internet_outage}</span>`
    if (s.fire_hotspots) signalHtml += `<span class="detail-chip" style="cursor:pointer;background:rgba(255,87,34,0.15);color:#ff5722;" data-action="click->globe#pulseSignalClick" data-signal="fires" data-lat="${zone.lat}" data-lng="${zone.lng}"><i class="fa-solid fa-fire"></i> ${s.fire_hotspots} fires</span>`
    if (s.known_conflict_zone) signalHtml += `<span class="detail-chip" style="cursor:pointer;background:rgba(244,67,54,0.15);color:#f44336;" data-action="click->globe#pulseSignalClick" data-signal="conflicts" data-lat="${zone.lat}" data-lng="${zone.lng}"><i class="fa-solid fa-crosshairs"></i> ${s.known_conflict_zone} historical events</span>`

    // Tier breakdown
    const tiers = zone.tier_breakdown || {}
    let tierHtml = Object.entries(tiers).sort((a,b) => a[0].localeCompare(b[0]))
      .map(([t, n]) => `<span style="color:#888;">${t}:</span>${n}`).join(" ")

    // Headlines with clickable links
    const articles = zone.top_articles || []
    const headlinesHtml = articles.length > 0
      ? articles.map(a => {
          const timeAgo = a.published_at ? this._timeAgo(new Date(a.published_at)) : ""
          const itemBody = `
            <div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.3;">${this._escapeHtml(a.title)}</div>
            <div style="font:400 9px var(--gt-mono,monospace);color:#666;margin-top:2px;">${this._escapeHtml(a.publisher || a.source || "")} · tone ${a.tone || 0} · ${timeAgo}</div>
          `
          if (a.cluster_id) {
            return `<div style="display:flex;gap:8px;align-items:flex-start;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
              <button type="button" data-action="click->globe#selectContextNode" data-kind="news_story_cluster" data-id="${this._escapeHtml(a.cluster_id)}" data-title="${this._escapeHtml(a.title || "Story cluster")}" data-summary="${this._escapeHtml((a.publisher || a.source || "") + (timeAgo ? ` · ${timeAgo}` : ""))}" style="flex:1;padding:0;border:0;background:none;text-align:left;cursor:pointer;">
                ${itemBody}
              </button>
              ${a.url ? `<a href="${this._safeUrl(a.url)}" target="_blank" rel="noopener" style="color:#888;text-decoration:none;padding-top:2px;"><i class="fa-solid fa-arrow-up-right-from-square"></i></a>` : ""}
            </div>`
          }
          return `<a href="${this._safeUrl(a.url)}" target="_blank" rel="noopener" style="display:block;text-decoration:none;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
            ${itemBody}
          </a>`
        }).join("")
      : (zone.top_headlines || []).map(h =>
          `<div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.4;padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.05);">${this._escapeHtml(h)}</div>`
        ).join("")

    // Sparkline bars
    const spikeBar = Math.min(zone.spike_ratio / 5.0, 1.0) * 100
    const toneBar = Math.min(Math.abs(zone.avg_tone) / 10.0, 1.0) * 100

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-bolt" style="margin-right:6px;"></i>${zone.situation_name ? this._escapeHtml(zone.situation_name) : "DEVELOPING SITUATION"}
      </div>
      <div style="display:inline-block;padding:2px 8px;border-radius:3px;background:${color};color:#000;font:700 10px var(--gt-mono,monospace);letter-spacing:1px;margin-bottom:8px;">
        ${zone.escalation_trend.toUpperCase()} — PULSE ${zone.pulse_score}
      </div>

      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Reports (24h)</span>
          <span class="detail-value" style="color:${color};">${zone.count_24h}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Reports (7d)</span>
          <span class="detail-value">${zone.count_7d}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Sources</span>
          <span class="detail-value">${zone.source_count}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Stories</span>
          <span class="detail-value">${zone.story_count}</span>
        </div>
      </div>

      <div style="margin:8px 0;">
        <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:4px;">FREQUENCY SPIKE</div>
        <div style="display:flex;align-items:center;gap:8px;">
          <div style="flex:1;height:6px;background:rgba(255,255,255,0.08);border-radius:3px;overflow:hidden;">
            <div style="width:${spikeBar}%;height:100%;background:${color};border-radius:3px;"></div>
          </div>
          <span style="font:600 11px var(--gt-mono,monospace);color:${color};">${zone.spike_ratio}x</span>
        </div>
      </div>

      <div style="margin:8px 0;">
        <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:4px;">TONE SEVERITY</div>
        <div style="display:flex;align-items:center;gap:8px;">
          <div style="flex:1;height:6px;background:rgba(255,255,255,0.08);border-radius:3px;overflow:hidden;">
            <div style="width:${toneBar}%;height:100%;background:#ef5350;border-radius:3px;"></div>
          </div>
          <span style="font:600 11px var(--gt-mono,monospace);color:#ef5350;">${zone.avg_tone}</span>
        </div>
      </div>

      ${signalHtml ? `
        <div style="margin:10px 0;">
          <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">CROSS-LAYER SIGNALS</div>
          <div style="display:flex;flex-wrap:wrap;gap:4px;">${signalHtml}</div>
        </div>
      ` : ""}

      <div style="margin:10px 0;">
        <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">TOP HEADLINES</div>
        ${headlinesHtml}
      </div>

      <div style="font:400 9px var(--gt-mono,monospace);color:#666;margin-top:8px;">
        Sources: ${tierHtml} · Updated ${new Date(zone.detected_at).toLocaleTimeString()}
      </div>

      ${zone.theater ? `<button class="detail-track-btn" style="background:rgba(255,152,0,0.15);border-color:rgba(255,152,0,0.3);color:#ffa726;font-weight:700;" data-action="click->globe#highlightTheater" data-theater="${this._escapeHtml(zone.theater)}">
        <i class="fa-solid fa-layer-group" style="margin-right:4px;"></i>Highlight ${this._escapeHtml(zone.theater)}
      </button>` : ""}

      <button class="detail-track-btn" style="background:rgba(244,67,54,0.2);border-color:rgba(244,67,54,0.4);color:#f44336;font-weight:700;" data-action="click->globe#revealPulseConnections" data-lat="${zone.lat}" data-lng="${zone.lng}" data-signals="${this._escapeHtml(JSON.stringify(s))}">
        <i class="fa-solid fa-eye" style="margin-right:4px;"></i>Explore This Area
      </button>

      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${zone.lat}" data-lng="${zone.lng}">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
      </button>

      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("conflict", zone.lat, zone.lng)

  }

  GlobeController.prototype.showStrategicSituationDetail = function(item) {
    if (item?.kind && item?.node_id && this._focusContextNode) {
      this._focusContextNode(
        { kind: item.kind, id: item.node_id },
        {
          title: item.name,
          summary: item.pressure_summary || [item.theater, `${item.direct_cluster_count || 0} corroborated clusters`].filter(Boolean).join(" · "),
        }
      )
    }

    const statusColors = { critical: "#ff7043", elevated: "#ffca28", monitoring: "#26c6da" }
    const color = statusColors[item.status] || "#26c6da"
    const signalHtml = Object.entries(item.cross_layer_signals || {}).map(([key, val]) => {
      const label = key.replace(/_/g, " ")
      return `<span class="detail-chip" style="background:rgba(38,198,218,0.12);color:${key === "gps_jamming" ? "#ffca28" : color};">${this._escapeHtml(`${label}: ${val}`)}</span>`
    }).join("")
    const headlinesHtml = (item.top_articles || []).map(article => {
      const timeAgo = article.published_at ? this._timeAgo(new Date(article.published_at)) : ""
      if (article.cluster_id) {
        return `<div style="display:flex;gap:8px;align-items:flex-start;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
          <button type="button" data-action="click->globe#selectContextNode" data-kind="news_story_cluster" data-id="${this._escapeHtml(article.cluster_id)}" data-title="${this._escapeHtml(article.title || "Story cluster")}" data-summary="${this._escapeHtml((article.publisher || article.source || "") + (timeAgo ? ` · ${timeAgo}` : ""))}" style="flex:1;padding:0;border:0;background:none;text-align:left;cursor:pointer;">
            <div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.3;">${this._escapeHtml(article.title)}</div>
            <div style="font:400 9px var(--gt-mono,monospace);color:#666;margin-top:2px;">${this._escapeHtml(article.publisher || article.source || "")} · ${timeAgo}</div>
          </button>
          ${article.url ? `<a href="${this._safeUrl(article.url)}" target="_blank" rel="noopener" style="color:#888;text-decoration:none;padding-top:2px;"><i class="fa-solid fa-arrow-up-right-from-square"></i></a>` : ""}
        </div>`
      }
      return `<div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.4;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">${this._escapeHtml(article.title)}</div>`
    }).join("")
    const flowRows = Object.entries(item.flows || {}).filter(([, flow]) => flow?.pct).map(([type, flow]) =>
      `<div style="display:flex;justify-content:space-between;padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
        <span style="font:600 11px var(--gt-mono);color:#e0e0e0;text-transform:capitalize;">${this._escapeHtml(type)}</span>
        <span style="font:700 11px var(--gt-mono);color:${color};">${flow.pct}% of world</span>
      </div>`
    ).join("")

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-crosshairs" style="margin-right:6px;"></i>${this._escapeHtml(item.name || "Strategic situation")}
      </div>
      <div style="display:inline-block;padding:2px 8px;border-radius:3px;background:${color};color:#000;font:700 10px var(--gt-mono,monospace);letter-spacing:1px;margin-bottom:8px;">
        ${(item.status || "monitoring").toUpperCase()} — STRATEGIC ${item.strategic_score || 0}
      </div>
      <div style="font:400 10px var(--gt-mono,monospace);color:#aaa;margin-bottom:10px;line-height:1.4;">
        ${this._escapeHtml(item.pressure_summary || "")}
      </div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Story clusters</span>
          <span class="detail-value" style="color:${color};">${item.direct_cluster_count || 0}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Sources</span>
          <span class="detail-value">${item.source_count || 0}</span>
        </div>
        ${item.theater ? `<div class="detail-field"><span class="detail-label">Theater</span><span class="detail-value">${this._escapeHtml(item.theater)}</span></div>` : ""}
      </div>
      ${signalHtml ? `<div style="margin:10px 0;"><div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">LIVE SIGNALS</div><div style="display:flex;flex-wrap:wrap;gap:4px;">${signalHtml}</div></div>` : ""}
      ${flowRows ? `<div style="margin:10px 0;"><div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">FLOW EXPOSURE</div>${flowRows}</div>` : ""}
      ${headlinesHtml ? `<div style="margin:10px 0;"><div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">DIRECT REPORTING</div>${headlinesHtml}</div>` : ""}
      ${item.theater ? `<button class="detail-track-btn" style="background:rgba(255,152,0,0.15);border-color:rgba(255,152,0,0.3);color:#ffa726;font-weight:700;" data-action="click->globe#highlightTheater" data-theater="${this._escapeHtml(item.theater)}">
        <i class="fa-solid fa-layer-group" style="margin-right:4px;"></i>Highlight ${this._escapeHtml(item.theater)}
      </button>` : ""}
      <button class="detail-track-btn" style="background:rgba(38,198,218,0.15);border-color:rgba(38,198,218,0.3);color:#26c6da;" data-action="click->globe#selectContextNode" data-kind="${this._escapeHtml(item.kind || "entity")}" data-id="${this._escapeHtml(item.node_id || item.name || "")}" data-title="${this._escapeHtml(item.name || "Strategic node")}" data-summary="${this._escapeHtml(item.pressure_summary || "")}">
        <i class="fa-solid fa-diagram-project" style="margin-right:4px;"></i>Open Graph Context
      </button>
      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype.showStrategicSituationFromList = function(event) {
    const id = event.currentTarget.dataset.id
    const item = (this._strategicSituationData || []).find(entry =>
      `${entry.id || entry.node_id || entry.name}` === `${id}`
    )
    if (!item) return
    this._flyToStrategicSituation(item)
  }

  // ── Explore area — scoped layer reveal (only layers with signals, viewport-bounded) ──

  GlobeController.prototype.revealPulseConnections = function(event) {
    const btn = event.currentTarget

    // Toggle off: hide layers we enabled and deselect country
    if (btn.dataset.revealed === "true") {
      (this._revealedLayers || []).forEach(toggle => this._disableLayer(toggle))
      this._revealedLayers = []
      if (this._revealedCountry) {
        this.selectedCountries.delete(this._revealedCountry)
        this._updateSelectedCountriesBbox()
        this.updateBorderColors()
        this._updateDeselectBtn()
        this._revealedCountry = null
      }
      btn.dataset.revealed = "false"
      btn.innerHTML = `<i class="fa-solid fa-eye" style="margin-right:4px;"></i>Explore This Area`
      btn.style.background = "rgba(244,67,54,0.2)"
      btn.style.borderColor = "rgba(244,67,54,0.4)"
      btn.style.color = "#f44336"
      this._toast("Layers hidden", "success")
      return
    }

    const lat = parseFloat(btn.dataset.lat)
    const lng = parseFloat(btn.dataset.lng)
    let signals = {}
    try { signals = JSON.parse(btn.dataset.signals) } catch {}

    const Cesium = window.Cesium

    // Fly to area at ~300km altitude — tight viewport scopes data fetches
    btn.innerHTML = `<i class="fa-solid fa-spinner fa-spin" style="margin-right:4px;"></i>Flying to area...`
    btn.disabled = true

    this._revealedLayers = []
    this._revealedCountry = null

    // Ensure border GeoJSON is loaded (needed for country detection) — don't wait for it
    if (!this.bordersLoaded && this.loadBorders) {
      this.loadBorders()
    }

    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, 400000),
      duration: 1.5,
      complete: () => {
        // 1. Try to select the country (borders may have loaded during the 1.5s fly)
        if (this._countryFeatures?.length) {
          const countryName = findCountryAtPoint(this._countryFeatures, lat, lng)
          if (countryName && !this.selectedCountries.has(countryName)) {
            if (!this.bordersVisible && this.hasBordersToggleTarget) {
              this.bordersToggleTarget.checked = true
              this.toggleBorders()
              this._revealedLayers.push("bordersToggle")
            }
            this.toggleCountrySelection(countryName)
            this._revealedCountry = countryName
          }
        }

        // 2. Enable context layers
        const enabled = []

        if (signals.gps_jamming) {
          this._enableLayer("gpsJammingToggle")
          this._revealedLayers.push("gpsJammingToggle")
          enabled.push("GPS jamming")
        }
        if (signals.internet_outage) {
          this._enableLayer("outagesToggle")
          this._revealedLayers.push("outagesToggle")
          enabled.push("internet outages")
        }

        // Always show conflicts + news
        this._enableLayer("conflictsToggle")
        this._revealedLayers.push("conflictsToggle")
        enabled.push("conflicts")

        this._enableLayer("newsToggle")
        this._revealedLayers.push("newsToggle")
        enabled.push("news")

        btn.innerHTML = `<i class="fa-solid fa-eye-slash" style="margin-right:4px;"></i>Hide Layers`
        btn.style.background = "rgba(76,175,80,0.2)"
        btn.style.borderColor = "rgba(76,175,80,0.4)"
        btn.style.color = "#4caf50"
        btn.disabled = false
        btn.dataset.revealed = "true"

        const countryLabel = this._revealedCountry ? ` (${this._revealedCountry})` : ""
        this._toast(`Exploring${countryLabel}`, "success")
      },
    })
  }

  // ── Strike arc detail panel ────────────────────────────────

  GlobeController.prototype.showStrikeArcDetail = function(arc) {
    const width = Math.min(1.5 + arc.count * 0.2, 5).toFixed(1)
    const intensity = arc.count >= 15 ? "Very high" : arc.count >= 8 ? "High" : arc.count >= 4 ? "Moderate" : "Low"

    let headlinesHtml = ""
    const samples = arc.sample_headlines || []
    if (samples.length) {
      headlinesHtml = samples.map(h =>
        `<div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.4;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">${this._escapeHtml(h)}</div>`
      ).join("")
    }

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#f44336;">
        <i class="fa-solid fa-arrows-left-right" style="margin-right:6px;"></i>STRIKE ARC
      </div>
      <div style="font:600 14px var(--gt-sans,sans-serif);color:rgba(220,230,245,0.85);margin:4px 0 8px;">
        ${this._escapeHtml(arc.from_name)} → ${this._escapeHtml(arc.to_name)}
      </div>

      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Mentions</span>
          <span class="detail-value" style="color:#f44336;">${arc.count}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Intensity</span>
          <span class="detail-value">${intensity}</span>
        </div>
      </div>

      <div style="margin:10px 0;">
        <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:4px;">ARC THICKNESS</div>
        <div style="font:400 10px var(--gt-sans,sans-serif);color:rgba(200,210,225,0.4);line-height:1.5;">
          Width scales with mention count (${width}px). More headlines mentioning this actor pair → thicker arc. Extracted from ${arc.count} headlines that mention both "${this._escapeHtml(arc.from_name)}" and "${this._escapeHtml(arc.to_name)}" with directional attack language.
        </div>
      </div>

      ${headlinesHtml ? `
        <div style="margin:10px 0;">
          <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">SAMPLE HEADLINES</div>
          ${headlinesHtml}
        </div>
      ` : ""}
    `
    this.detailPanelTarget.style.display = ""
  }

  // ── Helper: enable a layer toggle if it exists and is off ──

  GlobeController.prototype._enableLayer = function(toggleName) {
    const targetName = `${toggleName}Target`
    const hasTarget = `has${toggleName[0].toUpperCase()}${toggleName.slice(1)}Target`
    if (this[hasTarget]) {
      const toggle = this[targetName]
      if (toggle && !toggle.checked) {
        toggle.checked = true
        toggle.dispatchEvent(new Event("change"))
      }
    }
  }

  // ── Helper: disable a layer toggle ──────────────────────────

  GlobeController.prototype._disableLayer = function(toggleName) {
    const targetName = `${toggleName}Target`
    const hasTarget = `has${toggleName[0].toUpperCase()}${toggleName.slice(1)}Target`
    if (this[hasTarget]) {
      const toggle = this[targetName]
      if (toggle && toggle.checked) {
        toggle.checked = false
        toggle.dispatchEvent(new Event("change"))
      }
    }
  }

  // ── Signal chip click — enable layer + fly to area ─────────

  GlobeController.prototype.pulseSignalClick = function(event) {
    const signal = event.currentTarget.dataset.signal
    const lat = parseFloat(event.currentTarget.dataset.lat)
    const lng = parseFloat(event.currentTarget.dataset.lng)
    if (isNaN(lat) || isNaN(lng)) return

    const Cesium = window.Cesium

    // Fly first, then enable layer — viewport-aware fetch only loads nearby data
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, 500000),
      duration: 1.0,
      complete: () => {
        const layerToggles = {
          flights: "flightsToggle",
          gpsJamming: "gpsJammingToggle",
          fires: "firesToggle",
          conflicts: "conflictsToggle",
        }
        const toggle = layerToggles[signal]
        if (toggle) this._enableLayer(toggle)
      },
    })
  }

  // ── Time ago helper ────────────────────────────────────────

  // Find which hex cell contains a given lat/lng using point-in-polygon test
  GlobeController.prototype._findHexAtPosition = function(lat, lng) {
    if (!this._hexCellData?.length) return null
    for (const cell of this._hexCellData) {
      if (!cell.vertices || cell.vertices.length !== 6) continue
      if (cell.intensity < 0.01) continue
      // Quick bounding-box check first
      const lats = cell.vertices.map(v => v[0])
      const lngs = cell.vertices.map(v => v[1])
      if (lat < Math.min(...lats) || lat > Math.max(...lats)) continue
      if (lng < Math.min(...lngs) || lng > Math.max(...lngs)) continue
      // Ray-casting point-in-polygon
      let inside = false
      for (let i = 0, j = 5; i < 6; j = i++) {
        const yi = cell.vertices[i][0], xi = cell.vertices[i][1]
        const yj = cell.vertices[j][0], xj = cell.vertices[j][1]
        if (((yi > lat) !== (yj > lat)) && (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
          inside = !inside
        }
      }
      if (inside) return cell
    }
    return null
  }

  // ── Strike Arc / Hex Theater toggles ─────────────────────

  GlobeController.prototype.toggleStrikeArcs = function() {
    this._strikeArcsVisible = this.hasStrikeArcsToggleTarget && this.strikeArcsToggleTarget.checked
    this._renderConflictPulse()
  }

  GlobeController.prototype.toggleHexTheater = function() {
    this._hexTheaterVisible = this.hasHexTheaterToggleTarget && this.hexTheaterToggleTarget.checked
    this._renderConflictPulse()
  }

  GlobeController.prototype._timeAgo = function(date) {
    const seconds = Math.floor((Date.now() - date.getTime()) / 1000)
    if (seconds < 60) return "just now"
    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return `${minutes}m ago`
    const hours = Math.floor(minutes / 60)
    if (hours < 24) return `${hours}h ago`
    const days = Math.floor(hours / 24)
    return `${days}d ago`
  }

  // ── Hex cell click → show linked situation ──────────────────

  GlobeController.prototype._showHexDetail = function(cell) {
    const situation = cell.situation || "Unlinked area"
    const theater = cell.theater || ""
    const zone = cell.zone_key
      ? this._conflictPulseData?.find(z => z.cell_key === cell.zone_key)
      : null

    // Resolve the hex's own location using country borders
    let localName = ""
    if (this._countryFeatures) {
      try {
        const country = findCountryAtPoint(this._countryFeatures, cell.lat, cell.lng)
        if (country) localName = country
      } catch(e) {}
    }
    // Fallback: use a rough label from lat/lng
    if (!localName) {
      localName = `${cell.lat.toFixed(1)}°, ${cell.lng.toFixed(1)}°`
    }

    // Show parent zone's headlines if available
    let headlinesHtml = ""
    if (zone) {
      const articles = zone.top_articles || []
      const headlines = articles.length > 0
        ? articles.slice(0, 3).map(a => {
            const timeAgo = a.published_at ? this._timeAgo(new Date(a.published_at)) : ""
            return `<a href="${this._safeUrl(a.url)}" target="_blank" rel="noopener" style="display:block;text-decoration:none;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
              <div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.3;">${this._escapeHtml(a.title?.substring(0, 70))}</div>
              <div style="font:400 9px var(--gt-mono,monospace);color:#666;margin-top:2px;">${this._escapeHtml(a.publisher || a.source || "")} · ${timeAgo}</div>
            </a>`
          }).join("")
        : (zone.top_headlines || []).slice(0, 3).map(h =>
            `<div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.4;padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.05);">${this._escapeHtml(h?.substring(0, 70))}</div>`
          ).join("")
      if (headlines) {
        headlinesHtml = `<div style="margin-top:8px;">
          <div style="font:600 9px var(--gt-mono);text-transform:uppercase;letter-spacing:1px;color:rgba(255,152,0,0.6);margin-bottom:6px;">Related Headlines</div>
          ${headlines}
        </div>`
      }
    }

    // Trend info from parent zone
    const trendColors = {surging:"#f44336",active:"#f44336",escalating:"#ff9800",elevated:"#ffc107",baseline:"#66bb6a"}
    const trendHtml = zone ? `<div style="font:600 10px var(--gt-mono);color:${trendColors[zone.escalation_trend] || "#ff9800"};letter-spacing:0.5px;margin:4px 0;">${(zone.escalation_trend || "").toUpperCase()} — PULSE ${zone.pulse_score}</div>` : ""

    // Connection line: "Lebanon → Israel-Palestine → Middle East / Iran War"
    const connectionParts = [localName]
    if (situation && situation !== localName && situation !== "Unlinked area") connectionParts.push(situation)
    if (theater) connectionParts.push(theater)
    const connectionHtml = connectionParts.length > 1
      ? `<div style="font:400 10px var(--gt-mono,monospace);color:rgba(255,152,0,0.5);margin:4px 0 6px;letter-spacing:0.3px;">${connectionParts.map(p => this._escapeHtml(p)).join(' → ')}</div>`
      : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign"><i class="fa-solid fa-hexagon-nodes" style="color:#ff9800;margin-right:6px;"></i>${this._escapeHtml(localName)}</div>
      ${connectionHtml}
      ${trendHtml}
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Articles</span>
          <span class="detail-value">${cell.count}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Intensity</span>
          <span class="detail-value">${(cell.intensity * 100).toFixed(0)}%</span>
        </div>
        ${zone ? `<div class="detail-field">
          <span class="detail-label">Reports (24h)</span>
          <span class="detail-value">${zone.count_24h || "—"}</span>
        </div>` : ""}
        ${zone ? `<div class="detail-field">
          <span class="detail-label">Sources</span>
          <span class="detail-value">${zone.source_count || "—"}</span>
        </div>` : ""}
      </div>
      ${headlinesHtml}
      ${zone ? `<button class="detail-track-btn" style="background:rgba(244,67,54,0.2);border-color:rgba(244,67,54,0.4);color:#f44336;"
        data-action="click->globe#flyToConflictZone" data-zone-key="${this._escapeHtml(zone.cell_key)}">
        <i class="fa-solid fa-crosshairs" style="margin-right:4px;"></i>Go to ${this._escapeHtml(situation)}
      </button>` : ""}
      ${theater ? `<button class="detail-track-btn" style="background:rgba(255,152,0,0.15);border-color:rgba(255,152,0,0.3);color:#ffa726;"
        data-action="click->globe#highlightTheater" data-theater="${this._escapeHtml(theater)}">
        <i class="fa-solid fa-layer-group" style="margin-right:4px;"></i>Highlight ${this._escapeHtml(theater)}
      </button>` : ""}
    `
    this.detailPanelTarget.style.display = ""

    // Auto-highlight theater + ripple animation
    if (theater) {
      this._highlightedTheater = null
      this.highlightTheater({ currentTarget: { dataset: { theater, skipContext: "true" } } })
      this._rippleFromHex(cell)
    }
  }

  // ── Ripple animation: wavefront pulses across hex grid from click point ──

  GlobeController.prototype._rippleFromHex = function(clickedCell) {
    if (!this._hexCellData?.length) return
    const Cesium = window.Cesium
    const ds = this._ds["conflictPulse"]
    if (!ds) return

    // Cancel previous ripple
    if (this._rippleFrame) { cancelAnimationFrame(this._rippleFrame); this._rippleFrame = null }

    // Collect theater siblings with distance from click point (in degrees)
    const siblings = []
    let maxDist = 0
    this._hexCellData.forEach((h, i) => {
      if (h.theater !== clickedCell.theater) return
      const d = Math.sqrt((h.lat - clickedCell.lat) ** 2 + (h.lng - clickedCell.lng) ** 2)
      maxDist = Math.max(maxDist, d)
      siblings.push({ idx: i, dist: d })
    })
    if (!siblings.length) return

    // Wavefront settings
    const speed = maxDist / 1.2        // degrees per second — full reach in 1.2s
    const waveFront = 4.0              // width of the bright band in degrees
    const startTime = performance.now()
    const totalDuration = 2000         // ms total animation

    const highlightColor = Cesium.Color.fromCssColorString("#ff6d00")
    const dimColor = Cesium.Color.fromCssColorString("#ff6d00")

    const animate = () => {
      const elapsed = (performance.now() - startTime) / 1000 // seconds
      const waveDist = elapsed * speed // how far the wavefront has traveled

      siblings.forEach(s => {
        const entity = ds.entities.getById(`cpulse-hex-${s.idx}`)
        if (!entity?.polygon) return

        // How far is this hex from the wavefront center?
        const delta = waveDist - s.dist

        if (delta < 0) {
          // Wavefront hasn't reached this hex yet — dim
          entity.polygon.material = dimColor.withAlpha(0.08)
          entity.polygon.outlineColor = dimColor.withAlpha(0.15)
        } else if (delta < waveFront) {
          // Inside the wavefront band — bright flash, intensity based on position in band
          const bandT = delta / waveFront // 0 = leading edge, 1 = trailing edge
          const flash = 1.0 - bandT * 0.5 // bright at leading edge, dimmer at trailing
          entity.polygon.material = highlightColor.withAlpha(0.3 + flash * 0.5)
          entity.polygon.outlineColor = highlightColor.withAlpha(0.5 + flash * 0.5)
        } else {
          // Wavefront has passed — settle to steady highlight
          entity.polygon.material = highlightColor.withAlpha(0.5)
          entity.polygon.outlineColor = highlightColor.withAlpha(0.85)
        }
      })

      this._requestRender()

      if (performance.now() - startTime < totalDuration) {
        this._rippleFrame = requestAnimationFrame(animate)
      } else {
        this._rippleFrame = null
      }
    }

    this._rippleFrame = requestAnimationFrame(animate)
  }

  // ── Fly to a zone by cell_key ────────────────────────────────

  GlobeController.prototype.flyToConflictZone = function(event) {
    const key = event.currentTarget.dataset.zoneKey
    const zone = this._conflictPulseData?.find(z => z.cell_key === key)
    if (!zone) return
    this._flyToConflictPulse(zone)
    // Also highlight the theater
    if (zone.theater) {
      this.highlightTheater({ currentTarget: { dataset: { theater: zone.theater, skipContext: "true" } } })
    }
  }

  // ── Highlight theater: brighten connected hexes + arcs, dim others ──

  GlobeController.prototype.highlightTheater = function(event) {
    const theater = event.currentTarget.dataset.theater
    const skipContext = event.currentTarget.dataset.skipContext === "true"
    if (!theater || this._highlightedTheater === theater) {
      // Toggle off — reset all to normal and turn hex layer back off if we turned it on
      this._highlightedTheater = null
      if (this._hexLayerAutoEnabled) {
        this._hexTheaterVisible = false
        this._strikeArcsVisible = false
        if (this.hasHexTheaterToggleTarget) this.hexTheaterToggleTarget.checked = false
        if (this.hasStrikeArcsToggleTarget) this.strikeArcsToggleTarget.checked = false
        this._hexLayerAutoEnabled = false
      }
      this._renderConflictPulse()
      return
    }
    this._highlightedTheater = theater
    if (!skipContext && this._setTheaterSelectedContext) this._setTheaterSelectedContext(theater)

    // Auto-enable hex theater + strike arcs if they're off
    if (!this._hexTheaterVisible) {
      this._hexTheaterVisible = true
      this._strikeArcsVisible = true
      if (this.hasHexTheaterToggleTarget) this.hexTheaterToggleTarget.checked = true
      if (this.hasStrikeArcsToggleTarget) this.strikeArcsToggleTarget.checked = true
      this._hexLayerAutoEnabled = true
      // Re-render with hexes/arcs visible before applying highlight
      this._renderConflictPulse()
    }

    const Cesium = window.Cesium
    const ds = this._ds["conflictPulse"]
    if (!ds) return

    // Dim/brighten hex cells by theater
    this._conflictPulseEntities.forEach(entity => {
      if (!entity.polygon) return
      const props = entity.properties
      const entityTheater = props?.theater?.getValue()
      const isMatch = entityTheater === theater

      entity.polygon.material = Cesium.Color.fromCssColorString(isMatch ? "#ff6d00" : "#444").withAlpha(isMatch ? 0.6 : 0.03)
      entity.polygon.outlineColor = Cesium.Color.fromCssColorString(isMatch ? "#ff6d00" : "#333").withAlpha(isMatch ? 0.9 : 0.05)
    })

    // Also dim/brighten situation nodes (points/labels/rings)
    this._conflictPulseEntities.forEach(entity => {
      if (!entity.point && !entity.label && !entity.ellipse) return
      const entityId = `${entity.id || ""}`
      if (!entityId.startsWith("cpulse-")) return
      if (entityId.startsWith("cpulse-strat-") || entityId.startsWith("cpulse-arc-") || entityId.startsWith("cpulse-hex-")) return
      const zoneKey = decodeURIComponent(entityId.replace(/^cpulse-(?:lbl-|ring-|core-|pulse-)?/, ""))
      const zone = this._conflictPulseData?.find(item => `${item.cell_key}` === zoneKey)
      if (!zone) return
      const isMatch = zone.theater === theater
      if (entity.point) {
        entity.point.color = entity.point.color?.getValue?.(Cesium.JulianDate.now())?.withAlpha(isMatch ? 1.0 : 0.15)
      }
      if (entity.label) {
        entity.label.fillColor = Cesium.Color.WHITE.withAlpha(isMatch ? 1.0 : 0.1)
      }
    })

    this._requestRender()
  }

  // ═══════════════════════════════════════════════════════════
  // Situations Right Panel — theater-grouped, expandable cards
  // ═══════════════════════════════════════════════════════════

  GlobeController.prototype._renderSituationPanel = function() {
    const list = this.hasSitListTarget ? this.sitListTarget : null
    const countEl = this.hasSitCountTarget ? this.sitCountTarget : null
    if (!list) return

    const zones = this._conflictPulseZones || []
    const strategic = this._strategicSituationData || []
    const snapshotStatus = this._conflictPulseSnapshotStatus || "pending"
    if (countEl) {
      const base = `${zones.length} zone${zones.length !== 1 ? "s" : ""}`
      const strategicSuffix = strategic.length ? ` · ${strategic.length} strategic` : ""
      const suffix = snapshotStatus === "ready" ? "" : ` · ${this._statusLabel(snapshotStatus, "snapshot")}`
      countEl.textContent = `${base}${strategicSuffix}${suffix}`
    }

    if (!zones.length && !strategic.length) {
      const emptyLabel = {
        pending: "Conflict pulse snapshot pending.",
        stale: "Showing no active zones from the latest stored snapshot.",
        error: "Conflict pulse snapshot unavailable.",
      }[snapshotStatus] || "No active zones."
      list.innerHTML = `<div style="padding:16px 14px;color:var(--gt-text-dim);font:500 11px var(--gt-mono);">${this._escapeHtml(emptyLabel)}</div>`
      return
    }

    // Group by theater
    const theaters = {}
    zones.forEach(z => {
      const t = z.theater || "Other"
      ;(theaters[t] ||= []).push(z)
    })

    // Sort theaters by max pulse_score descending
    const sorted = Object.entries(theaters).sort((a, b) => {
      const maxA = Math.max(...a[1].map(z => z.pulse_score))
      const maxB = Math.max(...b[1].map(z => z.pulse_score))
      return maxB - maxA
    })

    // Track expanded state
    if (!this._sitExpanded) this._sitExpanded = {}

    const trendColors = { surging: "#f44336", active: "#f44336", escalating: "#ff9800", elevated: "#ffc107", baseline: "#66bb6a" }
    const trendArrows = { surging: "▲", escalating: "↗", active: "●", elevated: "→", baseline: "↓" }

    let html = ""
    if (snapshotStatus !== "ready") {
      html += `<div style="padding:0 0 10px;display:flex;align-items:center;gap:6px;flex-wrap:wrap;">${this._statusChip(snapshotStatus, this._statusLabel(snapshotStatus, "snapshot"))}</div>`
    }
    if (strategic.length) {
      html += `<div class="sit-theater">`
      html += `<div class="sit-theater-header"><span class="sit-theater-arrow">▾</span><span class="sit-theater-name">Strategic Situations</span><span class="sit-theater-count">${strategic.length}</span></div>`
      html += `<div class="sit-theater-body">`
      strategic.forEach((item, idx) => {
        const color = { critical: "#ff7043", elevated: "#ffca28", monitoring: "#26c6da" }[item.status] || "#26c6da"
        const topArticle = (item.top_articles || [])[0]
        const strategicId = item.id || item.node_id || item.name || `strategic-${idx}`
        html += `<div class="sit-zone sit-zone--summary" data-zone-key="${this._escapeHtml(item.id || `strategic-${idx}`)}">
          <div class="sit-zone-header" data-action="click->globe#showStrategicSituationFromList" data-id="${this._escapeHtml(strategicId)}">
            <span class="sit-zone-name">${this._escapeHtml(item.name || "Strategic node")}</span>
            <span class="sit-zone-score" style="color:${color};">${item.strategic_score || 0} <span class="sit-zone-trend">${this._escapeHtml((item.status || "monitoring").toUpperCase())}</span></span>
          </div>
          <div class="sit-zone-summary">
            <div class="sit-zone-headline">${this._escapeHtml(item.pressure_summary || (item.theater || "Strategic pressure"))}</div>
            <div class="sit-zone-meta">${this._escapeHtml([item.theater, `${item.source_count || 0} sources`, `${item.direct_cluster_count || 0} clusters`].filter(Boolean).join(" · "))}</div>
            ${topArticle ? `<button type="button" data-action="click->globe#selectContextNode" data-kind="news_story_cluster" data-id="${this._escapeHtml(topArticle.cluster_id || "")}" data-title="${this._escapeHtml(topArticle.title || "Story cluster")}" data-summary="${this._escapeHtml(topArticle.publisher || topArticle.source || "")}" style="display:block;width:100%;padding:0;border:0;background:none;text-align:left;cursor:pointer;margin-top:8px;">
              <div class="sit-zone-headline">${this._escapeHtml(topArticle.title || "")}</div>
              <div class="sit-zone-meta">${this._escapeHtml(topArticle.publisher || topArticle.source || "")}</div>
            </button>` : ""}
          </div>
        </div>`
      })
      html += `</div></div>`
    }
    sorted.forEach(([theater, theaterZones], tIdx) => {
      const maxScore = Math.max(...theaterZones.map(z => z.pulse_score))
      const collapsed = maxScore < 40

      html += `<div class="sit-theater${collapsed ? " sit-theater--collapsed" : ""}">`
      html += `<div class="sit-theater-header" data-action="click->globe#toggleSitTheater" data-idx="${tIdx}">
        <span class="sit-theater-arrow">${collapsed ? "▸" : "▾"}</span>
        <span class="sit-theater-name">${this._escapeHtml(theater)}</span>
        <span class="sit-theater-count">${theaterZones.length}</span>
      </div>`
      html += `<div class="sit-theater-body"${collapsed ? ' style="display:none;"' : ""}>`

      theaterZones.sort((a, b) => b.pulse_score - a.pulse_score).forEach(zone => {
        const color = trendColors[zone.escalation_trend] || "#ff9800"
        const arrow = trendArrows[zone.escalation_trend] || ""
        const key = zone.cell_key
        const state = this._sitExpanded[key] || "collapsed"

        html += `<div class="sit-zone sit-zone--${state}" data-zone-key="${this._escapeHtml(key)}">`

        // Always: compact header line
        html += `<div class="sit-zone-header" data-action="click->globe#toggleSitZone" data-zone-key="${this._escapeHtml(key)}">
          <span class="sit-zone-name">${this._escapeHtml(zone.situation_name || "Developing")}</span>
          <span class="sit-zone-score" style="color:${color};">${zone.pulse_score} ${arrow} <span class="sit-zone-trend">${zone.escalation_trend.toUpperCase()}</span></span>
        </div>`

        // Summary state: top headline + signal count chips
        if (state === "summary" || state === "expanded") {
          const topArticle = (zone.top_articles || [])[0]
          html += `<div class="sit-zone-summary">`
          if (topArticle) {
            const timeAgo = topArticle.published_at ? this._timeAgo(new Date(topArticle.published_at)) : ""
            if (topArticle.cluster_id) {
              html += `<button type="button" data-action="click->globe#selectContextNode" data-kind="news_story_cluster" data-id="${this._escapeHtml(topArticle.cluster_id)}" data-title="${this._escapeHtml(topArticle.title?.substring(0, 90) || "Story cluster")}" data-summary="${this._escapeHtml((topArticle.publisher || topArticle.source || "") + (timeAgo ? ` · ${timeAgo}` : ""))}" style="display:block;width:100%;padding:0;border:0;background:none;text-align:left;cursor:pointer;">
                <div class="sit-zone-headline">${this._escapeHtml(topArticle.title?.substring(0, 90))}</div>
                <div class="sit-zone-meta">${this._escapeHtml(topArticle.publisher || topArticle.source || "")} · ${timeAgo}</div>
              </button>`
            } else {
              html += `<div class="sit-zone-headline">${this._escapeHtml(topArticle.title?.substring(0, 90))}</div>
                <div class="sit-zone-meta">${this._escapeHtml(topArticle.publisher || topArticle.source || "")} · ${timeAgo}</div>`
            }
          }
          // Signal count chips (compact)
          const s = zone.cross_layer_signals || {}
          const chips = []
          if (s.military_flights) chips.push(`<span class="sit-chip sit-chip--mil">🛩 ${s.military_flights}</span>`)
          if (s.gps_jamming) chips.push(`<span class="sit-chip sit-chip--jam">📡 ${s.gps_jamming}%</span>`)
          if (s.fire_hotspots) chips.push(`<span class="sit-chip sit-chip--fire">🔥 ${s.fire_hotspots}</span>`)
          if (s.known_conflict_zone) chips.push(`<span class="sit-chip sit-chip--hist">📊 ${s.known_conflict_zone}</span>`)
          if (s.internet_outage) chips.push(`<span class="sit-chip sit-chip--out">⚡ outage</span>`)
          if (chips.length) html += `<div class="sit-zone-chips">${chips.join("")}</div>`
          html += `</div>`
        }

        // Expanded state: full detail
        if (state === "expanded") {
          html += `<div class="sit-zone-detail">`

          // Stats
          html += `<div class="sit-zone-stats">
            <span>${zone.count_24h} reports today</span> · <span>${zone.source_count} sources</span> · <span>spike ${zone.spike_ratio}x</span>
          </div>`

          // Top stories
          const articles = (zone.top_articles || []).slice(0, 5)
          if (articles.length) {
            html += `<div class="sit-section-label">TOP STORIES</div>`
            articles.forEach(a => {
              const timeAgo = a.published_at ? this._timeAgo(new Date(a.published_at)) : ""
              if (a.cluster_id) {
                html += `<div class="sit-article" style="display:flex;gap:8px;align-items:flex-start;">
                  <button type="button" data-action="click->globe#selectContextNode" data-kind="news_story_cluster" data-id="${this._escapeHtml(a.cluster_id)}" data-title="${this._escapeHtml(a.title || "Story cluster")}" data-summary="${this._escapeHtml((a.publisher || a.source || "") + (timeAgo ? ` · ${timeAgo}` : ""))}" style="flex:1;padding:0;border:0;background:none;text-align:left;cursor:pointer;">
                    <div class="sit-article-title">${this._escapeHtml(a.title)}</div>
                    <div class="sit-article-meta">${this._escapeHtml(a.publisher || a.source || "")} · ${timeAgo}</div>
                  </button>
                  ${a.url ? `<a href="${this._safeUrl(a.url)}" target="_blank" rel="noopener" style="color:rgba(200,210,225,0.45);text-decoration:none;"><i class="fa-solid fa-arrow-up-right-from-square"></i></a>` : ""}
                </div>`
              } else {
                html += `<a href="${this._safeUrl(a.url)}" target="_blank" rel="noopener" class="sit-article">
                  <div class="sit-article-title">${this._escapeHtml(a.title)}</div>
                  <div class="sit-article-meta">${this._escapeHtml(a.publisher || a.source || "")} · ${timeAgo}</div>
                </a>`
              }
            })
            if (zone.count_24h > 5) html += `<div class="sit-more">+${zone.count_24h - 5} more</div>`
          }

          // Why these layers matter
          const signals = zone.cross_layer_signals || {}
          const context = zone.signal_context || {}
          const signalEntries = Object.entries(signals).filter(([_, v]) => v)
          if (signalEntries.length) {
            html += `<div class="sit-section-label">WHY THESE LAYERS MATTER</div>`
            const signalIcons = {
              military_flights: "🛩",
              gps_jamming: "📡",
              fire_hotspots: "🔥",
              known_conflict_zone: "📊",
              internet_outage: "⚡",
            }
            const signalLabels = {
              military_flights: "military flights",
              gps_jamming: "GPS jamming",
              fire_hotspots: "fire hotspots",
              known_conflict_zone: "historical incidents",
              internet_outage: "internet outage",
            }
            signalEntries.forEach(([key, val]) => {
              const icon = signalIcons[key] || "📎"
              const label = signalLabels[key] || key.replace(/_/g, " ")
              const desc = context[key] || ""
              const valStr = typeof val === "number" ? (key === "gps_jamming" ? `${val}%` : val) : val
              html += `<div class="sit-signal">
                <div class="sit-signal-header">${icon} ${valStr} ${this._escapeHtml(label)}</div>
                ${desc ? `<div class="sit-signal-desc">${this._escapeHtml(desc)}</div>` : ""}
              </div>`
            })
          }

          // Explore button
          html += `<button class="sit-explore-btn" data-action="click->globe#exploreSituation" data-zone-key="${this._escapeHtml(key)}">
            Explore this area →
          </button>`

          html += `</div>`
        }

        html += `</div>` // .sit-zone
      })

      html += `</div></div>` // .sit-theater-body, .sit-theater
    })

    list.innerHTML = html
  }

  // ── Toggle theater group collapse ──────────────────────────

  GlobeController.prototype.toggleSitTheater = function(event) {
    const header = event.currentTarget
    const theater = header.closest(".sit-theater")
    if (!theater) return
    const body = theater.querySelector(".sit-theater-body")
    const arrow = header.querySelector(".sit-theater-arrow")
    if (!body) return
    const hidden = body.style.display === "none"
    body.style.display = hidden ? "" : "none"
    if (arrow) arrow.textContent = hidden ? "▾" : "▸"
    theater.classList.toggle("sit-theater--collapsed", !hidden)
  }

  // ── Toggle zone card state: collapsed → summary → expanded → collapsed ──

  GlobeController.prototype.toggleSitZone = function(event) {
    const key = event.currentTarget.dataset.zoneKey
    if (!this._sitExpanded) this._sitExpanded = {}
    const current = this._sitExpanded[key] || "collapsed"
    const next = current === "collapsed" ? "summary" : current === "summary" ? "expanded" : "collapsed"
    this._sitExpanded[key] = next
    this._renderSituationPanel()
  }

  // ── Explore situation: scoped layer reveal ─────────────────

  GlobeController.prototype.exploreSituation = function(event) {
    const key = event.currentTarget.dataset.zoneKey
    const zone = this._conflictPulseZones?.find(z => z.cell_key === key)
    if (!zone) return

    const signals = zone.cross_layer_signals || {}
    const Cesium = window.Cesium

    // Save current camera for back navigation
    this._savedExploreCamera = {
      position: Cesium.Cartesian3.clone(this.viewer.camera.position),
      heading: this.viewer.camera.heading,
      pitch: this.viewer.camera.pitch,
      roll: this.viewer.camera.roll,
    }

    // Track which layers we enable so we can undo
    this._exploreRevealedLayers = []

    // Fly to zone
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat, 800000),
      duration: 1.5,
      complete: () => {
        // Enable only layers with actual signals
        const layerMap = {
          military_flights: "flightsToggle",
          gps_jamming: "gpsJammingToggle",
          fire_hotspots: "firesToggle",
          known_conflict_zone: "conflictsToggle",
          internet_outage: "internetOutagesToggle",
        }
        for (const [signal, toggle] of Object.entries(layerMap)) {
          if (signals[signal]) {
            this._enableLayer(toggle)
            this._exploreRevealedLayers.push(toggle)
          }
        }
        this._toast(`Exploring ${zone.situation_name || "situation"}`, "success")
      },
    })
  }
}
