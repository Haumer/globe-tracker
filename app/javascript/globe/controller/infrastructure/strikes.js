import { getDataSource, cachedColor, LABEL_DEFAULTS } from "../../utils"

const SAT_NORAD = {
  "Suomi NPP": 37849, "NOAA-20": 43013, "NOAA-21": 54234,
  "Terra": 25994, "Aqua": 27424,
}

export function applyStrikesMethods(GlobeController) {
  GlobeController.prototype.getStrikesDataSource = function() {
    return getDataSource(this.viewer, this._ds, "strikes")
  }

  GlobeController.prototype.toggleStrikes = function() {
    this.strikesVisible = this.hasStrikesToggleTarget && this.strikesToggleTarget.checked
    if (this.strikesVisible) {
      this.fetchStrikes()
      if (!this._strikesInterval) {
        this._strikesInterval = setInterval(() => {
          if (this.strikesVisible) this.fetchStrikes()
        }, 300000) // refresh every 5 min
      }
    } else {
      this._clearStrikeEntities()
      if (this._strikesInterval) { clearInterval(this._strikesInterval); this._strikesInterval = null }
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchStrikes = async function() {
    this._toast("Loading strike detections...")
    try {
      const resp = await fetch("/api/strikes")
      if (!resp.ok) return
      const raw = await resp.json()
      this._strikeDetections = raw.map(r => ({
        id: r[0], lat: r[1], lng: r[2], brightness: r[3],
        confidence: r[4], satellite: r[5], instrument: r[6],
        frp: r[7], daynight: r[8], time: r[9],
      }))
      this.renderStrikes()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch strikes:", e)
    }
  }

  GlobeController.prototype.renderStrikes = function() {
    this._clearStrikeEntities()
    if (!this._strikeDetections?.length || !this.strikesVisible) return

    const Cesium = window.Cesium
    const dataSource = this.getStrikesDataSource()
    const color = cachedColor("#e040fb") // magenta

    const bounds = this.getViewportBounds()

    dataSource.entities.suspendEvents()
    this._strikeDetections.forEach(s => {
      if (bounds && (s.lat < bounds.lamin || s.lat > bounds.lamax || s.lng < bounds.lomin || s.lng > bounds.lomax)) return
      if (this.hasActiveFilter && this.hasActiveFilter() && !this.pointPassesFilter(s.lat, s.lng)) return

      const frp = s.frp || 1
      const pixelSize = Math.min(8 + Math.sqrt(frp) * 1.0, 20)

      // Glow ring
      if (frp > 10) {
        const ring = dataSource.entities.add({
          id: `strike-ring-${s.id}`,
          position: Cesium.Cartesian3.fromDegrees(s.lng, s.lat, 0),
          ellipse: {
            semiMinorAxis: Math.min(2000 + frp * 50, 15000),
            semiMajorAxis: Math.min(2000 + frp * 50, 15000),
            material: color.withAlpha(0.1),
            outline: true,
            outlineColor: color.withAlpha(0.3),
            outlineWidth: 1,
            height: 0,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            classificationType: Cesium.ClassificationType.BOTH,
          },
        })
        this._strikeEntities.push(ring)
      }

      const entity = dataSource.entities.add({
        id: `strike-${s.id}`,
        position: Cesium.Cartesian3.fromDegrees(s.lng, s.lat, 10),
        point: {
          pixelSize,
          color: color.withAlpha(0.95),
          outlineColor: color.withAlpha(0.4),
          outlineWidth: 2,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 8e6, 0.4),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._strikeEntities.push(entity)
    })
    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._clearStrikeEntities = function() {
    const ds = this._ds["strikes"]
    if (ds) {
      ds.entities.suspendEvents()
      this._strikeEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
      this._requestRender()
    }
    this._strikeEntities = []
  }

  GlobeController.prototype.showStrikeDetail = function(s) {
    const date = s.time ? new Date(s.time) : null
    const ago = date ? this._timeAgo(date) : "Unknown"
    const timeStr = date ? date.toUTCString().replace("GMT", "UTC") : "Unknown"

    const noradId = SAT_NORAD[s.satellite]
    const satLink = noradId
      ? `<button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;"
           data-action="click->globe#flyToSatellite" data-norad="${noradId}">
           <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Track ${this._escapeHtml(s.satellite)}
         </button>`
      : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#e040fb;">
        <i class="fa-solid fa-crosshairs" style="margin-right:6px;"></i>Possible Strike
      </div>
      <div style="margin:4px 0 8px;padding:4px 8px;background:rgba(224,64,251,0.1);border:1px solid rgba(224,64,251,0.3);border-radius:4px;font:500 9px var(--gt-mono);color:#e040fb;letter-spacing:0.5px;">THERMAL ANOMALY IN ACTIVE CONFLICT ZONE</div>
      <div class="detail-country">${s.lat.toFixed(3)}°, ${s.lng.toFixed(3)}°</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Fire Power</span>
          <span class="detail-value">${s.frp ? s.frp.toFixed(1) + " MW" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Brightness</span>
          <span class="detail-value">${s.brightness ? s.brightness.toFixed(1) + " K" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Day/Night</span>
          <span class="detail-value">${s.daynight === "D" ? "Day" : "Night"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Detected by</span>
          <span class="detail-value" style="color:#ce93d8;">${this._escapeHtml(s.satellite || "Unknown")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Time</span>
          <span class="detail-value">${ago}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Timestamp</span>
          <span class="detail-value" style="font-size:9px;">${timeStr}</span>
        </div>
      </div>
      ${satLink}
      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("fire_hotspot", s.lat, s.lng, { satellite: s.satellite })
  }
}
