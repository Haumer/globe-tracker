import { getDataSource, cachedColor } from "../utils"

export function applyFiresMethods(GlobeController) {

  GlobeController.prototype.getFiresDataSource = function() { return getDataSource(this.viewer, this._ds, "fires") }

  GlobeController.prototype.toggleFireHotspots = function() {
    this.fireHotspotsVisible = this.hasFireHotspotsToggleTarget && this.fireHotspotsToggleTarget.checked
    if (this.fireHotspotsVisible) {
      this.fetchFireHotspots()
    } else {
      this._clearFireHotspotEntities()
      this._fireHotspotData = []
    }
    this._startFiresRefresh()
    this._updateStats()
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._startFiresRefresh = function() {
    if (this._firesInterval) clearInterval(this._firesInterval)
    if (this.fireHotspotsVisible) {
      this._firesInterval = setInterval(() => {
        if (this.fireHotspotsVisible && !this._timelineActive) this.fetchFireHotspots()
      }, 600000) // refresh every 10 min
    }
  }

  GlobeController.prototype.fetchFireHotspots = async function() {
    if (this._timelineActive) return
    this._toast("Loading fire hotspots...")
    try {
      const resp = await fetch("/api/fire_hotspots")
      if (!resp.ok) return
      const raw = await resp.json()
      // API returns arrays: [id, lat, lng, brightness, confidence, satellite, instrument, frp, daynight, time]
      this._fireHotspotData = raw.map(r => ({
        id: r[0], lat: r[1], lng: r[2], brightness: r[3],
        confidence: r[4], satellite: r[5], instrument: r[6],
        frp: r[7], daynight: r[8], time: r[9],
      }))
      this._handleBackgroundRefresh(resp, "fire-hotspots", this._fireHotspotData.length > 0, () => {
        if (this.fireHotspotsVisible && !this._timelineActive) this.fetchFireHotspots()
      })
      this.renderFireHotspots()
      this._markFresh("fireHotspots")
      this._updateStats()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch fire hotspots:", e)
    }
  }

  GlobeController.prototype.renderFireHotspots = function() {
    const Cesium = window.Cesium
    this._clearFireHotspotEntities()
    const dataSource = this.getFiresDataSource()

    const bounds = this.getViewportBounds()

    dataSource.entities.suspendEvents()
    this._fireHotspotData.forEach(f => {
      if (bounds && (f.lat < bounds.lamin || f.lat > bounds.lamax || f.lng < bounds.lomin || f.lng > bounds.lomax)) return
      if (this.hasActiveFilter && this.hasActiveFilter() && !this.pointPassesFilter(f.lat, f.lng)) return

      const frp = f.frp || 1
      const brightness = f.brightness || 300

      // Color by brightness/FRP: yellow → orange → red → deep red
      let color
      if (brightness < 320) color = cachedColor("#ffd54f")
      else if (brightness < 350) color = cachedColor("#ff9800")
      else if (brightness < 400) color = cachedColor("#ff5722")
      else color = cachedColor("#d50000")

      const pixelSize = Math.min(4 + Math.sqrt(frp) * 0.8, 16)

      // Glow ring for high-confidence fires
      const isHigh = f.confidence === "high" || f.confidence === "h" || parseInt(f.confidence) >= 80
      if (isHigh && frp > 10) {
        const ring = dataSource.entities.add({
          id: `fire-ring-${f.id}`,
          position: Cesium.Cartesian3.fromDegrees(f.lng, f.lat, 0),
          ellipse: {
            semiMinorAxis: Math.min(5000 + frp * 200, 50000),
            semiMajorAxis: Math.min(5000 + frp * 200, 50000),
            material: color.withAlpha(0.08),
            outline: true,
            outlineColor: color.withAlpha(0.2),
            outlineWidth: 1,
            height: 0,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            classificationType: Cesium.ClassificationType.BOTH,
          },
        })
        this._fireHotspotEntities.push(ring)
      }

      const entity = dataSource.entities.add({
        id: `fire-${f.id}`,
        position: Cesium.Cartesian3.fromDegrees(f.lng, f.lat, 10),
        point: {
          pixelSize,
          color: color.withAlpha(0.9),
          outlineColor: color.withAlpha(0.3),
          outlineWidth: 1,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 8e6, 0.3),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._fireHotspotEntities.push(entity)
    })
    dataSource.entities.resumeEvents()

    this._requestRender()
  }

  GlobeController.prototype._clearFireHotspotEntities = function() {
    const ds = this._ds["fires"]
    if (ds) {
      ds.entities.suspendEvents()
      this._fireHotspotEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
      this._requestRender()
    }
    this._fireHotspotEntities = []
  }

  // ── Satellite NORAD IDs for FIRMS satellites ──────────────────
  const SAT_NORAD = {
    "Suomi NPP": 37849,
    "NOAA-20": 43013,
    "NOAA-21": 54234,
    "Terra": 25994,
    "Aqua": 27424,
  }

  GlobeController.prototype.showFireHotspotDetail = function(f) {
    const date = f.time ? new Date(f.time) : null
    const ago = date ? this._timeAgo(date) : "Unknown"
    const timeStr = date ? date.toUTCString().replace("GMT", "UTC") : "Unknown"

    const confColor = (f.confidence === "high" || f.confidence === "h" || parseInt(f.confidence) >= 80) ? "#f44336"
      : (f.confidence === "nominal" || f.confidence === "n" || (parseInt(f.confidence) >= 30 && parseInt(f.confidence) < 80)) ? "#ff9800"
      : "#66bb6a"
    const confLabel = f.confidence || "unknown"

    const noradId = SAT_NORAD[f.satellite]
    const satLink = noradId
      ? `<button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;"
           data-action="click->globe#flyToSatellite" data-norad="${noradId}">
           <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Track ${this._escapeHtml(f.satellite)}
         </button>`
      : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#ff5722;">
        <i class="fa-solid fa-fire" style="margin-right:6px;"></i>Active Fire / Hotspot
      </div>
      <div class="detail-country">${f.lat.toFixed(3)}°, ${f.lng.toFixed(3)}°</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Brightness</span>
          <span class="detail-value">${f.brightness ? f.brightness.toFixed(1) + " K" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Confidence</span>
          <span class="detail-value" style="color:${confColor};">${confLabel}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Fire Power</span>
          <span class="detail-value">${f.frp ? f.frp.toFixed(1) + " MW" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Day/Night</span>
          <span class="detail-value">${f.daynight === "D" ? "☀ Day" : "🌙 Night"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Detected by</span>
          <span class="detail-value" style="color:#ce93d8;">${this._escapeHtml(f.satellite || "Unknown")} (${f.instrument || "?"})</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Time</span>
          <span class="detail-value">${ago}</span>
        </div>
      </div>
      ${satLink}
      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("fire_hotspot", f.lat, f.lng, { satellite: f.satellite })

    // Draw arc from detecting satellite to fire location
    if (noradId) this._drawSatFireArc(f, noradId)

    // Fly to fire
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(f.lng, f.lat, 300000),
      duration: 1.5,
    })
  }

  // Draw an arc from the detecting satellite's current position to the fire
  GlobeController.prototype._drawSatFireArc = function(fire, noradId) {
    this._clearSatFireArc()
    const Cesium = window.Cesium

    // Find the satellite entity
    const satEntity = this._findSatelliteByNorad(noradId)
    if (!satEntity) return

    const satPos = satEntity.position?.getValue(this.viewer.clock.currentTime)
    if (!satPos) return

    const firePos = Cesium.Cartesian3.fromDegrees(fire.lng, fire.lat, 0)

    const dataSource = this.getFiresDataSource()
    this._satFireArc = dataSource.entities.add({
      id: "sat-fire-arc",
      polyline: {
        positions: [satPos, firePos],
        width: 1.5,
        material: new Cesium.PolylineDashMaterialProperty({
          color: Cesium.Color.fromCssColorString("#ce93d8").withAlpha(0.6),
          dashLength: 12,
        }),
        arcType: Cesium.ArcType.NONE,
      },
    })
    this._requestRender()
  }

  GlobeController.prototype._clearSatFireArc = function() {
    if (this._satFireArc) {
      const ds = this._ds["fires"]
      if (ds) ds.entities.remove(this._satFireArc)
      this._satFireArc = null
      this._requestRender()
    }
  }

  GlobeController.prototype._findSatelliteByNorad = function(noradId) {
    // Search through all satellite datasources
    for (const [key, ds] of Object.entries(this._ds)) {
      if (!key.startsWith("sat-")) continue
      const entities = ds.entities.values
      for (let i = 0; i < entities.length; i++) {
        const e = entities[i]
        if (e.id && String(e.id) === String(noradId)) return e
      }
    }
    return null
  }

  GlobeController.prototype.flyToSatellite = function(event) {
    const noradId = event.currentTarget.dataset.norad
    const satEntity = this._findSatelliteByNorad(noradId)
    if (satEntity) {
      this.viewer.flyTo(satEntity, { duration: 1.5 })
    } else {
      this._toast("Satellite not loaded — enable the relevant satellite category first")
      setTimeout(() => this._toastHide(), 3000)
    }
  }
}
