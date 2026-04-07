import { getDataSource, cachedColor } from "globe/utils"

export function applyGpsJammingMethods(GlobeController) {
  GlobeController.prototype.getGpsJammingDataSource = function() { return getDataSource(this.viewer, this._ds, "gpsJamming") }

  GlobeController.prototype.toggleGpsJamming = function() {
    this.gpsJammingVisible = this.hasGpsJammingToggleTarget && this.gpsJammingToggleTarget.checked
    if (this._gpsJammingInterval) { clearInterval(this._gpsJammingInterval); this._gpsJammingInterval = null }

    if (this.gpsJammingVisible) {
      if (this._timelineActive) {
        this._timelineOnLayerToggle?.()
      } else {
        this.fetchGpsJamming()
        this._gpsJammingInterval = setInterval(() => this.fetchGpsJamming(), 60000)
      }
    } else {
      this._clearGpsJammingEntities()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchGpsJamming = async function() {
    if (this._timelineActive) return
    this._toast("Loading GPS jamming...")
    try {
      const resp = await fetch("/api/gps_jamming")
      if (!resp.ok) return
      // Check if layer was toggled off while fetch was in flight
      if (!this.gpsJammingVisible) return
      const cells = await resp.json()
      if (!this.gpsJammingVisible) return
      this._gpsJammingData = this.filterToRegion(cells)
      this._renderGpsJamming(this._gpsJammingData)
      this._markFresh("gpsJamming")
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch GPS jamming data:", e)
    }
  }

  GlobeController.prototype._renderGpsJamming = function(cells) {
    this._clearGpsJammingEntities()
    const dataSource = this.getGpsJammingDataSource()
    const Cesium = window.Cesium
    dataSource.show = true

    if (cells.length === 0) return

    const elevatedCells = cells.filter(cell => cell.level !== "low")
    const renderCells = elevatedCells.length > 0 ? elevatedCells : cells

    const colors = {
      low: Cesium.Color.fromCssColorString("rgba(255, 152, 0, 0.25)"),
      medium: Cesium.Color.fromCssColorString("rgba(255, 87, 34, 0.45)"),
      high: Cesium.Color.fromCssColorString("rgba(244, 67, 54, 0.55)")
    }
    const outlines = {
      low: Cesium.Color.fromCssColorString("rgba(255, 152, 0, 0.5)"),
      medium: Cesium.Color.fromCssColorString("rgba(255, 87, 34, 0.8)"),
      high: Cesium.Color.fromCssColorString("rgba(244, 67, 54, 0.9)")
    }

    const hexRadius = 1.0 // degrees (~111km) — matches backend HEX_SIZE for flush tiling

    dataSource.entities.suspendEvents()
    renderCells.forEach(cell => {
      const hexPoints = this._hexVertices(cell.lat, cell.lng, hexRadius)
      const positions = hexPoints.map(p => Cesium.Cartesian3.fromDegrees(p[1], p[0]))

      const hexEntity = dataSource.entities.add({
        id: `jam-${cell.lat}-${cell.lng}`,
        polygon: {
          hierarchy: new Cesium.PolygonHierarchy(positions),
          material: colors[cell.level] || colors.medium,
          outline: true,
          outlineColor: outlines[cell.level] || outlines.medium,
          outlineWidth: 2,
          height: 5000,
        },
        description: `<div style="font-family: 'DM Sans', sans-serif;">
          <div style="font-size: 15px; font-weight: 600; margin-bottom: 6px;">GPS Interference</div>
          <div style="font-size: 13px; color: ${cell.level === 'high' ? '#f44336' : '#ffc107'}; font-weight: 600; margin-bottom: 4px;">${cell.level.toUpperCase()} — ${cell.pct}%</div>
          <div style="font-size: 12px; color: #aaa;">${cell.bad} of ${cell.total} aircraft with degraded accuracy</div>
          <div style="font-size: 11px; color: #666; margin-top: 6px;">NACp ≤ 4 indicates GPS jamming or spoofing</div>
        </div>`,
      })
      this._gpsJammingEntities.push(hexEntity)

      // Label only for medium/high, unless low is all we have in the current scope.
      if (cell.level !== "low" || elevatedCells.length === 0) {
        const labelEntity = dataSource.entities.add({
          id: `jam-lbl-${cell.lat}-${cell.lng}`,
          position: Cesium.Cartesian3.fromDegrees(cell.lng, cell.lat, 5500),
          label: {
            text: `${cell.level === "low" ? "GPS" : "⚠"} ${cell.pct}%`,
            font: "13px DM Sans, sans-serif",
            fillColor: cell.level === "high" ? cachedColor("#ff5252") : cachedColor("#ffd54f"),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1.0, 8e6, 0.4),
          },
        })
        this._gpsJammingEntities.push(labelEntity)
      }
    })
    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  // Generate 6 vertices of a flat-top hexagon at (lat, lng) with given radius in degrees.
  // Corrects longitude for latitude so hexagons appear regular on the globe.

  GlobeController.prototype._hexVertices = function(lat, lng, radius) {
    const vertices = []
    const cosLat = Math.cos(lat * Math.PI / 180)
    const lngR = cosLat > 0.01 ? radius / cosLat : radius
    for (let i = 0; i < 6; i++) {
      const angle = (Math.PI / 3) * i  // flat-top: 0°, 60°, 120°...
      vertices.push([
        lat + radius * Math.sin(angle),
        lng + lngR * Math.cos(angle),
      ])
    }
    return vertices
  }

  GlobeController.prototype._clearGpsJammingEntities = function() {
    const ds = this.getGpsJammingDataSource()
    ds.entities.suspendEvents()
    this._gpsJammingEntities.forEach(e => ds.entities.remove(e))
    ds.entities.resumeEvents()
    this._gpsJammingEntities = []
  }

  GlobeController.prototype.showGpsJammingDetail = function(cellKey) {
    const cell = (this._gpsJammingData || []).find(entry => `${entry.lat}-${entry.lng}` === cellKey)
    if (!cell) return false

    const color = cell.level === "high" ? "#ff5252" : cell.level === "medium" ? "#ff7043" : "#ffca28"
    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-satellite-dish" style="margin-right:6px;"></i>GPS Interference
      </div>
      <div class="detail-country">${cell.level.toUpperCase()} cell</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Degraded</span>
          <span class="detail-value" style="color:${color};">${cell.pct}%</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Aircraft</span>
          <span class="detail-value">${cell.bad} / ${cell.total}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Latitude</span>
          <span class="detail-value">${Number(cell.lat).toFixed(2)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Longitude</span>
          <span class="detail-value">${Number(cell.lng).toFixed(2)}</span>
        </div>
      </div>
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Derived from ADS-B position quality (NACp)</div>
    `
    this.detailPanelTarget.style.display = ""
    return true
  }
}
