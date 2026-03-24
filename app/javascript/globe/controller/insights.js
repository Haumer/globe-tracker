import { getDataSource } from "../utils"

export function applyInsightsMethods(GlobeController) {

  GlobeController.prototype._startInsightPolling = function() {
    this._insightsData = []
    this._insightEntities = []
    this._fetchInsights()
    this._insightPollInterval = setInterval(() => this._fetchInsights(), 5 * 60 * 1000)
  }

  GlobeController.prototype._stopInsightPolling = function() {
    if (this._insightPollInterval) {
      clearInterval(this._insightPollInterval)
      this._insightPollInterval = null
    }
  }

  GlobeController.prototype._fetchInsights = async function() {
    try {
      const resp = await fetch("/api/insights")
      if (!resp.ok) return
      const data = await resp.json()
      this._insightsData = data.insights || []
      this._insightSnapshotStatus = data.snapshot_status || "ready"
      this._renderInsightMarkers()
      this._renderInsightFeed()
      // Show insights tab if we have data
      if ((this._insightsData.length > 0 || this._insightSnapshotStatus) && this.hasRpTabInsightsTarget) {
        this.rpTabInsightsTarget.style.display = ""
      }
      if (this._syncRightPanels) this._syncRightPanels()
    } catch (e) {
      console.warn("Insights fetch failed:", e)
    }
  }

  GlobeController.prototype._renderInsightMarkers = function() {
    const Cesium = window.Cesium
    const ds = getDataSource(this.viewer, this._ds, "insights")

    // Remove old entities
    for (const e of this._insightEntities) ds.entities.remove(e)
    this._insightEntities = []

    if (!this._insightsData.length) return

    const severityColors = {
      critical: Cesium.Color.fromCssColorString("#f44336"),
      high: Cesium.Color.fromCssColorString("#ff9800"),
      medium: Cesium.Color.fromCssColorString("#ffc107"),
      low: Cesium.Color.fromCssColorString("#4caf50"),
    }

    const typeIcons = {
      earthquake_infrastructure: "\u26A0",
      earthquake_pipeline: "\u26A0",
      jamming_flights: "\u{1F4E1}",
      electronic_warfare: "\u{1F4E1}",
      conflict_military: "\u2694",
      fire_infrastructure: "\u{1F525}",
      fire_pipeline: "\u{1F525}",
      cable_outage: "\u{1F50C}",
      emergency_squawk: "\u{1F6A8}",
      ship_cable_proximity: "\u2693",
      information_blackout: "\u{1F50C}",
      airspace_clearing: "\u{2708}",
      weather_disruption: "\u26C8",
      conflict_pulse: "\u{1F4A5}",
      chokepoint_disruption: "\u2693",
      convergence: "\u{1F310}",
    }

    this._insightsData.forEach((insight, idx) => {
      if (insight.lat == null || insight.lng == null) return
      const color = severityColors[insight.severity] || severityColors.medium
      const icon = typeIcons[insight.type] || "\u26A0"

      // Pulsing ring
      const ring = ds.entities.add({
        id: `insight-ring-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(insight.lng, insight.lat),
        ellipse: {
          semiMajorAxis: insight.severity === "critical" ? 80000 : 50000,
          semiMinorAxis: insight.severity === "critical" ? 80000 : 50000,
          material: color.withAlpha(0.15),
          outline: true,
          outlineColor: color.withAlpha(0.6),
          outlineWidth: 2,
          height: 0,
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._insightEntities.push(ring)

      // Label
      const label = ds.entities.add({
        id: `insight-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(insight.lng, insight.lat),
        billboard: {
          image: this._makeInsightIcon(icon, color.toCssColorString()),
          width: 28,
          height: 28,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: insight.title.length > 40 ? insight.title.slice(0, 37) + "..." : insight.title,
          font: "11px 'JetBrains Mono', monospace",
          fillColor: Cesium.Color.WHITE,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 2,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -22),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.0, 5e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1.0, 8e6, 0.0),
        },
      })
      this._insightEntities.push(label)
    })

    this._requestRender()
  }

  GlobeController.prototype._makeInsightIcon = function(icon, color) {
    const key = `insight-${icon}-${color}`
    if (this._iconCache?.[key]) return this._iconCache[key]
    if (!this._iconCache) this._iconCache = {}

    const size = 28
    const canvas = document.createElement("canvas")
    canvas.width = size; canvas.height = size
    const ctx = canvas.getContext("2d")

    // Circle background
    ctx.beginPath()
    ctx.arc(size / 2, size / 2, size / 2 - 1, 0, Math.PI * 2)
    ctx.fillStyle = "rgba(0,0,0,0.7)"
    ctx.fill()
    ctx.strokeStyle = color
    ctx.lineWidth = 2
    ctx.stroke()

    // Icon text
    ctx.font = "14px sans-serif"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = color
    ctx.fillText(icon, size / 2, size / 2)

    const url = canvas.toDataURL()
    this._iconCache[key] = url
    return url
  }

  GlobeController.prototype._renderInsightFeed = function() {
    if (!this.hasInsightFeedContentTarget) return
    const insights = this._insightsData || []
    const snapshotStatus = this._insightSnapshotStatus || "pending"

    if (this.hasInsightFeedCountTarget) {
      const base = `${insights.length} insight${insights.length !== 1 ? "s" : ""}`
      const suffix = snapshotStatus === "ready" ? "" : ` · ${this._statusLabel(snapshotStatus, "snapshot")}`
      this.insightFeedCountTarget.textContent = `${base}${suffix}`
    }

    if (insights.length === 0) {
      const emptyLabel = {
        pending: "Insight snapshot pending. Correlations appear after the stored layers finish updating.",
        stale: "No stored insights in the latest snapshot.",
        error: "Insight snapshot unavailable.",
      }[snapshotStatus] || "No cross-layer correlations detected. Insights appear when multiple data layers overlap geographically."
      this.insightFeedContentTarget.innerHTML = `<div class="insight-empty">${this._escapeHtml(emptyLabel)}</div>`
      return
    }

    const severityOrder = { critical: 0, high: 1, medium: 2, low: 3 }
    const severityIcons = {
      critical: "fa-circle-exclamation",
      high: "fa-triangle-exclamation",
      medium: "fa-circle-info",
      low: "fa-circle-check",
    }
    const typeLabels = {
      earthquake_infrastructure: "QUAKE + INFRA",
      earthquake_pipeline: "QUAKE + PIPELINE",
      jamming_flights: "JAMMING + AIR",
      electronic_warfare: "ELECTRONIC WARFARE",
      conflict_military: "CONFLICT + MIL",
      fire_infrastructure: "FIRE + INFRA",
      fire_pipeline: "FIRE + PIPELINE",
      cable_outage: "OUTAGE + CABLE",
      emergency_squawk: "EMERGENCY SQUAWK",
      ship_cable_proximity: "SHIP + CABLE",
      information_blackout: "INFO BLACKOUT",
      airspace_clearing: "AIRSPACE + MIL",
      weather_disruption: "WEATHER + AIR",
      conflict_pulse: "DEVELOPING",
      chokepoint_disruption: "CHOKEPOINT",
      convergence: "CONVERGENCE",
    }

    const statusBanner = snapshotStatus === "ready"
      ? ""
      : `<div style="margin-bottom:10px;display:flex;align-items:center;gap:6px;flex-wrap:wrap;">${this._statusChip(snapshotStatus, this._statusLabel(snapshotStatus, "snapshot"))}</div>`

    const html = statusBanner + insights
      .sort((a, b) => (severityOrder[a.severity] || 3) - (severityOrder[b.severity] || 3))
      .map((insight, idx) => {
        const sev = insight.severity || "medium"
        const icon = severityIcons[sev] || "fa-circle-info"
        const typeLabel = typeLabels[insight.type] || insight.type.replace(/_/g, " ").toUpperCase()
        const hasLocation = insight.lat != null && insight.lng != null

        // Build entity detail chips
        let chips = ""
        if (insight.type === "convergence" && insight.layers) {
          // Convergence insight — show layer chips
          const layerChipColors = {
            earthquake: "eq", fire: "fire", conflict: "conf",
            military_flight: "flight", jamming: "jam", natural_event: "event",
            news: "news", nuclear_plant: "plant", submarine_cable: "cable",
          }
          insight.layers.forEach(layer => {
            const cls = layerChipColors[layer] || "eq"
            const label = layer.replace(/_/g, " ")
            const ents = insight.entities?.[layer]
            const count = ents?.count || (Array.isArray(ents) ? ents.length : "")
            chips += `<span class="ins-chip ins-chip--${cls}">${count ? count + " " : ""}${label}</span>`
          })
          if (insight.layer_count) {
            chips = `<span class="ins-chip ins-chip--conf">${insight.layer_count} layers</span>` + chips
          }
        } else if (insight.entities) {
          const ents = insight.entities
          if (ents.earthquake) chips += `<span class="ins-chip ins-chip--eq">M${ents.earthquake.magnitude}</span>`
          if (ents.cables?.length) chips += `<span class="ins-chip ins-chip--cable">${ents.cables.length} cable${ents.cables.length > 1 ? "s" : ""}</span>`
          if (ents.plants?.length) chips += `<span class="ins-chip ins-chip--plant">${ents.plants.length} plant${ents.plants.length > 1 ? "s" : ""}</span>`
          if (ents.flights) chips += `<span class="ins-chip ins-chip--flight">${ents.flights.total || ents.flights.military || 0} flights</span>`
          if (ents.jamming) chips += `<span class="ins-chip ins-chip--jam">${ents.jamming.percentage?.toFixed(0)}% jam</span>`
          if (ents.fires) chips += `<span class="ins-chip ins-chip--fire">${ents.fires.count} fires</span>`
          if (ents.outages?.length) chips += `<span class="ins-chip ins-chip--outage">${ents.outages.length} outage${ents.outages.length > 1 ? "s" : ""}</span>`
          if (ents.conflict) chips += `<span class="ins-chip ins-chip--conf">${ents.conflict.count || ents.conflict.events} events</span>`
          if (ents.flight) chips += `<span class="ins-chip ins-chip--flight">${ents.flight.squawk || "EMG"} ${ents.flight.callsign || ents.flight.icao24}</span>`
          if (ents.ship) chips += `<span class="ins-chip ins-chip--cable">${ents.ship.name || ents.ship.mmsi}</span>`
          if (ents.cable && !ents.cables) chips += `<span class="ins-chip ins-chip--cable">${ents.cable.name} (${ents.cable.distance_km}km)</span>`
          if (ents.nordo) chips += `<span class="ins-chip ins-chip--jam">${ents.nordo.count} NORDO</span>`
          if (ents.notams?.length) chips += `<span class="ins-chip ins-chip--flight">${ents.notams.length} NOTAMs</span>`
          if (ents.pipelines?.length) chips += `<span class="ins-chip ins-chip--cable">${ents.pipelines.length} pipeline${ents.pipelines.length > 1 ? "s" : ""}</span>`
          if (ents.satellite) chips += `<span class="ins-chip ins-chip--plant">${ents.satellite.name}</span>`
          if (ents.hotspot) chips += `<span class="ins-chip ins-chip--conf">${ents.hotspot.label}</span>`
          if (ents.weather) chips += `<span class="ins-chip ins-chip--outage">${ents.weather.event}</span>`
          if (ents.conflicts?.length) chips += `<span class="ins-chip ins-chip--conf">${ents.conflicts.length} conflicts</span>`
          if (ents.pulse) chips += `<span class="ins-chip ins-chip--conf">${ents.pulse.score} pulse · ${ents.pulse.trend}</span>`
          if (ents.news?.count_24h) chips += `<span class="ins-chip ins-chip--fire">${ents.news.count_24h} reports · ${ents.news.sources} sources</span>`
          if (ents.headlines?.length) chips += ents.headlines.map(h => `<span class="ins-chip ins-chip--eq" style="white-space:normal;text-align:left;font-size:8px;line-height:1.2;">${h.slice(0,60)}</span>`).join("")
          if (ents.cross_layer?.military_flights) chips += `<span class="ins-chip ins-chip--flight">${ents.cross_layer.military_flights} mil flights</span>`
          if (ents.cross_layer?.gps_jamming) chips += `<span class="ins-chip ins-chip--jam">${ents.cross_layer.gps_jamming}% jamming</span>`
          if (ents.cross_layer?.internet_outage) chips += `<span class="ins-chip ins-chip--outage">outage: ${ents.cross_layer.internet_outage}</span>`
          if (ents.cross_layer?.fire_hotspots) chips += `<span class="ins-chip ins-chip--fire">${ents.cross_layer.fire_hotspots} fires</span>`
          if (ents.chokepoint) chips += `<span class="ins-chip ins-chip--cable">${ents.chokepoint.name} (${ents.chokepoint.status})</span>`
          if (ents.ships?.total) chips += `<span class="ins-chip ins-chip--cable">${ents.ships.total} ships (${ents.ships.tankers || 0} tankers)</span>`
          if (ents.flows) Object.entries(ents.flows).forEach(([k, v]) => { if (v.pct) chips += `<span class="ins-chip ins-chip--outage">${v.pct}% world ${k}</span>` })
          if (ents.commodities?.length) ents.commodities.forEach(c => { if (c.change_pct) chips += `<span class="ins-chip ins-chip--${c.change_pct > 0 ? "fire" : "eq"}">${c.symbol} ${c.change_pct > 0 ? "+" : ""}${c.change_pct}%</span>` })
        }

        return `<div class="insight-card insight-card--${sev}" data-insight-idx="${idx}">
          <div class="insight-card-severity">
            <i class="fa-solid ${icon}"></i>
          </div>
          <div class="insight-card-body">
            <div class="insight-card-type">${typeLabel}</div>
            <div class="insight-card-title">${this._escapeHtml(insight.title)}</div>
            <div class="insight-card-desc">${this._escapeHtml(insight.description)}</div>
            ${chips ? `<div class="insight-card-chips">${chips}</div>` : ""}
            <div class="insight-card-actions">
              ${hasLocation ? `<button class="insight-action-btn" data-action="click->globe#focusInsight" data-insight-idx="${idx}"><i class="fa-solid fa-location-crosshairs"></i> Focus</button>` : ""}
            </div>
          </div>
        </div>`
      }).join("")

    this.insightFeedContentTarget.innerHTML = html
  }

  GlobeController.prototype.focusInsight = function(event) {
    const idx = parseInt(event.currentTarget.dataset.insightIdx)
    const insight = this._insightsData?.[idx]
    if (!insight) return

    // Show insight detail panel
    this.showInsightDetail(insight)

    // Fly camera if location is available
    if (insight.lat != null && insight.lng != null) {
      const Cesium = window.Cesium
      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(insight.lng, insight.lat, 500000),
        duration: 1.5,
      })
    }
  }

  GlobeController.prototype.showInsightDetail = function(insight) {
    const severityColors = { critical: "#f44336", high: "#ff9800", medium: "#ffc107", low: "#4caf50" }
    const sev = insight.severity || "medium"
    const sevColor = severityColors[sev] || "#ffc107"
    const typeLabel = (insight.type || "insight").replace(/_/g, " ").toUpperCase()
    const description = insight.description || ""
    const coordStr = (insight.lat != null && insight.lng != null)
      ? `${insight.lat.toFixed(2)}, ${insight.lng.toFixed(2)}` : "Global"

    let entitiesHtml = ""
    if (insight.entities) {
      const ents = insight.entities
      const items = []
      if (ents.earthquakes?.count) items.push(`${ents.earthquakes.count} earthquakes (max M${ents.earthquakes.max_mag || "?"})`)
      if (ents.fires) items.push(`${ents.fires.count} fire hotspots`)
      if (ents.conflict) items.push(`${ents.conflict.count || ents.conflict.events || ""} conflict events`)
      if (ents.outages?.length) items.push(`${ents.outages.length} internet outages`)
      if (ents.flight) items.push(`Flight ${ents.flight.callsign || ents.flight.icao24} (${ents.flight.squawk || "EMG"})`)
      if (ents.ship) items.push(`Ship: ${ents.ship.name || ents.ship.mmsi}`)
      if (ents.cable) items.push(`Cable: ${ents.cable.name}`)
      if (ents.nordo) items.push(`${ents.nordo.count} NORDO aircraft`)
      if (ents.notams?.length) items.push(`${ents.notams.length} NOTAMs`)
      if (ents.pipelines?.length) items.push(`${ents.pipelines.length} pipelines`)
      if (ents.satellite) items.push(`Satellite: ${ents.satellite.name}`)
      if (ents.weather) items.push(`Weather: ${ents.weather.event}`)
      if (ents.chokepoint) items.push(`Chokepoint: ${ents.chokepoint.name} (${ents.chokepoint.status})`)
      if (items.length) {
        entitiesHtml = `<div style="margin-top:6px;font-size:11px;color:var(--gt-text-sec);">${items.map(i => `<div style="padding:2px 0;">- ${this._escapeHtml(i)}</div>`).join("")}</div>`
      }
    }

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${sevColor};">
        <i class="fa-solid fa-brain" style="margin-right:6px;"></i>${typeLabel}
      </div>
      <div style="display:flex;gap:6px;align-items:center;margin-bottom:4px;">
        <span style="font-size:10px;font-weight:600;text-transform:uppercase;padding:2px 6px;border-radius:3px;background:${sevColor}22;color:${sevColor};border:1px solid ${sevColor}44;">${sev}</span>
      </div>
      <div class="detail-country">${this._escapeHtml(insight.title)}</div>
      <div style="font-size:12px;line-height:1.4;color:var(--gt-text-sec);margin:6px 0;">${this._escapeHtml(description)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Location</span>
          <span class="detail-value">${coordStr}</span>
        </div>
      </div>
      ${entitiesHtml}
    `
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype.toggleInsightsFeed = function() {
    if (this._insightsData?.length > 0) {
      this._showRightPanel("insights")
    }
  }

  // ── Intelligence Brief ──────────────────────────────────

  GlobeController.prototype.loadBrief = async function() {
    const container = document.getElementById("intelligence-brief")
    if (!container) return

    // Toggle visibility
    if (container.style.display !== "none") {
      container.style.display = "none"
      return
    }

    container.style.display = ""
    container.innerHTML = `<div style="font:400 11px 'JetBrains Mono',monospace;color:rgba(200,210,225,0.4);padding:12px 0;">Generating intelligence brief...</div>`

    try {
      const resp = await fetch("/api/brief")
      if (resp.status === 403) {
        container.innerHTML = `<div style="color:rgba(255,152,0,0.75);font:400 11px monospace;">Brief is currently internal-only.</div>`
        return
      }
      if (!resp.ok) { container.innerHTML = `<div style="color:#ef5350;font:400 11px monospace;">Failed to load brief.</div>`; return }
      const data = await resp.json()

      if (data.status === "generating") {
        container.innerHTML = `<div style="font:400 11px 'JetBrains Mono',monospace;color:rgba(255,152,0,0.6);padding:12px 0;"><i class="fa-solid fa-spinner fa-spin" style="margin-right:6px;"></i>${data.message}</div>`
        // Retry in 15 seconds
        setTimeout(() => this.loadBrief(), 15000)
        return
      }

      const brief = data.brief || "No brief available."
      const generatedAt = data.generated_at ? new Date(data.generated_at).toLocaleString() : ""
      const ctx = data.context_summary || {}

      // Format the brief text — convert section headers to styled spans
      const formatted = this._escapeHtml(brief)
        .replace(/^(CRITICAL|HIGH|NOTABLE|CROSS-LAYER CONNECTIONS|MARKET IMPACT)/gm,
          '<span style="display:block;font:700 11px \'JetBrains Mono\',monospace;color:#ff9800;letter-spacing:1px;margin:14px 0 6px;padding-top:8px;border-top:1px solid rgba(255,255,255,0.06);">$1</span>')
        .replace(/\n- /g, '\n<span style="color:rgba(255,152,0,0.4);margin-right:4px;">▸</span>')
        .replace(/\n/g, '<br>')

      container.innerHTML = `
        <div style="font:400 11px/1.7 'DM Sans',sans-serif;color:rgba(200,210,225,0.75);">
          ${formatted}
        </div>
        <div style="font:400 9px 'JetBrains Mono',monospace;color:rgba(200,210,225,0.2);margin-top:12px;padding-top:8px;border-top:1px solid rgba(255,255,255,0.04);">
          Generated ${generatedAt} · ${ctx.conflict_zones || 0} zones · ${ctx.earthquakes || 0} quakes · ${ctx.news_articles || 0} articles
        </div>
      `
    } catch (e) {
      container.innerHTML = `<div style="color:#ef5350;font:400 11px monospace;">Error: ${e.message}</div>`
    }
  }

}
