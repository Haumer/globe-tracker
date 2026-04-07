import { getDataSource } from "globe/utils"
import { COUNTRY_CENTROIDS } from "globe/country_centroids"

export function applyOutagesMethods(GlobeController) {
  GlobeController.prototype.getOutagesDataSource = function() { return getDataSource(this.viewer, this._ds, "outages") }

  GlobeController.prototype.toggleOutages = function() {
    this.outagesVisible = this.hasOutagesToggleTarget && this.outagesToggleTarget.checked
    if (this._outageInterval) {
      clearInterval(this._outageInterval)
      this._outageInterval = null
    }

    if (this.outagesVisible) {
      if (this._timelineActive) {
        this._timelineOnLayerToggle?.()
      } else {
        this.fetchOutages()
        this._outageInterval = setInterval(() => this.fetchOutages(), 300000) // 5min
      }
    } else {
      this._clearOutageEntities()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchOutages = async function() {
    if (this._timelineActive) return
    this._toast("Loading outages...")
    try {
      const resp = await fetch("/api/internet_outages")
      if (!resp.ok) return
      const data = await resp.json()
      const hasData = (data.summary?.length || 0) > 0 || (data.events?.length || 0) > 0
      this._handleBackgroundRefresh(resp, "internet-outages", hasData, () => {
        if (this.outagesVisible && !this._timelineActive) this.fetchOutages()
      })
      const summary = data.summary?.length ? data.summary : this._deriveOutageSummary(data.events || [])
      this._outageData = summary
      this._renderOutages(data)
      this._markFresh("outages")
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch internet outages:", e)
    }
  }

  GlobeController.prototype._renderOutages = function(data) {
    this._clearOutageEntities()
    const Cesium = window.Cesium
    const dataSource = this.getOutagesDataSource()
    dataSource.show = true

    const levelColors = {
      critical: "#e040fb",
      severe: "#f44336",
      moderate: "#ff9800",
      minor: "#ffc107",
    }

    const summaries = data.summary?.length ? data.summary : this._deriveOutageSummary(data.events || [])
    dataSource.entities.suspendEvents()
    summaries.forEach(s => {
      const centroid = COUNTRY_CENTROIDS[s.code]
      if (!centroid) return

      const color = levelColors[s.level] || "#ffc107"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const intensity = Math.min(Math.log10(Math.max(s.score, 1)) / 5, 1)
      const pixelSize = 8 + intensity * 16

      // Pulsing ring for outage area
      const ring = dataSource.entities.add({
        id: `outage-ring-${s.code}`,
        position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 0),
        ellipse: {
          semiMinorAxis: 50000 + intensity * 300000,
          semiMajorAxis: 50000 + intensity * 300000,
          material: cesiumColor.withAlpha(0.06 + intensity * 0.08),
          outline: true,
          outlineColor: cesiumColor.withAlpha(0.2),
          outlineWidth: 1,
          height: 0,
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._outageEntities.push(ring)

      // Center marker
      const entity = dataSource.entities.add({
        id: `outage-${s.code}`,
        position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 10),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(0.85),
          outlineColor: cesiumColor.withAlpha(0.4),
          outlineWidth: 3,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.5),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: `${s.code} ▼${s.score}${s.eventCount ? ` · ${s.eventCount}` : ""}`,
          font: "bold 12px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -18),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1.0, 1e7, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._outageEntities.push(entity)
    })
    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._clearOutageEntities = function() {
    const ds = this.getOutagesDataSource()
    ds.entities.suspendEvents()
    this._outageEntities.forEach(e => ds.entities.remove(e))
    ds.entities.resumeEvents()
    this._outageEntities = []
  }

  GlobeController.prototype._deriveOutageSummary = function(events) {
    if (!Array.isArray(events) || events.length === 0) return []

    const levelRank = { minor: 1, moderate: 2, major: 3, severe: 4, critical: 5 }
    const groups = new Map()

    events.forEach((event) => {
      if (!event?.code) return
      if (!groups.has(event.code)) groups.set(event.code, [])
      groups.get(event.code).push(event)
    })

    return [...groups.entries()].map(([code, rows]) => {
      const strongest = rows.reduce((best, row) => {
        if (!best) return row
        const bestRank = levelRank[best.level] || 0
        const rowRank = levelRank[row.level] || 0
        if (rowRank !== bestRank) return rowRank > bestRank ? row : best
        return Number(row.score || 0) > Number(best.score || 0) ? row : best
      }, null)

      return {
        code,
        name: strongest?.name || code,
        score: Math.max(...rows.map(row => Number(row.score || 0))).toFixed(1).replace(/\.0$/, ""),
        eventCount: rows.length,
        level: strongest?.level || "minor",
      }
    }).sort((a, b) => Number(b.score || 0) - Number(a.score || 0))
  }

  GlobeController.prototype.showOutageDetail = function(code) {
    const s = this._outageData.find(o => o.code === code)
    if (!s) return

    const levelColors = { critical: "#e040fb", severe: "#f44336", moderate: "#ff9800", minor: "#ffc107" }
    const color = levelColors[s.level] || "#ffc107"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-wifi" style="margin-right:6px;"></i>Internet Outage
      </div>
      <div class="detail-country">${this._escapeHtml(s.name || s.code)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Severity</span>
          <span class="detail-value" style="color:${color};">${s.level.toUpperCase()}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Score</span>
          <span class="detail-value">${s.score}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Country</span>
          <span class="detail-value">${s.code}</span>
        </div>
        ${s.eventCount ? `<div class="detail-field">
          <span class="detail-label">Events</span>
          <span class="detail-value">${s.eventCount}</span>
        </div>` : ""}
      </div>
      <a href="https://ioda.inetintel.cc.gatech.edu/country/${s.code}" target="_blank" rel="noopener" class="detail-track-btn">View on IODA →</a>
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: IODA (Georgia Tech)</div>
    `
    this.detailPanelTarget.style.display = ""
  }
}
