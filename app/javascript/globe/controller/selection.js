import { getDataSource } from "../utils"

export function applySelectionMethods(GlobeController) {
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
      } catch { return false }
    })

    this.entityFlightCountTarget.textContent = flights.length
    this.entityShipCountTarget.textContent = ships.length
    this.entitySatCountTarget.textContent = sats.length

    // Store for tab rendering
    this._entityListData = { flights, ships, sats }

    // Set header
    const label = this._activeCircle
      ? "Circle Selection"
      : [...this.selectedCountries].join(", ")
    this.entityListHeaderTarget.textContent = label

    // Only open the panel if it was explicitly requested (country/circle selection)
    if (this._entityListRequested) {
      if (this._showRightPanel) this._showRightPanel("entities")
    }

    // Render active tab if entities pane is showing
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
      // Show airline bar in entity list
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

      // Apply airline filter
      let flights = data.flights
      if (this._airlineFilter.size > 0) {
        flights = flights.filter(f => this._flightPassesAirlineFilter(f))
      }

      if (flights.length === 0) {
        html += '<div class="entity-empty">No flights in area</div>'
      } else {
        // Sort: selected first, then military, then by altitude
        html += flights
          .map(f => ({ ...f, _mil: this._isMilitaryFlight(f), _sel: this.selectedFlights.has(f.id) ? 1 : 0 }))
          .sort((a, b) => (b._sel - a._sel) || (b._mil - a._mil) || (b.altitude || 0) - (a.altitude || 0))
          .map(f => {
          const alt = f.currentAlt || f.altitude || 0
          const vr = f.verticalRate || 0
          const spd = f.speed || 0
          const isMil = f._mil
          const airlineCode = this._extractAirlineCode(f.callsign)
          const airlineName = airlineCode ? this._getAirlineName(airlineCode) : ""

          // Status icon
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

          // Altitude label
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

  // ── Selection Tray ───────────────────────────────────────

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
    // Don't trigger if the remove button was clicked
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
        } catch { /* skip */ }
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

    // Clear focus if removing the focused item
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
    const L = 12 // bracket arm length
    const pad = 2
    ctx.strokeStyle = color
    ctx.globalAlpha = alpha
    ctx.lineWidth = 2.5
    ctx.lineCap = "square"
    // top-left
    ctx.beginPath(); ctx.moveTo(pad, pad + L); ctx.lineTo(pad, pad); ctx.lineTo(pad + L, pad); ctx.stroke()
    // top-right
    ctx.beginPath(); ctx.moveTo(size - pad - L, pad); ctx.lineTo(size - pad, pad); ctx.lineTo(size - pad, pad + L); ctx.stroke()
    // bottom-left
    ctx.beginPath(); ctx.moveTo(pad, size - pad - L); ctx.lineTo(pad, size - pad); ctx.lineTo(pad + L, size - pad); ctx.stroke()
    // bottom-right
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

    // Drop shadow
    ctx.shadowColor = "rgba(0,0,0,0.5)"
    ctx.shadowBlur = 3
    ctx.shadowOffsetY = 1

    // Camera body
    ctx.fillStyle = mode === "stale" ? "rgba(120, 130, 145, 0.85)" : color
    ctx.beginPath()
    ctx.roundRect(cx - 8, cy - 5, 16, 11, 2)
    ctx.fill()

    // Lens circle
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

    // Flash / top bump
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
    try { entry.dataSource.entities.remove(entry.entity) } catch { /* ds may be gone */ }
    this._selectionBoxEntities.delete(key)
  }

  GlobeController.prototype._updateSelectionBoxColors = function() {
    const Cesium = window.Cesium
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
      } catch { /* skip */ }
    }
  }

  // ── Search ─────────────────────────────────────────────────

  GlobeController.prototype.onSearchInput = function() {
    clearTimeout(this._searchDebounce)
    const query = this.searchInputTarget.value.trim()

    if (query.length === 0) {
      this.searchResultsTarget.style.display = "none"
      this.searchClearTarget.style.display = "none"
      return
    }

    this.searchClearTarget.style.display = "block"
    this._searchDebounce = setTimeout(() => this._runSearch(query), 150)
  }

  GlobeController.prototype.onSearchKeydown = function(event) {
    if (event.key === "Escape") {
      this.clearSearch()
      return
    }

    const rows = this.searchResultsTarget?.querySelectorAll(".search-result-row")
    if (!rows || rows.length === 0) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this._searchHighlight = Math.min((this._searchHighlight ?? -1) + 1, rows.length - 1)
      this._highlightSearchRow(rows)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this._searchHighlight = Math.max((this._searchHighlight ?? 0) - 1, 0)
      this._highlightSearchRow(rows)
    } else if (event.key === "Enter") {
      event.preventDefault()
      const idx = this._searchHighlight ?? 0
      if (this._searchResults?.[idx]) {
        this._activateSearchResult(idx)
      }
    }
  }

  GlobeController.prototype._highlightSearchRow = function(rows) {
    rows.forEach((r, i) => {
      r.style.background = i === this._searchHighlight ? "rgba(255,255,255,0.08)" : ""
    })
    rows[this._searchHighlight]?.scrollIntoView({ block: "nearest" })
  }

  GlobeController.prototype.clearSearch = function() {
    this.searchInputTarget.value = ""
    this.searchResultsTarget.style.display = "none"
    this.searchClearTarget.style.display = "none"
  }

  // ── Search source definitions ───────────────────────────────
  // Each entry defines how to search a specific entity type.
  // Flights, satellites, and airports have custom logic and are handled separately.
  const SEARCH_SOURCES = [
    {
      key: "earthquake",
      icon: "fa-house-crack",
      color: "#ff7043",
      getData: (ctrl) => ctrl._earthquakeData || [],
      fields: (item) => [item.title, `m${item.mag}`],
      toResult: (item) => ({
        name: `M${item.mag.toFixed(1)}`,
        detail: item.title,
        lat: item.lat, lng: item.lng, alt: 500000,
        data: item,
      }),
    },
    {
      key: "event",
      getData: (ctrl) => ctrl._naturalEventData || [],
      fields: (item) => [item.title, item.categoryTitle],
      toResult: (item, ctrl) => {
        const catInfo = ctrl.eonetCategoryIcons[item.categoryId] || { icon: "circle-exclamation", color: "#78909c" }
        return {
          icon: `fa-${catInfo.icon}`,
          color: catInfo.color,
          name: item.title.length > 30 ? item.title.substring(0, 28) + "…" : item.title,
          detail: item.categoryTitle,
          lat: item.lat, lng: item.lng, alt: 500000,
        }
      },
    },
    {
      key: "webcam",
      icon: "fa-video",
      color: "#29b6f6",
      getData: (ctrl) => ctrl._webcamData || [],
      fields: (item) => [item.title, item.city],
      toResult: (item) => ({
        name: item.title.length > 30 ? item.title.substring(0, 28) + "…" : item.title,
        detail: [item.city, item.country].filter(Boolean).join(", "),
        lat: item.lat, lng: item.lng, alt: 50000,
      }),
    },
    {
      key: "city",
      getData: (ctrl) => ctrl._citiesData || [],
      fields: (item) => [item.name, item.country],
      toResult: (item) => ({
        icon: item.capital ? "fa-landmark" : "fa-city",
        color: item.capital ? "#ffd54f" : "#e0e0e0",
        name: item.name,
        detail: `${item.country} · ${(item.population / 1e6).toFixed(1)}M`,
        lat: item.lat, lng: item.lng, alt: 200000,
      }),
    },
    {
      key: "power_plant",
      icon: "fa-plug",
      getData: (ctrl) => ctrl._powerPlantAll || [],
      fields: (item) => [item.name, item.fuel, item.country],
      toResult: (item) => ({
        color: item.fuel === "Nuclear" ? "#fdd835" : "#ff9800",
        name: item.name,
        detail: `${item.fuel || "?"} · ${item.capacity ? item.capacity.toLocaleString() + " MW" : "?"}`,
        lat: item.lat, lng: item.lng, alt: 200000,
        data: item,
      }),
    },
    {
      key: "conflict",
      icon: "fa-crosshairs",
      color: "#f44336",
      getData: (ctrl) => ctrl._conflictData || [],
      fields: (item) => [item.name, item.conflict],
      toResult: (item) => ({
        name: item.name || item.conflict,
        detail: item.conflict || "",
        lat: item.lat, lng: item.lng, alt: 300000,
        data: item,
      }),
    },
    {
      key: "fire_hotspot",
      icon: "fa-fire",
      color: "#ff5722",
      getData: (ctrl) => ctrl._fireHotspotData || [],
      fields: (item) => [item.satellite, "fire", "hotspot"],
      toResult: (item) => ({
        name: `Fire ${item.lat.toFixed(2)}°, ${item.lng.toFixed(2)}°`,
        detail: `${item.satellite || "?"} · ${item.frp ? item.frp.toFixed(0) + " MW" : "?"}`,
        lat: item.lat, lng: item.lng, alt: 300000,
        data: item,
      }),
    },
  ]

  GlobeController.prototype._runSearch = async function(query) {
    const q = query.toLowerCase()
    const results = []
    const MAX = 12

    // ── Flights (custom: iterates Map, checks airline name, dynamic icon/color) ──
    for (const [id, f] of this.flightData) {
      if (results.length >= MAX) break
      const cs = (f.callsign || "").toLowerCase()
      const ic = (f.id || "").toLowerCase()
      const airlineCode = this._extractAirlineCode(f.callsign)
      const airlineName = airlineCode ? this._getAirlineName(airlineCode).toLowerCase() : ""
      if (cs.includes(q) || ic.includes(q) || airlineName.includes(q)) {
        const isMil = this._isMilitaryFlight(f)
        results.push({
          type: "flight",
          icon: isMil ? "fa-jet-fighter" : "fa-plane",
          color: isMil ? "#ef5350" : "#4fc3f7",
          name: f.callsign || f.id,
          detail: airlineCode ? this._getAirlineName(airlineCode) : (f.originCountry || ""),
          lat: f.currentLat,
          lng: f.currentLng,
          alt: f.currentAlt || 200000,
          id,
        })
      }
    }

    // ── Ships (custom: iterates Map, uses mmsi as key) ──
    for (const [mmsi, s] of this.shipData) {
      if (results.length >= MAX) break
      const name = (s.name || "").toLowerCase()
      const mmsiStr = mmsi.toLowerCase()
      if (name.includes(q) || mmsiStr.includes(q)) {
        results.push({
          type: "ship",
          icon: "fa-ship",
          color: "#26c6da",
          name: s.name || mmsi,
          detail: s.flag || "",
          lat: s.latitude,
          lng: s.longitude,
          alt: 100000,
        })
      }
    }

    // ── Satellites (custom: local + server search, dedup by norad_id) ──
    const localSatIds = new Set()
    for (const s of this.satelliteData) {
      if (results.length >= MAX) break
      const name = (s.name || "").toLowerCase()
      const norad = String(s.norad_id)
      if (name.includes(q) || norad.includes(q)) {
        localSatIds.add(s.norad_id)
        results.push(this._satSearchResult(s))
      }
    }

    if (q.length >= 2 && results.filter(r => r.type === "satellite").length < 4) {
      try {
        const resp = await fetch(`/api/satellites/search?q=${encodeURIComponent(query)}`)
        if (resp.ok) {
          const serverSats = await resp.json()
          for (const s of serverSats) {
            if (results.length >= MAX) break
            if (localSatIds.has(s.norad_id)) continue
            results.push(this._satSearchResult(s))
          }
        }
      } catch { /* ignore */ }
    }

    // ── Airports (custom: conditional on airportsVisible, iterates Object entries) ──
    if (this.airportsVisible) {
      for (const [icao, ap] of Object.entries(this._airportDb)) {
        if (results.length >= MAX) break
        if (icao.toLowerCase().includes(q) || ap.name.toLowerCase().includes(q)) {
          results.push({
            type: "airport",
            icon: "fa-plane-departure",
            color: "#ffd54f",
            name: ap.name,
            detail: icao,
            lat: ap.lat,
            lng: ap.lng,
            alt: 200000,
          })
        }
      }
    }

    // ── Generic array-based sources ──
    for (const source of SEARCH_SOURCES) {
      if (results.length >= MAX) break
      const data = source.getData(this)
      for (const item of data) {
        if (results.length >= MAX) break
        const fieldValues = source.fields(item)
        const matches = fieldValues.some(f => (f || "").toLowerCase().includes(q))
        if (matches) {
          const result = source.toResult(item, this)
          results.push({
            type: source.key,
            icon: result.icon || source.icon,
            color: result.color || source.color,
            ...result,
          })
        }
      }
    }

    this._renderSearchResults(results, query)
  }

  GlobeController.prototype._satSearchResult = function(s) {
    const sat = window.satellite
    let lat = 0, lng = 0, alt = 500000
    if (sat && s.tle_line1 && s.tle_line2) {
      try {
        const now = new Date()
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (posVel.position) {
          const gmst = sat.gstime(now)
          const posGd = sat.eciToGeodetic(posVel.position, gmst)
          lng = sat.degreesLong(posGd.longitude)
          lat = sat.degreesLat(posGd.latitude)
          alt = posGd.height * 1000 + 500000
        }
      } catch { /* skip */ }
    }
    return {
      type: "satellite",
      icon: "fa-satellite",
      color: this.satCategoryColors?.[s.category] || "#ab47bc",
      name: s.name,
      detail: s.category + (s.country_owner ? ` · ${s.country_owner}` : ""),
      lat, lng, alt,
      data: s,
    }
  }

  GlobeController.prototype._renderSearchResults = function(results, query) {
    if (results.length === 0) {
      this.searchResultsTarget.innerHTML = '<div class="search-empty">No results</div>'
      this.searchResultsTarget.style.display = "block"
      return
    }

    const html = results.map((r, i) => `
      <div class="search-result-row" data-action="click->globe#searchResultClick" data-idx="${i}">
        <span class="search-result-icon" style="color: ${r.color}"><i class="fa-solid ${r.icon}"></i></span>
        <span class="search-result-name">${r.name}</span>
        <span class="search-result-detail">${r.detail}</span>
      </div>
    `).join("")

    this.searchResultsTarget.innerHTML = html
    this.searchResultsTarget.style.display = "block"
    this._searchResults = results
    this._searchHighlight = 0
    this._highlightSearchRow(this.searchResultsTarget.querySelectorAll(".search-result-row"))
  }

  GlobeController.prototype.searchResultClick = function(event) {
    const idx = parseInt(event.currentTarget.dataset.idx)
    this._activateSearchResult(idx)
  }

  GlobeController.prototype._activateSearchResult = function(idx) {
    const r = this._searchResults?.[idx]
    if (!r) return

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(r.lng, r.lat, r.alt),
      duration: 1.5,
    })

    // Open detail panel for the entity
    if (r.type === "flight" && r.id) {
      this.toggleFlightSelection(r.id)
      const f = this.flightData.get(r.id)
      if (f) this.showDetail(r.id, f)
    } else if (r.type === "earthquake" && r.data) {
      this.showEarthquakeDetail(r.data)
    } else if (r.type === "power_plant" && r.data) {
      this.showPowerPlantDetail(r.data)
    } else if (r.type === "conflict" && r.data) {
      this.showConflictDetail(r.data)
    } else if (r.type === "fire_hotspot" && r.data) {
      this.showFireHotspotDetail(r.data)
    } else if (r.type === "satellite" && r.data) {
      this.showSatelliteDetail(r.data)
    }

    this.clearSearch()
  }

  Object.defineProperty(GlobeController.prototype, "airlineNames", {
    configurable: true,
    get: function() {
      return {
        AAL: "American", AAR: "Asiana", ACA: "Air Canada", AFR: "Air France",
        AIC: "Air India", ALK: "SriLankan", ANA: "All Nippon", ANZ: "Air NZ",
        AUA: "Austrian", AZA: "Alitalia/ITA", BAW: "British Airways",
        BEL: "Brussels", CAL: "China Airlines", CCA: "Air China",
        CES: "China Eastern", CPA: "Cathay Pacific", CSN: "China Southern",
        DAL: "Delta", DLH: "Lufthansa", EIN: "Aer Lingus", ELY: "El Al",
        ETD: "Etihad", ETH: "Ethiopian", EVA: "EVA Air", EWG: "Eurowings",
        EZY: "easyJet", FDX: "FedEx", FIN: "Finnair", GAF: "German AF",
        GIA: "Garuda", HAL: "Hawaiian", IBE: "Iberia", ICE: "Icelandair",
        JAL: "Japan Airlines", JBU: "JetBlue", KAL: "Korean Air",
        KLM: "KLM", LAN: "LATAM", LOT: "LOT Polish", MAS: "Malaysia",
        MEA: "Middle East", MSR: "EgyptAir", NAX: "Norwegian", OMA: "Oman Air",
        PAL: "Philippine", PIA: "PIA", QFA: "Qantas", QTR: "Qatar",
        RAM: "Royal Air Maroc", RJA: "Royal Jordanian", ROT: "TAROM",
        RYR: "Ryanair", SAS: "SAS", SAA: "South African", SIA: "Singapore",
        SKW: "SkyWest", SLK: "Silk Air", SQC: "SQ Cargo", SVA: "Saudia",
        SWA: "Southwest", SWR: "Swiss", TAP: "TAP Portugal", THA: "Thai",
        THY: "Turkish", TUI: "TUI", UAE: "Emirates", UAL: "United",
        UPS: "UPS", VIR: "Virgin Atlantic", VOZ: "Virgin Aus",
        VJC: "VietJet", WZZ: "Wizz Air", AEE: "Aegean",
        ENY: "Envoy Air", RPA: "Republic", ASA: "Alaska",
        NKS: "Spirit", AAY: "Allegiant", FFT: "Frontier",
        AXM: "AirAsia", SBI: "S7 Airlines", AFL: "Aeroflot",
        CSZ: "Shenzhen", CQH: "Spring Airlines", HVN: "Vietnam Airlines",
        AMX: "Aeromexico", AVA: "Avianca", GOL: "Gol", AZU: "Azul",
        CMP: "Copa", TOM: "TUI Airways", SXS: "SunExpress",
        PGT: "Pegasus", OAL: "Olympic", TAR: "Tunisair",
      }
    },
  })

  GlobeController.prototype._extractAirlineCode = function(callsign) {
    if (!callsign || callsign.length < 3) return null
    const code = callsign.substring(0, 3).toUpperCase()
    // Must be all letters (ICAO airline codes are 3 alpha chars)
    if (/^[A-Z]{3}$/.test(code)) return code
    return null
  }

  GlobeController.prototype._getAirlineName = function(code) {
    return this.airlineNames[code] || code
  }

  GlobeController.prototype._detectAirlines = function() {
    const counts = new Map()
    for (const [, f] of this.flightData) {
      const code = this._extractAirlineCode(f.callsign)
      if (code) {
        counts.set(code, (counts.get(code) || 0) + 1)
      }
    }
    this._detectedAirlines = counts
    this._updateAirlineChips()
  }

  GlobeController.prototype._updateAirlineChips = function() {
    // Sort by count descending, show top 20
    const sorted = [...this._detectedAirlines.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 20)

    if (sorted.length === 0) {
      if (this.hasAirlineFilterTarget) this.airlineFilterTarget.style.display = "none"
      if (this.hasEntityAirlineBarTarget) this.entityAirlineBarTarget.style.display = "none"
      return
    }

    const html = sorted.map(([code, count]) => {
      const active = this._airlineFilter.has(code) ? " active" : ""
      const name = this._getAirlineName(code)
      return `<span class="airline-chip${active}" data-action="click->globe#toggleAirlineFilter" data-code="${code}" title="${name}">
        ${code}<span class="airline-chip-count">${count}</span>
      </span>`
    }).join("")

    // Update sidebar chips
    if (this.hasAirlineFilterTarget && this.hasAirlineChipsTarget) {
      this.airlineFilterTarget.style.display = this.flightsVisible ? "" : "none"
      this.airlineChipsTarget.innerHTML = html
    }

    // Update entity list chips
    if (this.hasEntityAirlineBarTarget && this.hasEntityAirlineChipsTarget) {
      const entityListVisible = this.entityListPanelTarget.classList.contains("rp-pane--active")
      const activeTab = this.entityListPanelTarget.querySelector(".entity-tab.active")?.dataset.tab
      this.entityAirlineBarTarget.style.display = (entityListVisible && activeTab === "flights") ? "" : "none"
      this.entityAirlineChipsTarget.innerHTML = html
    }
  }

  GlobeController.prototype.toggleAirlineFilter = function(event) {
    const code = event.currentTarget.dataset.code
    if (this._airlineFilter.has(code)) {
      this._airlineFilter.delete(code)
    } else {
      this._airlineFilter.add(code)
    }
    this._updateAirlineChips()
    // Refresh entity list flights tab if visible
    if (this.entityListPanelTarget.classList.contains("rp-pane--active")) {
      this.renderEntityTab("flights")
    }
    this._savePrefs()
  }

  GlobeController.prototype._flightPassesAirlineFilter = function(f) {
    if (this._airlineFilter.size === 0) return true
    const code = this._extractAirlineCode(f.callsign)
    return code && this._airlineFilter.has(code)
  }

  // ── Sidebar & Section Controls ──────────────────────────────

}
