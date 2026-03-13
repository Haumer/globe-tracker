import { getDataSource, haversineDistance } from "../../utils"

export function applyNotamsMethods(GlobeController) {
  GlobeController.prototype.getNotamsDataSource = function() { return getDataSource(this.viewer, this._ds, "notams") }

  GlobeController.prototype.toggleNotams = function() {
    this.notamsVisible = this.hasNotamsToggleTarget && this.notamsToggleTarget.checked
    if (this.notamsVisible) {
      this.fetchNotams()
      if (!this._notamCameraCb) {
        this._notamCameraCb = () => { if (this.notamsVisible) this.fetchNotams() }
        this.viewer.camera.moveEnd.addEventListener(this._notamCameraCb)
      }
    } else {
      this._clearNotamEntities()
      if (this._notamCameraCb) { this.viewer.camera.moveEnd.removeEventListener(this._notamCameraCb); this._notamCameraCb = null }
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchNotams = async function() {
    this._toast("Loading NOTAMs...")
    try {
      const bounds = this.getViewportBounds()
      let url = "/api/notams"
      if (bounds) {
        url += `?lamin=${bounds.lamin.toFixed(2)}&lamax=${bounds.lamax.toFixed(2)}&lomin=${bounds.lomin.toFixed(2)}&lomax=${bounds.lomax.toFixed(2)}`
      }
      const resp = await fetch(url)
      if (!resp.ok) return
      this._notamData = await resp.json()
      this.renderNotams()
      this._markFresh("notams")
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch NOTAMs:", e)
    }
  }

  GlobeController.prototype.renderNotams = function() {
    this._clearNotamEntities()
    if (!this._notamData || this._notamData.length === 0) return

    const Cesium = window.Cesium
    const dataSource = this.getNotamsDataSource()
    dataSource.entities.suspendEvents()

    const reasonColors = {
      "VIP Movement": "#ff1744",
      "White House": "#ff1744",
      "US Capitol": "#ff1744",
      "Washington DC SFRA": "#ff5252",
      "Washington DC FRZ": "#ff1744",
      "Camp David": "#ff1744",
      "Wildfire": "#ff6d00",
      "Space Operations": "#7c4dff",
      "Sporting Event": "#00c853",
      "Security": "#ff9100",
      "Restricted Area": "#d50000",
      "Hazard": "#ffab00",
      "TFR": "#ef5350",
      "Nuclear Facility": "#ffea00",
      "Government": "#ff1744",
      "Military": "#d50000",
      "Conflict Zone": "#ff3d00",
      "Environmental": "#00e676",
      "Danger": "#ff6d00",
      "Prohibited": "#d50000",
      "Warning": "#ffab00",
    }

    this._notamData.forEach((n) => {
      const color = reasonColors[n.reason] || "#ef5350"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const radius = n.radius_m || 5556

      const altLow = (n.alt_low_ft || 0) * 0.3048
      const altHigh = Math.min((n.alt_high_ft || 18000) * 0.3048, 60000)

      const ellipse = dataSource.entities.add({
        id: `notam-${n.id}`,
        position: Cesium.Cartesian3.fromDegrees(n.lng, n.lat, 0),
        ellipse: {
          semiMinorAxis: radius,
          semiMajorAxis: radius,
          height: altLow,
          extrudedHeight: altHigh,
          material: cesiumColor.withAlpha(0.08),
          outline: true,
          outlineColor: cesiumColor.withAlpha(0.4),
          outlineWidth: 1,
        },
      })
      this._notamEntities.push(ellipse)

      const label = dataSource.entities.add({
        id: `notam-lbl-${n.id}`,
        position: Cesium.Cartesian3.fromDegrees(n.lng, n.lat, altHigh + 500),
        label: {
          text: `⛔ ${n.reason}`,
          font: "bold 11px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 4,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 5e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(1e4, 1.0, 5e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._notamEntities.push(label)
    })
    dataSource.entities.resumeEvents(); this._requestRender()

    this._checkFlightNotamProximity()
  }

  GlobeController.prototype._clearNotamEntities = function() {
    const ds = this._ds["notams"]
    if (ds) {
      ds.entities.suspendEvents()
      this._notamEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents(); this._requestRender()
    }
    this._notamEntities = []
    this._clearFlightNotamWarnings()
  }

  GlobeController.prototype._checkFlightNotamProximity = function() {
    if (!this.notamsVisible || !this._notamData?.length) return
    this._clearFlightNotamWarnings()

    const Cesium = window.Cesium
    const dataSource = this.getNotamsDataSource()
    this._notamFlightWarnings = []

    this.flightData.forEach((f, icao24) => {
      if (!f.latitude || !f.longitude) return

      for (const n of this._notamData) {
        const dist = haversineDistance(
          { lat: f.latitude, lng: f.longitude },
          { lat: n.lat, lng: n.lng }
        )
        const proximityThreshold = (n.radius_m || 5556) * 1.5

        if (dist <= proximityThreshold) {
          const warningEntity = dataSource.entities.add({
            id: `notam-warn-${icao24}`,
            position: Cesium.Cartesian3.fromDegrees(f.longitude, f.latitude, (f.baro_altitude || 0)),
            ellipse: {
              semiMinorAxis: 8000,
              semiMajorAxis: 8000,
              material: Cesium.Color.RED.withAlpha(0.15),
              outline: true,
              outlineColor: Cesium.Color.RED.withAlpha(0.6),
              outlineWidth: 2,
              height: (f.baro_altitude || 0) - 500,
              extrudedHeight: (f.baro_altitude || 0) + 500,
            },
          })
          this._notamFlightWarnings.push(warningEntity)
          break
        }
      }
    })
  }

  GlobeController.prototype._clearFlightNotamWarnings = function() {
    if (!this._notamFlightWarnings) return
    const ds = this._ds["notams"]
    if (ds) {
      this._notamFlightWarnings.forEach(e => ds.entities.remove(e))
    }
    this._notamFlightWarnings = []
  }

  GlobeController.prototype.showNotamDetail = function(n) {
    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#ef5350;">
        <i class="fa-solid fa-ban" style="margin-right:6px;"></i>${this._escapeHtml(n.reason)}
      </div>
      <div class="detail-country">${this._escapeHtml(n.id)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Radius</span>
          <span class="detail-value">${n.radius_nm} NM (${(n.radius_m / 1000).toFixed(1)} km)</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Altitude</span>
          <span class="detail-value">${n.alt_low_ft?.toLocaleString() || 'SFC'} – ${n.alt_high_ft?.toLocaleString()} ft</span>
        </div>
        ${n.effective_start ? `<div class="detail-field">
          <span class="detail-label">Effective</span>
          <span class="detail-value" style="font-size:9px;">${n.effective_start}</span>
        </div>` : ""}
      </div>
      <div style="margin-top:8px;font:400 10px var(--gt-mono);color:var(--gt-text-dim);line-height:1.4;">${this._escapeHtml(n.text)}</div>
    `
    this.detailPanelTarget.style.display = ""
  }
}
