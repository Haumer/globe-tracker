import { getDataSource, LABEL_DEFAULTS } from "../../utils"

export function applyConflictsMethods(GlobeController) {
  GlobeController.prototype.getConflictsDataSource = function() { return getDataSource(this.viewer, this._ds, "conflicts") }

  GlobeController.prototype.toggleConflicts = function() {
    this.conflictsVisible = this.hasConflictsToggleTarget && this.conflictsToggleTarget.checked
    if (this.conflictsVisible) {
      this.fetchConflicts()
    } else {
      this._clearConflictEntities()
      this._conflictData = []
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchConflicts = async function() {
    if (this._timelineActive) return
    this._toast("Loading conflicts...")
    try {
      const resp = await fetch("/api/conflict_events")
      if (!resp.ok) return
      this._conflictData = await resp.json()
      this._handleBackgroundRefresh(resp, "conflict-events", this._conflictData.length > 0, () => {
        if (this.conflictsVisible && !this._timelineActive) this.fetchConflicts()
      })
      this.renderConflicts()
      this._updateStats()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch conflict events:", e)
    }
  }

  GlobeController.prototype.renderConflicts = function() {
    this._clearConflictEntities()
    const Cesium = window.Cesium
    const dataSource = this.getConflictsDataSource()

    const typeColors = {
      1: "#f44336", // state-based
      2: "#ff9800", // non-state
      3: "#e040fb", // one-sided
    }

    dataSource.entities.suspendEvents()
    this._conflictData.forEach(c => {
      if (this.hasActiveFilter() && !this.pointPassesFilter(c.lat, c.lng)) return

      const color = typeColors[c.type] || "#f44336"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const deaths = c.deaths || 0
      const pixelSize = Math.min(5 + Math.sqrt(deaths) * 2, 22)

      // Impact ring for higher-casualty events
      if (deaths >= 5) {
        const ring = dataSource.entities.add({
          id: `conf-ring-${c.id}`,
          position: Cesium.Cartesian3.fromDegrees(c.lng, c.lat, 0),
          ellipse: {
            semiMinorAxis: Math.min(5000 + deaths * 300, 30000),
            semiMajorAxis: Math.min(5000 + deaths * 300, 30000),
            material: cesiumColor.withAlpha(0.06),
            outline: true,
            outlineColor: cesiumColor.withAlpha(0.2),
            outlineWidth: 1,
            height: 0,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            classificationType: Cesium.ClassificationType.BOTH,
          },
        })
        this._conflictEntities.push(ring)
      }

      const entity = dataSource.entities.add({
        id: `conf-${c.id}`,
        position: Cesium.Cartesian3.fromDegrees(c.lng, c.lat, 10),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(0.85),
          outlineColor: cesiumColor.withAlpha(0.4),
          outlineWidth: 2,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 8e6, 0.4),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: `${c.conflict || c.country}`,
          font: LABEL_DEFAULTS.font,
          fillColor: cesiumColor.withAlpha(0.9),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: LABEL_DEFAULTS.pixelOffsetAbove(),
          scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
          translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._conflictEntities.push(entity)
    })
    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._clearConflictEntities = function() {
    const ds = this._ds["conflicts"]
    if (ds) {
      ds.entities.suspendEvents()
      this._conflictEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._conflictEntities = []
  }

  GlobeController.prototype.showConflictDetail = function(c) {
    const typeColors = { 1: "#f44336", 2: "#ff9800", 3: "#e040fb" }
    const color = typeColors[c.type] || "#f44336"
    const totalDeaths = c.deaths || 0

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-crosshairs" style="margin-right:6px;"></i>${this._escapeHtml(c.conflict || "Conflict Event")}
      </div>
      <div class="detail-country">${this._escapeHtml(c.country || "")} — ${this._escapeHtml(c.type_label)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Side A</span>
          <span class="detail-value" style="font-size:11px;">${this._escapeHtml(c.side_a || "—")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Side B</span>
          <span class="detail-value" style="font-size:11px;">${this._escapeHtml(c.side_b || "—")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Deaths</span>
          <span class="detail-value" style="color:${color};">${totalDeaths}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Civilian</span>
          <span class="detail-value">${c.deaths_civilians || 0}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Date</span>
          <span class="detail-value">${c.date_start || "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Location</span>
          <span class="detail-value" style="font-size:10px;">${this._escapeHtml(c.location || "—")}</span>
        </div>
      </div>
      ${c.headline ? `<div style="margin-top:8px;font:400 10px var(--gt-mono);color:var(--gt-text-dim);line-height:1.4;">${this._escapeHtml(c.headline)}</div>` : ""}
      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${c.lat}" data-lng="${c.lng}">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
      </button>
      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("conflict", c.lat, c.lng)
  }
}
