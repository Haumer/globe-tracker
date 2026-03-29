import { getDataSource } from "../utils"

export function applySelectionEntityMethods(GlobeController) {
  GlobeController.prototype.updateEntityList = function() {
    const anySatsVisible = Object.values(this.satCategoryVisible).some(Boolean)
    if (!this.hasActiveFilter() || (!this.flightsVisible && !this.shipsVisible && !anySatsVisible)) {
      this._entityListRequested = false
      if (this._syncRightPanels) this._syncRightPanels()
      return
    }

    const flights = this.flightsVisible
      ? [...this.flightData.values()].filter(f => f.currentLat && f.currentLng && this.pointPassesFilter(f.currentLat, f.currentLng))
      : []
    const ships = this.shipsVisible
      ? [...this.shipData.values()].filter(s => s.latitude && s.longitude && this.pointPassesFilter(s.latitude, s.longitude))
      : []
    const sats = this.satelliteData.filter(s => {
      if (!this.satCategoryVisible[s.category]) return false
      const entity = this.satelliteEntities.get(`sat-${s.norad_id}`)
      return !!entity
    }).filter(s => {
      const sat = window.satellite
      if (!sat) return false
      try {
        const now = new Date()
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) return false
        const gmst = sat.gstime(now)
        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        return this.pointPassesFilter(sat.degreesLat(posGd.latitude), sat.degreesLong(posGd.longitude))
      } catch {
        return false
      }
    })

    this.entityFlightCountTarget.textContent = flights.length
    this.entityShipCountTarget.textContent = ships.length
    this.entitySatCountTarget.textContent = sats.length

    this._entityListData = { flights, ships, sats }

    const label = this._activeCircle
      ? "Circle Selection"
      : [...this.selectedCountries].join(", ")
    this.entityListHeaderTarget.textContent = label

    if (this._entityListRequested) {
      if (this._showRightPanel) this._showRightPanel("entities")
    }

    const activeTab = this.entityListPanelTarget.querySelector(".entity-tab.active")?.dataset.tab || "flights"
    this.renderEntityTab(activeTab)
  }

  GlobeController.prototype.switchEntityTab = function(event) {
    const tab = event.currentTarget.dataset.tab
    this.entityListPanelTarget.querySelectorAll(".entity-tab").forEach(t => t.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this.renderEntityTab(tab)
  }

  GlobeController.prototype.renderEntityTab = function(tab) {
    const data = this._entityListData
    if (!data) return

    let html = ""

    if (tab === "flights") {
      if (this.hasEntityAirlineBarTarget) {
        this.entityAirlineBarTarget.style.display = data.flights.length > 0 ? "" : "none"
        this._updateAirlineChips()
      }

      if (this.selectedFlights.size > 0) {
        html = `<div class="entity-selection-bar">
          <span>${this.selectedFlights.size} selected</span>
          <button class="entity-clear-btn" data-action="click->globe#clearFlightSelection">Clear</button>
        </div>`
      }

      let flights = data.flights
      if (this._airlineFilter.size > 0) {
        flights = flights.filter(f => this._flightPassesAirlineFilter(f))
      }

      if (flights.length === 0) {
        html += '<div class="entity-empty">No flights in area</div>'
      } else {
        html += flights
          .map(f => ({ ...f, _mil: this._isMilitaryFlight(f), _sel: this.selectedFlights.has(f.id) ? 1 : 0 }))
          .sort((a, b) => (b._sel - a._sel) || (b._mil - a._mil) || (b.altitude || 0) - (a.altitude || 0))
          .map(f => {
            const alt = f.currentAlt || f.altitude || 0
            const vr = f.verticalRate || 0
            const isMil = f._mil
            const airlineCode = this._extractAirlineCode(f.callsign)
            const airlineName = airlineCode ? this._getAirlineName(airlineCode) : ""

            let statusIcon, statusColor
            if (isMil) {
              statusIcon = "fa-jet-fighter"
              statusColor = "#ef5350"
            } else if (f.onGround) {
              statusIcon = "fa-plane-arrival"
              statusColor = "#78909c"
            } else if (vr > 200) {
              statusIcon = "fa-plane-up"
              statusColor = "#66bb6a"
            } else if (vr < -200) {
              statusIcon = "fa-plane-down"
              statusColor = "#ffa726"
            } else {
              statusIcon = "fa-plane"
              statusColor = "#4fc3f7"
            }

            const altFt = Math.round(alt * 3.281)
            let altLabel
            if (f.onGround) altLabel = "GND"
            else if (altFt > 30000) altLabel = `FL${Math.round(altFt / 100)}`
            else altLabel = `${altFt.toLocaleString()} ft`

            const milBadge = isMil ? '<span class="entity-badge mil">MIL</span>' : ''
            const isSelected = this.selectedFlights.has(f.id)
            const selClass = isSelected ? " entity-selected" : ""
            const airlineLabel = airlineName && airlineName !== airlineCode ? airlineName : ""

            return `
          <div class="entity-row${isMil ? " entity-military" : ""}${selClass}" data-action="click->globe#flyToFlight" data-id="${f.id || f.hex}">
            <span class="entity-select-dot ${isSelected ? "active" : ""}"></span>
            <span class="entity-icon" style="color: ${statusColor}"><i class="fa-solid ${statusIcon}"></i></span>
            <span class="entity-name">${this._escapeHtml(f.callsign || f.id || "—")}${milBadge}</span>
            <span class="entity-detail">${this._escapeHtml(airlineLabel)}</span>
            <span class="entity-detail">${altLabel}</span>
          </div>`
          }).join("")
      }
    } else if (tab === "ships") {
      if (data.ships.length === 0) {
        html = '<div class="entity-empty">No ships in area</div>'
      } else {
        html = data.ships.map(s => `
          <div class="entity-row" data-action="click->globe#flyToShip" data-mmsi="${s.mmsi}">
            <span class="entity-icon"><i class="fa-solid fa-ship"></i></span>
            <span class="entity-name">${this._escapeHtml(s.name || String(s.mmsi))}</span>
            <span class="entity-detail">${s.speed != null ? s.speed.toFixed(1) + " kts" : ""}</span>
            <span class="entity-detail">${this._escapeHtml(s.flag || "")}</span>
          </div>
        `).join("")
      }
    } else if (tab === "satellites") {
      if (data.sats.length === 0) {
        html = '<div class="entity-empty">No satellites in area</div>'
      } else {
        html = data.sats.map(s => `
          <div class="entity-row" data-action="click->globe#flyToSat" data-norad="${s.norad_id}">
            <span class="entity-icon" style="color: ${this.satCategoryColors[s.category] || "#ab47bc"}"><i class="fa-solid fa-satellite"></i></span>
            <span class="entity-name">${this._escapeHtml(s.name)}</span>
            <span class="entity-detail">${this._escapeHtml(s.category)}</span>
          </div>
        `).join("")
      }
    }

    this.entityListContentTarget.innerHTML = html
  }

  GlobeController.prototype.closeEntityList = function() {
    this._entityListRequested = false
    if (this._syncRightPanels) this._syncRightPanels()
  }

  GlobeController.prototype.toggleFlightSelection = function(id) {
    if (this.selectedFlights.has(id)) {
      this.selectedFlights.delete(id)
      this._removeFlightHighlight(id)
    } else {
      this.selectedFlights.add(id)
      this._addFlightHighlight(id)
    }
    this._renderSelectionTray()
    if (this.entityListPanelTarget.classList.contains("rp-pane--active")) {
      this.renderEntityTab("flights")
    }
  }

  GlobeController.prototype.toggleShipSelection = function(mmsi) {
    if (this.selectedShips.has(mmsi)) {
      this.selectedShips.delete(mmsi)
      this._removeSelectionBox("ship", mmsi)
    } else {
      this.selectedShips.add(mmsi)
      this._addSelectionBox("ship", mmsi)
    }
    this._renderSelectionTray()
  }

  GlobeController.prototype.toggleSatSelection = function(noradId) {
    const key = String(noradId)
    if (this.selectedSats.has(key)) {
      this.selectedSats.delete(key)
      this._removeSelectionBox("sat", key)
    } else {
      this.selectedSats.add(key)
      this._addSelectionBox("sat", key)
    }
    this._renderSelectionTray()
  }

  GlobeController.prototype.clearAllSelections = function() {
    this.clearFlightSelection()
    for (const mmsi of this.selectedShips) this._removeSelectionBox("ship", mmsi)
    this.selectedShips.clear()
    for (const nid of this.selectedSats) this._removeSelectionBox("sat", nid)
    this.selectedSats.clear()
    this._focusedSelection = null
    this._renderSelectionTray()
  }

  GlobeController.prototype._renderSelectionTray = function() {
    const total = this.selectedFlights.size + this.selectedShips.size + this.selectedSats.size
    if (total === 0) {
      this.selectionTrayTarget.style.display = "none"
      return
    }

    this.selectionTrayTarget.style.display = ""
    let html = ""

    for (const id of this.selectedFlights) {
      const f = this.flightData.get(id)
      const name = f?.callsign || id
      const isMil = f && this._isMilitaryFlight(f)
      const focused = this._focusedSelection?.type === "flight" && this._focusedSelection?.id === id
      html += `<div class="sel-chip${focused ? " sel-focused" : ""}${isMil ? " sel-mil" : ""}" data-action="click->globe#focusSelection" data-sel-type="flight" data-sel-id="${id}">
        <i class="fa-solid fa-plane"></i>
        <span class="sel-chip-name">${this._escapeHtml(name)}</span>
        <button class="sel-chip-remove" data-action="click->globe#removeSelection" data-sel-type="flight" data-sel-id="${id}">&times;</button>
      </div>`
    }

    for (const mmsi of this.selectedShips) {
      const s = this.shipData.get(mmsi)
      const name = s?.name || mmsi
      const focused = this._focusedSelection?.type === "ship" && this._focusedSelection?.id === mmsi
      html += `<div class="sel-chip${focused ? " sel-focused" : ""}" data-action="click->globe#focusSelection" data-sel-type="ship" data-sel-id="${mmsi}">
        <i class="fa-solid fa-ship"></i>
        <span class="sel-chip-name">${this._escapeHtml(name)}</span>
        <button class="sel-chip-remove" data-action="click->globe#removeSelection" data-sel-type="ship" data-sel-id="${mmsi}">&times;</button>
      </div>`
    }

    for (const noradId of this.selectedSats) {
      const s = this.satelliteData.find(sat => String(sat.norad_id) === noradId)
      const name = s?.name || `SAT ${noradId}`
      const color = s ? (this.satCategoryColors[s.category] || "#ab47bc") : "#ab47bc"
      const focused = this._focusedSelection?.type === "sat" && String(this._focusedSelection?.id) === noradId
      html += `<div class="sel-chip${focused ? " sel-focused" : ""}" data-action="click->globe#focusSelection" data-sel-type="sat" data-sel-id="${noradId}" style="--sel-color: ${color}">
        <i class="fa-solid fa-satellite"></i>
        <span class="sel-chip-name">${this._escapeHtml(name)}</span>
        <button class="sel-chip-remove" data-action="click->globe#removeSelection" data-sel-type="sat" data-sel-id="${noradId}">&times;</button>
      </div>`
    }

    this.selectionTrayItemsTarget.innerHTML = html
    this._updateSelectionBoxColors()
  }

  GlobeController.prototype.focusSelection = function(event) {
    if (event.target.closest(".sel-chip-remove")) return
    const type = event.currentTarget.dataset.selType
    const id = event.currentTarget.dataset.selId

    this._focusedSelection = { type, id }

    if (type === "flight") {
      const f = this.flightData.get(id)
      if (f) {
        this._flyToCoordinates?.(f.currentLng, f.currentLat, 200000, { duration: 1.0 })
        this.showDetail(id, f)
        return
      }
    } else if (type === "ship") {
      const s = this.shipData.get(id)
      if (s) {
        this._flyToCoordinates?.(s.longitude, s.latitude, 100000, { duration: 1.0 })
        this.showShipDetail(s)
        return
      }
    } else if (type === "sat") {
      const Cesium = window.Cesium
      const noradId = parseInt(id)
      const s = this.satelliteData.find(sat => sat.norad_id === noradId)
      if (s) {
        const sat = window.satellite
        try {
          const now = new Date()
          const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
          const posVel = sat.propagate(satrec, now)
          if (posVel.position) {
            const gmst = sat.gstime(now)
            const posGd = sat.eciToGeodetic(posVel.position, gmst)
            const lng = sat.degreesLong(posGd.longitude)
            const lat = sat.degreesLat(posGd.latitude)
            const alt = posGd.height * 1000
            this.viewer.camera.flyTo({
              destination: Cesium.Cartesian3.fromDegrees(lng, lat, alt + 500000),
              duration: 1.0,
            })
          }
        } catch {}
        this.showSatelliteDetail(s)
        return
      }
    }
    this._renderSelectionTray()
  }

  GlobeController.prototype.removeSelection = function(event) {
    event.stopPropagation()
    const type = event.currentTarget.dataset.selType
    const id = event.currentTarget.dataset.selId

    if (type === "flight") {
      this.selectedFlights.delete(id)
      this._removeSelectionBox("flight", id)
    } else if (type === "ship") {
      this.selectedShips.delete(id)
      this._removeSelectionBox("ship", id)
    } else if (type === "sat") {
      this.selectedSats.delete(id)
      this._removeSelectionBox("sat", id)
    }

    if (this._focusedSelection?.type === type && String(this._focusedSelection?.id) === id) {
      this._focusedSelection = null
    }
    this._renderSelectionTray()
  }

  GlobeController.prototype._addFlightHighlight = function(id) {
    this._addSelectionBox("flight", id)
  }

  GlobeController.prototype._removeFlightHighlight = function(id) {
    this._removeSelectionBox("flight", id)
  }

  GlobeController.prototype._makeSelectionBracket = function(color, alpha) {
    const size = 48
    const c = document.createElement("canvas")
    c.width = size
    c.height = size
    const ctx = c.getContext("2d")
    const L = 12
    const pad = 2
    ctx.strokeStyle = color
    ctx.globalAlpha = alpha
    ctx.lineWidth = 2.5
    ctx.lineCap = "square"
    ctx.beginPath(); ctx.moveTo(pad, pad + L); ctx.lineTo(pad, pad); ctx.lineTo(pad + L, pad); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(size - pad - L, pad); ctx.lineTo(size - pad, pad); ctx.lineTo(size - pad, pad + L); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(pad, size - pad - L); ctx.lineTo(pad, size - pad); ctx.lineTo(pad + L, size - pad); ctx.stroke()
    ctx.beginPath(); ctx.moveTo(size - pad - L, size - pad); ctx.lineTo(size - pad, size - pad); ctx.lineTo(size - pad, size - pad - L); ctx.stroke()
    return c.toDataURL()
  }

  GlobeController.prototype._makeWebcamIcon = function(color = "#29b6f6", options = {}) {
    const mode = options.mode || "periodic"
    const size = 28
    const c = document.createElement("canvas")
    c.width = size
    c.height = size
    const ctx = c.getContext("2d")
    const cx = size / 2, cy = size / 2

    if (mode === "realtime" || mode === "live") {
      ctx.beginPath()
      ctx.arc(cx, cy, 11.5, 0, Math.PI * 2)
      ctx.fillStyle = mode === "realtime" ? "rgba(255,68,68,0.18)" : "rgba(76,175,80,0.16)"
      ctx.fill()
    }

    ctx.shadowColor = "rgba(0,0,0,0.5)"
    ctx.shadowBlur = 3
    ctx.shadowOffsetY = 1

    ctx.fillStyle = mode === "stale" ? "rgba(120, 130, 145, 0.85)" : color
    ctx.beginPath()
    ctx.roundRect(cx - 8, cy - 5, 16, 11, 2)
    ctx.fill()

    ctx.shadowBlur = 0
    ctx.fillStyle = "rgba(0,0,0,0.3)"
    ctx.beginPath()
    ctx.arc(cx, cy, 3.5, 0, Math.PI * 2)
    ctx.fill()
    ctx.fillStyle = "#fff"
    ctx.globalAlpha = 0.8
    ctx.beginPath()
    ctx.arc(cx, cy, 1.8, 0, Math.PI * 2)
    ctx.fill()
    ctx.globalAlpha = 1

    ctx.fillStyle = mode === "stale" ? "rgba(120, 130, 145, 0.85)" : color
    ctx.fillRect(cx - 3, cy - 7, 6, 3)

    if (mode === "realtime") {
      ctx.shadowBlur = 0
      ctx.fillStyle = "#ff5252"
      ctx.beginPath()
      ctx.arc(cx + 8, cy - 8, 3, 0, Math.PI * 2)
      ctx.fill()
      ctx.lineWidth = 1.5
      ctx.strokeStyle = "rgba(255,255,255,0.9)"
      ctx.stroke()
    } else if (mode === "live") {
      ctx.shadowBlur = 0
      ctx.strokeStyle = "rgba(255,255,255,0.8)"
      ctx.lineWidth = 1.5
      ctx.beginPath()
      ctx.arc(cx, cy, 10.5, 0, Math.PI * 2)
      ctx.stroke()
    }

    return c.toDataURL()
  }

  GlobeController.prototype._addSelectionBox = function(type, id) {
    const key = `${type}-${id}`
    if (this._selectionBoxEntities.has(key)) return

    const Cesium = window.Cesium
    const isFocused = this._focusedSelection?.type === type && String(this._focusedSelection?.id) === String(id)
    const img = isFocused ? this._selBoxImgGreen : this._selBoxImgYellow

    let positionProp
    let dataSource
    if (type === "flight") {
      dataSource = this.getFlightsDataSource()
      positionProp = new Cesium.CallbackProperty(() => {
        const fd = this.flightData.get(id)
        if (!fd) return Cesium.Cartesian3.fromDegrees(0, 0, 0)
        return Cesium.Cartesian3.fromDegrees(fd.currentLng, fd.currentLat, fd.currentAlt)
      }, false)
    } else if (type === "ship") {
      dataSource = getDataSource(this.viewer, this._ds, "ships")
      positionProp = new Cesium.CallbackProperty(() => {
        const sd = this.shipData.get(id)
        if (!sd) return Cesium.Cartesian3.fromDegrees(0, 0, 0)
        return Cesium.Cartesian3.fromDegrees(sd.currentLng, sd.currentLat, 0)
      }, false)
    } else if (type === "sat") {
      dataSource = this.getSatellitesDataSource()
      const noradId = parseInt(id)
      positionProp = new Cesium.CallbackProperty(() => {
        const ent = this.satelliteEntities.get(`sat-${noradId}`)
        return ent ? ent.position?.getValue(Cesium.JulianDate.now()) : Cesium.Cartesian3.fromDegrees(0, 0, 0)
      }, false)
    }

    if (!dataSource) return

    const entity = dataSource.entities.add({
      id: `selbox-${key}`,
      position: positionProp,
      billboard: {
        image: img,
        scale: type === "sat" ? 0.7 : 0.85,
        verticalOrigin: Cesium.VerticalOrigin.CENTER,
        horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
        scaleByDistance: type === "sat"
          ? new Cesium.NearFarScalar(5e5, 1.0, 1e7, 0.5)
          : new Cesium.NearFarScalar(1e5, 1.0, 5e6, 0.4),
      },
    })
    this._selectionBoxEntities.set(key, { entity, dataSource })
  }

  GlobeController.prototype._removeSelectionBox = function(type, id) {
    const key = `${type}-${id}`
    const entry = this._selectionBoxEntities.get(key)
    if (!entry) return
    try { entry.dataSource.entities.remove(entry.entity) } catch {}
    this._selectionBoxEntities.delete(key)
  }

  GlobeController.prototype._updateSelectionBoxColors = function() {
    for (const [key, entry] of this._selectionBoxEntities) {
      const [type, ...rest] = key.split("-")
      const id = rest.join("-")
      const isFocused = this._focusedSelection?.type === type && String(this._focusedSelection?.id) === String(id)
      entry.entity.billboard.image = isFocused ? this._selBoxImgGreen : this._selBoxImgYellow
    }
  }

  GlobeController.prototype.clearFlightSelection = function() {
    for (const id of this.selectedFlights) {
      this._removeFlightHighlight(id)
    }
    this.selectedFlights.clear()
    this._renderSelectionTray()
    if (this.entityListPanelTarget.classList.contains("rp-pane--active")) {
      this.renderEntityTab("flights")
    }
  }

  GlobeController.prototype.flyToFlight = function(event) {
    const id = event.currentTarget.dataset.id
    this.toggleFlightSelection(id)
    const f = this.flightData.get(id)
    if (f && f.currentLat && f.currentLng) {
      this._flyToCoordinates?.(f.currentLng, f.currentLat, 200000, { duration: 1.0 })
    }
  }

  GlobeController.prototype.flyToShip = function(event) {
    const mmsi = event.currentTarget.dataset.mmsi
    const s = this.shipData.get(mmsi)
    if (s && s.latitude && s.longitude) {
      this._flyToCoordinates?.(s.longitude, s.latitude, 100000, { duration: 1.0 })
    }
  }

  GlobeController.prototype.flyToSat = function(event) {
    const noradId = parseInt(event.currentTarget.dataset.norad)
    const s = this.satelliteData.find(sat => sat.norad_id === noradId)
    if (s) {
      const sat = window.satellite
      const now = new Date()
      try {
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (posVel.position) {
          const gmst = sat.gstime(now)
          const posGd = sat.eciToGeodetic(posVel.position, gmst)
          const lng = sat.degreesLong(posGd.longitude)
          const lat = sat.degreesLat(posGd.latitude)
          const alt = posGd.height * 1000
          this.viewer.camera.flyTo({
            destination: Cesium.Cartesian3.fromDegrees(lng, lat, alt + 500000),
            duration: 1.0,
          })
        }
      } catch {}
    }
  }
}
