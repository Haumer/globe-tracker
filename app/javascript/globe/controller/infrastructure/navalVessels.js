import { getDataSource, LABEL_DEFAULTS } from "globe/utils"

function createNavalIcon() {
  const size = 28
  const canvas = document.createElement("canvas")
  canvas.width = size; canvas.height = size
  const ctx = canvas.getContext("2d")
  const color = "#42a5f5"

  // Ship hull shape
  ctx.fillStyle = color
  ctx.globalAlpha = 0.2
  ctx.beginPath()
  ctx.moveTo(14, 4)
  ctx.lineTo(24, 18)
  ctx.lineTo(20, 24)
  ctx.lineTo(8, 24)
  ctx.lineTo(4, 18)
  ctx.closePath()
  ctx.fill()

  ctx.globalAlpha = 1.0
  ctx.strokeStyle = color
  ctx.lineWidth = 1.5
  ctx.stroke()

  // Mast
  ctx.beginPath()
  ctx.moveTo(14, 8)
  ctx.lineTo(14, 16)
  ctx.stroke()

  // Crossbar
  ctx.beginPath()
  ctx.moveTo(10, 12)
  ctx.lineTo(18, 12)
  ctx.stroke()

  return canvas.toDataURL()
}

export function applyNavalVesselsMethods(GlobeController) {
  GlobeController.prototype.getNavalVesselsDataSource = function() {
    return getDataSource(this.viewer, this._ds, "naval-vessels")
  }

  GlobeController.prototype.fetchNavalVessels = async function() {
    if (!this.navalVesselsVisible || this._timelineActive) return

    try {
      const bounds = this.getFilterBounds?.() || this.getViewportBounds?.()
      const params = new URLSearchParams({ filter: "naval" })
      if (bounds) Object.entries(bounds).forEach(([key, value]) => params.set(key, value))

      const response = await fetch(`/api/ships?${params.toString()}`)
      if (!response.ok) return

      const ships = await response.json()
      this._navalShipData = new Map(
        ships
          .filter(ship => ship.latitude && ship.longitude)
          .map(ship => {
            const mmsi = `${ship.mmsi}`
            const name = (ship.name || ship.mmsi || "").trim()
            return [mmsi, {
              mmsi,
              latitude: ship.latitude,
              longitude: ship.longitude,
              currentLat: ship.latitude,
              currentLng: ship.longitude,
              heading: ship.heading || ship.course || 0,
              speed: ship.speed,
              course: ship.course,
              destination: ship.destination,
              flag: ship.flag,
              shipType: ship.ship_type,
              name,
              _layerKind: "naval_vessel",
            }]
          })
      )

      this.renderNavalVessels()
    } catch (error) {
      console.error("Naval vessels fetch failed:", error)
    }
  }

  GlobeController.prototype.toggleNavalVessels = function() {
    this.navalVesselsVisible = this.hasNavalVesselsToggleTarget && this.navalVesselsToggleTarget.checked
    if (this._timelineActive) {
      this._timelineOnLayerToggle?.()
      this._syncQuickBar()
      this._savePrefs()
      return
    }
    if (this.navalVesselsVisible) {
      this.fetchNavalVessels()
      if (!this._navalShipInterval) {
        this._navalShipInterval = setInterval(() => {
          if (this.navalVesselsVisible) this.fetchNavalVessels()
        }, 60000)
      }
      if (!this._navalCameraCb) {
        this._navalCameraCb = () => { if (this.navalVesselsVisible) this.fetchNavalVessels() }
        this.viewer.camera.moveEnd.addEventListener(this._navalCameraCb)
      }
    } else {
      this._clearNavalVesselEntities()
      this._navalShipData.clear()
      if (this._navalShipInterval) {
        clearInterval(this._navalShipInterval)
        this._navalShipInterval = null
      }
      if (this._navalCameraCb) {
        this.viewer.camera.moveEnd.removeEventListener(this._navalCameraCb)
        this._navalCameraCb = null
      }
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.renderNavalVessels = function() {
    if (!this.navalVesselsVisible) return
    this._clearNavalVesselEntities()

    const Cesium = window.Cesium
    const dataSource = this.getNavalVesselsDataSource()
    if (!this._navalIcon) this._navalIcon = createNavalIcon()
    const color = Cesium.Color.fromCssColorString("#42a5f5")

    const navalShips = []
    this._navalShipData.forEach((ship, mmsi) => {
      if (this.hasActiveFilter && this.hasActiveFilter()) {
        const lat = ship.currentLat || ship.latitude
        const lng = ship.currentLng || ship.longitude
        if (!this.pointPassesFilter(lat, lng)) return
      }
      navalShips.push({ mmsi, ...ship })
    })

    dataSource.entities.suspendEvents()
    navalShips.forEach(ship => {
      const lat = ship.currentLat || ship.latitude
      const lng = ship.currentLng || ship.longitude
      const heading = ship.heading || 0

      const entity = dataSource.entities.add({
        id: `naval-${ship.mmsi}`,
        position: Cesium.Cartesian3.fromDegrees(lng, lat, 10),
        billboard: {
          image: this._navalIcon,
          scale: 1.0,
          rotation: -Cesium.Math.toRadians(heading),
          alignedAxis: Cesium.Cartesian3.UNIT_Z,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.2, 8e6, 0.4),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: ship.name || ship.mmsi,
          font: LABEL_DEFAULTS.font,
          fillColor: color.withAlpha(0.95),
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
      this._navalVesselEntities.push(entity)
    })

    dataSource.entities.resumeEvents()
    this._updateStats?.()
    this._requestRender()
  }

  GlobeController.prototype._clearNavalVesselEntities = function() {
    const ds = this._ds["naval-vessels"]
    if (ds) {
      ds.entities.suspendEvents()
      this._navalVesselEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
      this._requestRender()
    }
    this._navalVesselEntities = []
  }

  GlobeController.prototype.showNavalVesselDetail = function(data) {
    const color = "#42a5f5"
    const speedKnots = data.speed != null ? data.speed.toFixed(1) + " kn" : "—"
    const courseDisplay = data.course != null ? data.course.toFixed(1) + "°" : "—"
    const headingDisplay = data.heading != null ? data.heading.toFixed(1) + "°" : "—"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-ship" style="margin-right:6px;"></i>${this._escapeHtml(data.name || data.mmsi || "Naval Vessel")}
      </div>
      <div style="margin:4px 0 8px;padding:3px 8px;background:rgba(66,165,245,0.12);border:1px solid rgba(66,165,245,0.3);border-radius:4px;font:600 9px var(--gt-mono);color:#42a5f5;letter-spacing:1px;text-transform:uppercase;">NAVAL / MILITARY VESSEL</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Type</span>
          <span class="detail-value">${this.getShipTypeName(data.shipType)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Speed</span>
          <span class="detail-value">${speedKnots}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Course</span>
          <span class="detail-value">${courseDisplay}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Heading</span>
          <span class="detail-value">${headingDisplay}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">MMSI</span>
          <span class="detail-value">${this._escapeHtml(String(data.mmsi || "—"))}</span>
        </div>
        ${data.flag ? `<div class="detail-field"><span class="detail-label">Flag</span><span class="detail-value">${this._escapeHtml(data.flag)}</span></div>` : ""}
        ${data.destination ? `<div class="detail-field"><span class="detail-label">Destination</span><span class="detail-value">${this._escapeHtml(data.destination)}</span></div>` : ""}
      </div>
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: AIS (AISStream.io)</div>
      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
    const lat = data.currentLat || data.latitude
    const lng = data.currentLng || data.longitude
    this._fetchConnections("ship", lat, lng, { mmsi: data.mmsi })
  }
}
