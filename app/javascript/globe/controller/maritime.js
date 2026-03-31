import { getDataSource } from "../utils"

export function applyMaritimeMethods(GlobeController) {
  GlobeController.prototype.fetchShips = async function() {
    if (!this.shipsVisible || this._timelineActive) return

    this._toast("Loading ships...")
    try {
      let url = "/api/ships"
      const bounds = this.getFilterBounds()
      if (bounds) {
        const params = new URLSearchParams(bounds).toString()
        url += `?${params}`
      }

      const response = await fetch(url)
      if (!response.ok) return

      let ships = await response.json()

      if (this.hasActiveFilter()) {
        ships = ships.filter(s => s.latitude && s.longitude && this.pointPassesFilter(s.latitude, s.longitude))
      }

      this.renderShips(ships)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch ships:", e)
    }
  }

  GlobeController.prototype.createShipIcon = function(color) {
    const size = 24
    const canvas = document.createElement("canvas")
    canvas.width = size
    canvas.height = size
    const ctx = canvas.getContext("2d")

    ctx.translate(size / 2, size / 2)

    ctx.fillStyle = color
    ctx.beginPath()
    // Ship shape pointing up (bow at top)
    ctx.moveTo(0, -10)    // bow
    ctx.lineTo(5, -2)     // starboard bow
    ctx.lineTo(5, 7)      // starboard stern
    ctx.lineTo(3, 10)     // stern corner
    ctx.lineTo(-3, 10)
    ctx.lineTo(-5, 7)
    ctx.lineTo(-5, -2)
    ctx.closePath()
    ctx.fill()

    // Bridge/superstructure
    ctx.fillStyle = "rgba(255,255,255,0.3)"
    ctx.fillRect(-3, 0, 6, 4)

    return canvas.toDataURL()
  }

  GlobeController.prototype.renderShips = function(ships) {
    const Cesium = window.Cesium
    const dataSource = this.getShipsDataSource()
    const currentIds = new Set()

    if (!this._shipIcon) {
      this._shipIcon = this.createShipIcon("#26c6da")
    }

    dataSource.entities.suspendEvents()
    ships.forEach(ship => {
      if (!ship.latitude || !ship.longitude) return

      const mmsi = ship.mmsi
      currentIds.add(mmsi)

      const heading = ship.heading || ship.course || 0
      const speed = ship.speed || 0
      const name = (ship.name || mmsi).trim()

      const existing = this.shipData.get(mmsi)

      if (existing) {
        existing.heading = heading
        existing.speed = speed
        existing.course = ship.course
        existing.destination = ship.destination
        existing.flag = ship.flag
        existing.shipType = ship.ship_type
        existing.name = name
        existing.latitude = ship.latitude
        existing.longitude = ship.longitude
        existing.currentLat = ship.latitude
        existing.currentLng = ship.longitude

        existing.entity.position = Cesium.Cartesian3.fromDegrees(ship.longitude, ship.latitude, 10)
        existing.entity.billboard.rotation = -Cesium.Math.toRadians(heading)
        existing.entity.label.text = name
      } else {
        const entity = dataSource.entities.add({
          id: `ship-${mmsi}`,
          position: Cesium.Cartesian3.fromDegrees(ship.longitude, ship.latitude, 10),
          billboard: {
            image: this._shipIcon,
            scale: 0.8,
            rotation: -Cesium.Math.toRadians(heading),
            alignedAxis: Cesium.Cartesian3.UNIT_Z,
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            scaleByDistance: new Cesium.NearFarScalar(1e4, 1.2, 5e6, 0.3),
            heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
          label: {
            text: name,
            font: "14px JetBrains Mono, monospace",
            fillColor: Cesium.Color.fromCssColorString("#26c6da").withAlpha(0.95),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            pixelOffset: new Cesium.Cartesian2(0, -16),
            scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 2e6, 0),
            translucencyByDistance: new Cesium.NearFarScalar(1e4, 1, 5e6, 0),
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
        })

        this.shipData.set(mmsi, {
          entity,
          mmsi,
          latitude: ship.latitude,
          longitude: ship.longitude,
          currentLat: ship.latitude,
          currentLng: ship.longitude,
          heading,
          speed,
          course: ship.course,
          destination: ship.destination,
          flag: ship.flag,
          shipType: ship.ship_type,
          name,
        })
      }
    })

    // Remove ships no longer in view
    for (const [mmsi, data] of this.shipData) {
      if (!currentIds.has(mmsi)) {
        dataSource.entities.remove(data.entity)
        this.shipData.delete(mmsi)
        if (this.selectedShips.has(mmsi)) {
          this.selectedShips.delete(mmsi)
          this._removeSelectionBox("ship", mmsi)
          this._renderSelectionTray()
        }
      }
    }
    dataSource.entities.resumeEvents()

    this._updateStats()
    if (this.hasActiveFilter() && this.entityListPanelTarget?.classList.contains("rp-pane--active")) {
      this.updateEntityList?.()
    }
    this._requestRender()
  }

  GlobeController.prototype.getShipsDataSource = function() { return getDataSource(this.viewer, this._ds, "ships") }

  GlobeController.prototype.getShipTypeName = function(type) {
    const types = {
      0: "Not available",
      30: "Fishing", 31: "Towing", 32: "Towing (large)", 33: "Dredging",
      34: "Diving ops", 35: "Military ops", 36: "Sailing", 37: "Pleasure craft",
      40: "High-speed craft", 50: "Pilot vessel", 51: "SAR vessel",
      52: "Tug", 53: "Port tender", 55: "Law enforcement",
      60: "Passenger", 61: "Passenger (hazardous A)", 69: "Passenger (no info)",
      70: "Cargo", 71: "Cargo (hazardous A)", 79: "Cargo (no info)",
      80: "Tanker", 81: "Tanker (hazardous A)", 89: "Tanker (no info)",
      90: "Other",
    }
    if (!type) return "Unknown"
    // Check exact match first, then by tens (e.g., 71 → 70 range)
    return types[type] || types[Math.floor(type / 10) * 10] || `Type ${type}`
  }

  GlobeController.prototype.showShipDetail = function(data) {
    const mmsi = data.mmsi || data.entity?.id?.replace("ship-", "")
    this._focusedSelection = { type: "ship", id: mmsi }
    this._renderSelectionTray()
    const speedKnots = data.speed ? Math.round(data.speed * 10) / 10 + " kn" : "—"
    const courseDisplay = data.course ? Math.round(data.course) + "°" : "—"
    const headingDisplay = data.heading ? Math.round(data.heading) + "°" : "—"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign">${data.name}</div>
      <div class="detail-country">${data.flag || "Unknown flag"}</div>
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
          <span class="detail-value" style="font-size:12px; opacity:0.7;">${data.entity.id.replace("ship-", "")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Destination</span>
          <span class="detail-value">${data.destination || "—"}</span>
        </div>
      </div>
      <div class="detail-links">
        <a href="https://www.marinetraffic.com/en/ais/details/ships/mmsi:${data.entity.id.replace("ship-", "")}" target="_blank" rel="noopener">MarineTraffic</a>
        <a href="https://www.vesselfinder.com/vessels?mmsi=${data.entity.id.replace("ship-", "")}" target="_blank" rel="noopener">VesselFinder</a>
      </div>
      ${this._connectionsPlaceholder()}
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: AIS (AISStream.io)</div>
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("ship", data.latitude || data.lat, data.longitude || data.lng)
  }

  GlobeController.prototype.toggleShips = function() {
    this.shipsVisible = this.hasShipsToggleTarget && this.shipsToggleTarget.checked
    if (this._timelineActive) {
      this._timelineOnLayerToggle?.()
      this._savePrefs()
      return
    }
    if (this._ds["ships"]) {
      this._ds["ships"].show = this.shipsVisible
      this._requestRender()
    }
    if (this.shipsVisible) {
      this.fetchShips()
      if (!this.shipInterval) {
        this.shipInterval = setInterval(() => this.fetchShips(), 60000)
        this._shipCameraCb = () => this.fetchShips()
        this.viewer.camera.moveEnd.addEventListener(this._shipCameraCb)
      }
    } else {
      if (this.shipInterval) { clearInterval(this.shipInterval); this.shipInterval = null }
      if (this._shipCameraCb) { this.viewer.camera.moveEnd.removeEventListener(this._shipCameraCb); this._shipCameraCb = null }
    }
    this._savePrefs()
  }

  // ── Country Borders, Selection & Draw Tool ───────────────

}
