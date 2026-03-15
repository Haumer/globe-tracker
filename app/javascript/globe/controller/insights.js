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
      this._renderInsightMarkers()
      this._renderInsightFeed()
      // Show insights tab if we have data
      if (this._insightsData.length > 0 && this.hasRpTabInsightsTarget) {
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
          font: "11px monospace",
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

    if (this.hasInsightFeedCountTarget) {
      this.insightFeedCountTarget.textContent = `${insights.length} insight${insights.length !== 1 ? "s" : ""}`
    }

    if (insights.length === 0) {
      this.insightFeedContentTarget.innerHTML = '<div class="insight-empty">No cross-layer correlations detected. Insights appear when multiple data layers overlap geographically.</div>'
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
      convergence: "CONVERGENCE",
    }

    const html = insights
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
    if (!insight || insight.lat == null || insight.lng == null) return

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(insight.lng, insight.lat, 500000),
      duration: 1.5,
    })
  }

  GlobeController.prototype.toggleInsightsFeed = function() {
    if (this._insightsData?.length > 0) {
      this._showRightPanel("insights")
    }
  }

}
