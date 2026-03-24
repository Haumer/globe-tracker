import { getDataSource, createAirportIcon, cachedColor, LABEL_DEFAULTS } from "../../utils"

export function applyAirbasesMethods(GlobeController) {
  GlobeController.prototype.getAirbasesDataSource = function() {
    return getDataSource(this.viewer, this._ds, "airbases")
  }

  GlobeController.prototype.toggleAirbases = function() {
    this.airbasesVisible = this.hasAirbasesToggleTarget && this.airbasesToggleTarget.checked
    if (this.airbasesVisible) {
      this._ensureAirbaseData().then(() => { this.renderAirbases() })
      if (!this._airbaseCameraCb) {
        this._airbaseCameraCb = () => { if (this.airbasesVisible) this.renderAirbases() }
        this.viewer.camera.moveEnd.addEventListener(this._airbaseCameraCb)
      }
    } else {
      this._clearAirbaseEntities()
      if (this._airbaseCameraCb) {
        this.viewer.camera.moveEnd.removeEventListener(this._airbaseCameraCb)
        this._airbaseCameraCb = null
      }
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._ensureAirbaseData = async function() {
    if (this._airportDataLoaded) return
    await this._fetchAirportData()
  }

  GlobeController.prototype.renderAirbases = function() {
    if (!this._airportDb || !this.airbasesVisible) return

    const Cesium = window.Cesium
    const dataSource = this.getAirbasesDataSource()
    const bounds = this.getViewportBounds()
    const colorHex = "#ff7043"
    const icon = createAirportIcon(colorHex, true)
    const cesiumColor = Cesium.Color.fromCssColorString(colorHex)

    // Filter to military airports only
    let entries = Object.entries(this._airportDb).filter(([, ap]) => ap.military)

    if (bounds) {
      entries = entries.filter(([, ap]) =>
        ap.lat >= bounds.lamin && ap.lat <= bounds.lamax &&
        ap.lng >= bounds.lomin && ap.lng <= bounds.lomax
      )
    }
    if (this.hasActiveFilter && this.hasActiveFilter()) {
      entries = entries.filter(([, ap]) => this.pointPassesFilter(ap.lat, ap.lng))
    }

    const wantIds = new Set(entries.map(([icao]) => `airbase-${icao}`))

    dataSource.entities.suspendEvents()

    const keep = []
    for (const e of this._airbaseEntities) {
      if (!wantIds.has(e.id)) {
        dataSource.entities.remove(e)
      } else {
        wantIds.delete(e.id)
        keep.push(e)
      }
    }
    this._airbaseEntities = keep

    for (const [icao, ap] of entries) {
      if (!wantIds.has(`airbase-${icao}`)) continue

      const entity = dataSource.entities.add({
        id: `airbase-${icao}`,
        position: Cesium.Cartesian3.fromDegrees(ap.lng, ap.lat, 10),
        billboard: {
          image: icon,
          scale: 1.0,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.2, 1e7, 0.4),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: icao,
          font: LABEL_DEFAULTS.font,
          fillColor: cesiumColor.withAlpha(0.95),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          pixelOffset: LABEL_DEFAULTS.pixelOffsetBelow(),
          scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
          translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._airbaseEntities.push(entity)
    }

    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._clearAirbaseEntities = function() {
    const ds = this._ds["airbases"]
    if (ds) {
      ds.entities.suspendEvents()
      this._airbaseEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
      this._requestRender()
    }
    this._airbaseEntities = []
  }

  GlobeController.prototype.showAirbaseDetail = function(icao) {
    const ap = this._airportDb?.[icao]
    if (!ap) return

    const color = "#ff7043"
    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-tower-observation" style="margin-right:6px;"></i>${this._escapeHtml(ap.name || icao)}
      </div>
      <div class="detail-country">${ap.municipality ? this._escapeHtml(ap.municipality) + ", " : ""}${this._escapeHtml(ap.country || "")}</div>
      <div style="margin:4px 0 8px;padding:3px 8px;background:rgba(255,112,67,0.12);border:1px solid rgba(255,112,67,0.3);border-radius:4px;font:600 9px var(--gt-mono);color:#ff7043;letter-spacing:1px;text-transform:uppercase;">MILITARY AIRBASE</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">ICAO</span>
          <span class="detail-value">${icao}</span>
        </div>
        ${ap.iata ? `<div class="detail-field"><span class="detail-label">IATA</span><span class="detail-value">${ap.iata}</span></div>` : ""}
        <div class="detail-field">
          <span class="detail-label">Type</span>
          <span class="detail-value" style="color:${color};">${(ap.type || "").replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase())}</span>
        </div>
        ${ap.elevation ? `<div class="detail-field"><span class="detail-label">Elevation</span><span class="detail-value">${ap.elevation} ft</span></div>` : ""}
        <div class="detail-field">
          <span class="detail-label">Position</span>
          <span class="detail-value">${ap.lat.toFixed(4)}, ${ap.lng.toFixed(4)}</span>
        </div>
      </div>
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: OurAirports / FAA</div>
      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("airport", ap.lat, ap.lng, { icao })
  }
}
