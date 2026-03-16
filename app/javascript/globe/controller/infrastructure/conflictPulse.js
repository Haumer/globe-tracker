import { getDataSource } from "../../utils"

export function applyConflictPulseMethods(GlobeController) {

  // ── Lifecycle ──────────────────────────────────────────────

  GlobeController.prototype._startConflictPulse = function() {
    this._conflictPulseData = []
    this._conflictPulseEntities = []
    this._conflictPulsePrev = {}  // track previous state for surge detection
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
      this._strikeArcData = data.strike_arcs || []
      this._hexCellData = data.hex_cells || []
      this._renderConflictPulse()
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
    if (this._hexCellData?.length) {
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
    if (this._strikeArcData?.length) {
      this._strikeArcData.forEach((arc, idx) => {
        if (arc.count < 2) return
        const t = Math.min(arc.count / 20, 1)
        const arcColor = Cesium.Color.fromCssColorString("#f44336")

        // Build great-circle arc positions
        const arcPositions = this._buildArcPositions(arc.from_lat, arc.from_lng, arc.to_lat, arc.to_lng, 30)
        if (!arcPositions.length) return

        const line = ds.entities.add({
          id: `cpulse-arc-${idx}`,
          polyline: {
            positions: arcPositions,
            width: Math.min(1.5 + arc.count * 0.2, 5),
            material: new Cesium.PolylineGlowMaterialProperty({
              glowPower: 0.15,
              color: arcColor.withAlpha(0.3 + t * 0.4),
            }),
          },
        })
        this._conflictPulseEntities.push(line)

        // Small label at midpoint
        const midIdx = Math.floor(arcPositions.length / 2)
        const midLabel = ds.entities.add({
          id: `cpulse-arc-lbl-${idx}`,
          position: arcPositions[midIdx],
          label: {
            text: `${arc.from_name}→${arc.to_name} (${arc.count})`,
            font: "9px monospace",
            fillColor: arcColor.withAlpha(0.7),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 2,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            pixelOffset: new Cesium.Cartesian2(0, -6),
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
            scaleByDistance: new Cesium.NearFarScalar(5e5, 0.8, 8e6, 0.0),
            translucencyByDistance: new Cesium.NearFarScalar(5e5, 0.8, 8e6, 0.0),
          },
        })
        this._conflictPulseEntities.push(midLabel)
      })
    }

    // ── Layer 3: Situation nodes (pulse zones with names) ──
    this._conflictPulseData.forEach((zone, idx) => {
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
        id: `cpulse-ring-${idx}`,
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
          id: `cpulse-pulse-${idx}`,
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
          id: `cpulse-core-${idx}`,
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

      // Clickable billboard — always shown, size varies by tier
      const iconSize = score >= 70 ? 36 : (score >= 50 ? 32 : 24)
      const point = ds.entities.add({
        id: `cpulse-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat, 5500),
        billboard: {
          image: this._makePulseIcon("", color.toCssColorString(), score),
          width: iconSize,
          height: iconSize,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1e7, 0.4),
        },
        label: {
          text: zone.situation_name
            ? `${zone.situation_name.toUpperCase()} · ${score}`
            : (score >= 50 ? `${zone.escalation_trend.toUpperCase()} ${score}` : `${score}`),
          font: score >= 50 ? "bold 11px monospace" : "bold 9px monospace",
          fillColor: color.withAlpha(score >= 50 ? 0.95 : 0.7),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, iconSize / 2 + 4),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1e7, score >= 50 ? 0.3 : 0.2),
          translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, score >= 50 ? 1.5e7 : 8e6, 0.0),
        },
      })
      this._conflictPulseEntities.push(point)
    })
    ds.entities.resumeEvents()

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

  GlobeController.prototype._makePulseIcon = function(icon, color, score) {
    const key = `pulse-${icon}-${color}-${score}`
    if (this._iconCache?.[key]) return this._iconCache[key]
    if (!this._iconCache) this._iconCache = {}

    const size = 32
    const canvas = document.createElement("canvas")
    canvas.width = size; canvas.height = size
    const ctx = canvas.getContext("2d")

    // Circle background
    ctx.beginPath()
    ctx.arc(size / 2, size / 2, size / 2 - 1, 0, Math.PI * 2)
    ctx.fillStyle = "rgba(0,0,0,0.8)"
    ctx.fill()
    ctx.strokeStyle = color
    ctx.lineWidth = 2.5
    ctx.stroke()

    // Score text
    ctx.font = "bold 13px monospace"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = color
    ctx.fillText(score, size / 2, size / 2)

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

  GlobeController.prototype.showConflictPulseDetail = function(zone) {
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
          return `<a href="${this._safeUrl(a.url)}" target="_blank" rel="noopener" style="display:block;text-decoration:none;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
            <div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.3;">${this._escapeHtml(a.title)}</div>
            <div style="font:400 9px var(--gt-mono,monospace);color:#666;margin-top:2px;">${this._escapeHtml(a.source || "")} · tone ${a.tone || 0} · ${timeAgo}</div>
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
        <i class="fa-solid fa-eye" style="margin-right:4px;"></i>Reveal All Connected Layers
      </button>

      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${zone.lat}" data-lng="${zone.lng}">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
      </button>

      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("conflict", zone.lat, zone.lng)

    // Auto-highlight the theater this zone belongs to
    if (zone.theater) {
      this._highlightedTheater = null
      this.highlightTheater({ currentTarget: { dataset: { theater: zone.theater } } })
    }
  }

  // ── Reveal all connected layers ─────────────────────────────

  GlobeController.prototype.revealPulseConnections = function(event) {
    const btn = event.currentTarget

    // Toggle: if already revealed, hide all enabled layers
    if (btn.dataset.revealed === "true") {
      (this._revealedLayers || []).forEach(toggle => this._disableLayer(toggle))
      this._revealedLayers = []
      btn.dataset.revealed = "false"
      btn.innerHTML = `<i class="fa-solid fa-eye" style="margin-right:4px;"></i>Reveal All Connected Layers`
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

    // Step 1: Fly to area FIRST — this sets the viewport bounds
    // Layers enabled after arrival will only fetch data for the visible area
    btn.innerHTML = `<i class="fa-solid fa-spinner fa-spin" style="margin-right:4px;"></i>Flying to area...`
    btn.disabled = true

    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, 800000),
      duration: 1.5,
      complete: () => {
        // Step 2: Now enable layers — viewport-aware fetching means only nearby data loads
        const layerMap = {
          military_flights: "flightsToggle",
          gps_jamming: "gpsJammingToggle",
          fire_hotspots: "firesToggle",
          known_conflict_zone: "conflictsToggle",
          internet_outage: "internetOutagesToggle",
        }

        const enabled = []

        // Always enable flights + conflicts for context
        this._enableLayer("flightsToggle"); enabled.push("flights")
        this._enableLayer("conflictsToggle"); enabled.push("conflicts")

        // Enable layers that have detected signals
        for (const [signal, toggle] of Object.entries(layerMap)) {
          if (signals[signal]) {
            this._enableLayer(toggle)
            enabled.push(signal.replace(/_/g, " "))
          }
        }

        // Lightweight static layers (no API calls — already cached)
        this._enableLayer("cablesToggle")
        this._enableLayer("chokepointsToggle")

        // Track which layers we enabled so we can hide them later
        this._revealedLayers = enabled.map(name => {
          const map = { "flights": "flightsToggle", "conflicts": "conflictsToggle", "military flights": "flightsToggle", "gps jamming": "gpsJammingToggle", "fire hotspots": "firesToggle", "known conflict zone": "conflictsToggle", "internet outage": "internetOutagesToggle" }
          return map[name]
        }).filter(Boolean)
        this._revealedLayers.push("cablesToggle", "chokepointsToggle")

        btn.innerHTML = `<i class="fa-solid fa-eye-slash" style="margin-right:4px;"></i>Hide Revealed Layers`
        btn.style.background = "rgba(76,175,80,0.2)"
        btn.style.borderColor = "rgba(76,175,80,0.4)"
        btn.style.color = "#4caf50"
        btn.disabled = false
        btn.dataset.revealed = "true"

        this._toast(`Revealed: ${enabled.join(", ")}`, "success")
      },
    })
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

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign"><i class="fa-solid fa-hexagon-nodes" style="color:#ff9800;margin-right:6px;"></i>Conflict Theater Hex</div>
      <div class="detail-country">${this._escapeHtml(situation)}</div>
      ${theater ? `<div style="font:500 10px var(--gt-mono);color:#ffa726;letter-spacing:0.5px;margin:4px 0 8px;">${this._escapeHtml(theater)}</div>` : ""}
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Articles</span>
          <span class="detail-value">${cell.count}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Intensity</span>
          <span class="detail-value">${(cell.intensity * 100).toFixed(0)}%</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Coordinates</span>
          <span class="detail-value">${cell.lat.toFixed(1)}°, ${cell.lng.toFixed(1)}°</span>
        </div>
        ${zone ? `<div class="detail-field">
          <span class="detail-label">Pulse Score</span>
          <span class="detail-value">${zone.pulse_score}</span>
        </div>` : ""}
      </div>
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

    // Auto-highlight the theater this hex belongs to
    if (theater) {
      this._highlightedTheater = null // reset first so toggle works
      this.highlightTheater({ currentTarget: { dataset: { theater } } })
    }
  }

  // ── Fly to a zone by cell_key ────────────────────────────────

  GlobeController.prototype.flyToConflictZone = function(event) {
    const key = event.currentTarget.dataset.zoneKey
    const zone = this._conflictPulseData?.find(z => z.cell_key === key)
    if (zone) this._flyToConflictPulse(zone)
  }

  // ── Highlight theater: brighten connected hexes + arcs, dim others ──

  GlobeController.prototype.highlightTheater = function(event) {
    const theater = event.currentTarget.dataset.theater
    if (!theater || this._highlightedTheater === theater) {
      // Toggle off — reset all to normal
      this._highlightedTheater = null
      this._renderConflictPulse()
      return
    }
    this._highlightedTheater = theater

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
      // Zone entities use IDs like cpulse-0, cpulse-lbl-0, cpulse-ring-0
      const idMatch = entity.id?.match(/cpulse-(?:lbl-|ring-|core-)?(\d+)/)
      if (!idMatch) return
      const idx = parseInt(idMatch[1])
      const zone = this._conflictPulseData?.[idx]
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
}
