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
    const Cesium = window.Cesium
    const ds = getDataSource(this.viewer, this._ds, "conflictPulse")

    if (!this._conflictPulseData?.length) return

    ds.entities.suspendEvents()
    this._conflictPulseData.forEach((zone, idx) => {
      const score = zone.pulse_score
      // Color intensity scales with score
      const t = Math.min((score - 20) / 60, 1) // 0-1 range (20=min, 80=max)
      const r = Math.round(255 * (0.6 + t * 0.4))
      const g = Math.round(255 * (0.3 - t * 0.3))
      const b = Math.round(30 - t * 30)
      const color = Cesium.Color.fromBytes(r, g, b)

      // Zone radius based on score (100-300km visual radius)
      const radius = 100000 + score * 2000

      // Outer pulse ring
      const ring = ds.entities.add({
        id: `cpulse-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
        ellipse: {
          semiMajorAxis: radius,
          semiMinorAxis: radius,
          material: color.withAlpha(0.08 + t * 0.12),
          outline: true,
          outlineColor: color.withAlpha(0.3 + t * 0.3),
          outlineWidth: 2,
          height: 5100, // slightly above GPS jamming hexes
        },
      })
      this._conflictPulseEntities.push(ring)

      // Inner core (brighter)
      const core = ds.entities.add({
        id: `cpulse-core-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
        ellipse: {
          semiMajorAxis: radius * 0.3,
          semiMinorAxis: radius * 0.3,
          material: color.withAlpha(0.15 + t * 0.2),
          outline: false,
          height: 5100,
        },
      })
      this._conflictPulseEntities.push(core)

      // Trend label
      const trendIcon = zone.escalation_trend === "surging" ? "\u{1F534}" :
                         zone.escalation_trend === "escalating" ? "\u{1F7E0}" : "\u{1F7E1}"
      const label = ds.entities.add({
        id: `cpulse-lbl-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat, 6000),
        label: {
          text: `${trendIcon} ${zone.escalation_trend.toUpperCase()} ${score}`,
          font: "bold 12px monospace",
          fillColor: color.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1e7, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1.5e7, 0.0),
        },
      })
      this._conflictPulseEntities.push(label)
    })
    ds.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._clearConflictPulseEntities = function() {
    const ds = this._ds["conflictPulse"]
    if (ds && this._conflictPulseEntities?.length) {
      ds.entities.suspendEvents()
      this._conflictPulseEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._conflictPulseEntities = []
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
    const trendColors = { surging: "#f44336", escalating: "#ff9800", elevated: "#ffc107", baseline: "#66bb6a" }
    const color = trendColors[zone.escalation_trend] || "#ff9800"

    // Cross-layer signal chips
    let signalHtml = ""
    const s = zone.cross_layer_signals || {}
    if (s.military_flights) signalHtml += `<span class="detail-chip" style="background:rgba(239,83,80,0.15);color:#ef5350;"><i class="fa-solid fa-jet-fighter"></i> ${s.military_flights} mil flights</span>`
    if (s.gps_jamming) signalHtml += `<span class="detail-chip" style="background:rgba(255,193,7,0.15);color:#ffc107;"><i class="fa-solid fa-satellite-dish"></i> ${s.gps_jamming}% jamming</span>`
    if (s.internet_outage) signalHtml += `<span class="detail-chip" style="background:rgba(156,39,176,0.15);color:#ce93d8;"><i class="fa-solid fa-plug"></i> outage: ${s.internet_outage}</span>`
    if (s.fire_hotspots) signalHtml += `<span class="detail-chip" style="background:rgba(255,87,34,0.15);color:#ff5722;"><i class="fa-solid fa-fire"></i> ${s.fire_hotspots} fires</span>`
    if (s.known_conflict_zone) signalHtml += `<span class="detail-chip" style="background:rgba(244,67,54,0.15);color:#f44336;"><i class="fa-solid fa-crosshairs"></i> ${s.known_conflict_zone} historical events</span>`

    // Tier breakdown
    const tiers = zone.tier_breakdown || {}
    let tierHtml = Object.entries(tiers).sort((a,b) => a[0].localeCompare(b[0]))
      .map(([t, n]) => `<span style="color:#888;">${t}:</span>${n}`).join(" ")

    // Headlines
    const headlinesHtml = (zone.top_headlines || []).map(h =>
      `<div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.4;padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.05);">${this._escapeHtml(h)}</div>`
    ).join("")

    // Sparkline-style frequency indicator
    const spikeBar = Math.min(zone.spike_ratio / 5.0, 1.0) * 100
    const toneBar = Math.min(Math.abs(zone.avg_tone) / 10.0, 1.0) * 100

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-bolt" style="margin-right:6px;"></i>DEVELOPING SITUATION
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
    `
    this.detailPanelTarget.style.display = ""
  }
}
