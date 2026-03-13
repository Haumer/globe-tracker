export function applyUiMethods(GlobeController) {
  GlobeController.prototype._isMobile = function() {
    return window.matchMedia("(max-width: 768px)").matches
  }

  GlobeController.prototype.toggleSidebar = function() {
    if (this._isMobile()) {
      // Bottom sheet: cycle collapsed → peek → expanded → collapsed
      const sb = this.sidebarTarget
      if (sb.classList.contains("mobile-expanded")) {
        sb.classList.remove("mobile-expanded", "mobile-peek")
        // collapsed (default transform kicks in)
      } else if (sb.classList.contains("mobile-peek")) {
        sb.classList.remove("mobile-peek")
        sb.classList.add("mobile-expanded")
      } else {
        sb.classList.add("mobile-peek")
      }
    } else {
      this.sidebarTarget.classList.toggle("collapsed")
    }
    this._savePrefs()
  }

  GlobeController.prototype.toggleSection = function(event) {
    // Support keyboard activation (Enter/Space)
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return
    if (event.key === " ") event.preventDefault()

    const head = event.currentTarget
    head.classList.toggle("open")
    head.setAttribute("aria-expanded", String(head.classList.contains("open")))
    this._savePrefs()
  }

  // ── Quick Layer Bar ─────────────────────────────────────────

  GlobeController.prototype.quickToggle = function(event) {
    const layer = event.currentTarget.dataset.layer
    const map = {
      flights:     { target: "flightsToggle",       method: "toggleFlights" },
      satellites:  null, // handled by opening the section
      ships:       { target: "shipsToggle",          method: "toggleShips" },
      cities:      { target: "citiesToggle",         method: "toggleCities" },
      airports:    { target: "airportsToggle",       method: "toggleAirports" },
      borders:     { target: "bordersToggle",        method: "toggleBorders" },
      terrain:     { target: "terrainToggle",        method: "toggleTerrain" },
      earthquakes: { target: "earthquakesToggle",    method: "toggleEarthquakes" },
      events:      { target: "naturalEventsToggle",  method: "toggleNaturalEvents" },
      cameras:     { target: "camerasToggle",        method: "toggleCameras" },
      gpsJamming:  { target: "gpsJammingToggle",    method: "toggleGpsJamming" },
      news:        { target: "newsToggle",          method: "toggleNews" },
      cables:      { target: "cablesToggle",        method: "toggleCables" },
      pipelines:   { target: "pipelinesToggle",    method: "togglePipelines" },
      railways:    { target: "railwaysToggle",     method: "toggleRailways" },
      outages:     { target: "outagesToggle",       method: "toggleOutages" },
      powerPlants: { target: "powerPlantsToggle",  method: "togglePowerPlants" },
      conflicts:   { target: "conflictsToggle",    method: "toggleConflicts" },
      traffic:     { target: "trafficToggle",      method: "toggleTraffic" },
      notams:      { target: "notamsToggle",        method: "toggleNotams" },
      fireHotspots: { target: "fireHotspotsToggle", method: "toggleFireHotspots" },
      weather:      { target: "weatherToggle",      method: "toggleWeather" },
      trains:       { target: "trainsToggle",       method: "toggleTrains" },
      financial:    { target: "financialToggle",   method: "toggleFinancial" },
    }

    if (layer === "satellites") {
      const anySat = Object.values(this.satCategoryVisible).some(v => v)
      const defaults = ["stations", "gps-ops", "weather", "military"]
      if (anySat) {
        // Turn all off
        for (const cat of Object.keys(this.satCategoryVisible)) {
          if (this.satCategoryVisible[cat]) {
            const ev = { target: { dataset: { category: cat }, checked: false } }
            this.toggleSatCategory(ev)
          }
        }
      } else {
        // Turn defaults on
        for (const cat of defaults) {
          const ev = { target: { dataset: { category: cat }, checked: true } }
          this.toggleSatCategory(ev)
        }
      }
      // Sync chip UI
      this.element.querySelectorAll(".sb-chip[data-category]").forEach(chip => {
        const cat = chip.dataset.category
        chip.classList.toggle("active", this.satCategoryVisible[cat])
        chip.setAttribute("aria-pressed", String(this.satCategoryVisible[cat]))
      })
      this._syncQuickBar()
      this._updateSatBadge()
      return
    }

    const cfg = map[layer]
    if (!cfg) return

    const targetName = cfg.target + "Target"
    const hasTarget = "has" + cfg.target.charAt(0).toUpperCase() + cfg.target.slice(1) + "Target"

    if (this[hasTarget]) {
      this[targetName].checked = !this[targetName].checked
    }
    this[cfg.method]()
    this._syncQuickBar()
  }

  GlobeController.prototype.toggleRightPanel = function() {
    if (!this.hasRightPanelTarget) return
    const visible = this.rightPanelTarget.style.display !== "none"
    if (visible) {
      this.closeRightPanel()
    } else {
      this._showRightPanel("entities")
    }
  }

  GlobeController.prototype.toggleSatChip = function(event) {
    const btn = event.currentTarget
    const category = btn.dataset.category
    // Fire the existing toggleSatCategory with a synthetic event
    const syntheticEvent = { target: { dataset: { category }, checked: !this.satCategoryVisible[category] } }
    syntheticEvent.target.checked = !this.satCategoryVisible[category]
    this.toggleSatCategory(syntheticEvent)
    btn.classList.toggle("active", this.satCategoryVisible[category])
    btn.setAttribute("aria-pressed", String(this.satCategoryVisible[category]))
    this._syncQuickBar()
    this._updateSatBadge()
  }

  GlobeController.prototype._syncQuickBar = function() {
    const sync = (targetName, active) => {
      const has = "has" + targetName.charAt(0).toUpperCase() + targetName.slice(1) + "Target"
      if (this[has]) {
        this[targetName + "Target"].classList.toggle("active", active)
        this[targetName + "Target"].setAttribute("aria-pressed", String(active))
      }
    }

    sync("qlFlights", this.flightsVisible)
    sync("qlShips", this.shipsVisible)
    sync("qlCities", this.citiesVisible)
    sync("qlAirports", this.airportsVisible)
    sync("qlBorders", this.bordersVisible)
    sync("qlTerrain", this.terrainEnabled)
    sync("qlEarthquakes", this.earthquakesVisible)
    sync("qlEvents", this.naturalEventsVisible)
    sync("qlCameras", this.camerasVisible)
    sync("qlGpsJamming", this.gpsJammingVisible)
    sync("qlNews", this.newsVisible)
    sync("qlCables", this.cablesVisible)
    sync("qlPipelines", this.pipelinesVisible)
    sync("qlRailways", this.railwaysVisible)
    sync("qlTrains", this.trainsVisible)
    sync("qlOutages", this.outagesVisible)
    sync("qlPowerPlants", this.powerPlantsVisible)
    sync("qlConflicts", this.conflictsVisible)
    sync("qlTraffic", this.trafficVisible)
    sync("qlNotams", this.notamsVisible)
    sync("qlFireHotspots", this.fireHotspotsVisible)
    sync("qlWeather", this.weatherVisible)
    sync("qlFinancial", this.financialVisible)

    const anySat = Object.values(this.satCategoryVisible).some(v => v)
    sync("qlSatellites", anySat)

    // Show/hide flight sub-options
    if (this.hasFlightSubOptionsTarget) {
      this.flightSubOptionsTarget.style.display = this.flightsVisible ? "" : "none"
    }

    // Show/hide weather panel
    if (this._weatherPanelBuilt) this._showWeatherPanel(this.weatherVisible)

    // Update section active counts
    this._updateSectionCounts()
    this._renderActiveLayerPills()
    this._updateSidebarBadge()
  }

  GlobeController.prototype._updateSectionCounts = function() {
    const sections = {
      tracking: [this.flightsVisible, this.shipsVisible, Object.values(this.satCategoryVisible).some(v => v), this.notamsVisible, this.trainsVisible],
      events: [this.earthquakesVisible, this.naturalEventsVisible, this.fireHotspotsVisible, this.weatherVisible, this.conflictsVisible, this.newsVisible],
      infrastructure: [this.cablesVisible, this.pipelinesVisible, this.railwaysVisible, this.powerPlantsVisible, this.camerasVisible, this.financialVisible],
      cyber: [this.trafficVisible, this.outagesVisible, this.gpsJammingVisible],
    }
    for (const [key, flags] of Object.entries(sections)) {
      const count = flags.filter(Boolean).length
      const el = document.getElementById("sec-count-" + key)
      if (el) el.textContent = count > 0 ? count + " on" : ""
    }
  }

  GlobeController.prototype._updateSidebarBadge = function() {
    const badge = document.getElementById("sidebar-layer-badge")
    if (!badge) return
    const count = [
      this.flightsVisible, this.shipsVisible, this.citiesVisible,
      this.airportsVisible, this.bordersVisible, this.terrainEnabled,
      this.earthquakesVisible, this.naturalEventsVisible, this.camerasVisible,
      this.gpsJammingVisible, this.newsVisible, this.cablesVisible,
      this.pipelinesVisible, this.railwaysVisible, this.trainsVisible, this.outagesVisible, this.powerPlantsVisible,
      this.conflictsVisible, this.trafficVisible, this.notamsVisible,
      this.fireHotspotsVisible, this.weatherVisible, this.financialVisible,
      Object.values(this.satCategoryVisible).some(v => v)
    ].filter(Boolean).length
    badge.textContent = count
    badge.style.display = count > 0 ? "" : "none"
  }

  GlobeController.prototype._renderActiveLayerPills = function() {
    if (!this.hasActiveLayerPillsTarget) return

    const layers = [
      { key: "flights",      active: this.flightsVisible,       color: "#4fc3f7", label: "FLT" },
      { key: "ships",        active: this.shipsVisible,         color: "#26c6da", label: "AIS" },
      { key: "satellites",   active: Object.values(this.satCategoryVisible).some(v => v), color: "#ab47bc", label: "SAT" },
      { key: "earthquakes",  active: this.earthquakesVisible,   color: "#ff5252", label: "EQ" },
      { key: "events",       active: this.naturalEventsVisible, color: "#ff9800", label: "EVT" },
      { key: "fires",        active: this.fireHotspotsVisible,  color: "#ff6d00", label: "FIRE" },
      { key: "weather",      active: this.weatherVisible,       color: "#64b5f6", label: "WX" },
      { key: "conflicts",    active: this.conflictsVisible,     color: "#ef5350", label: "WAR" },
      { key: "cables",       active: this.cablesVisible,        color: "#00bcd4", label: "CBL" },
      { key: "pipelines",    active: this.pipelinesVisible,     color: "#ff6d00", label: "PIPE" },
      { key: "railways",     active: this.railwaysVisible,      color: "#90a4ae", label: "RAIL" },
      { key: "trains",      active: this.trainsVisible,        color: "#e53935", label: "TRAIN" },
      { key: "outages",      active: this.outagesVisible,       color: "#e040fb", label: "OUT" },
      { key: "powerPlants",  active: this.powerPlantsVisible,   color: "#ffc107", label: "PWR" },
      { key: "gpsJamming",   active: this.gpsJammingVisible,    color: "#ff1744", label: "GPS" },
      { key: "traffic",      active: this.trafficVisible,       color: "#69f0ae", label: "NET" },
      { key: "notams",       active: this.notamsVisible,        color: "#ffab40", label: "NOTAM" },
      { key: "cameras",      active: this.camerasVisible,       color: "#29b6f6", label: "CAM" },
      { key: "news",         active: this.newsVisible,          color: "#7c4dff", label: "NEWS" },
      { key: "financial",    active: this.financialVisible,     color: "#66bb6a", label: "MKT" },
      { key: "cities",       active: this.citiesVisible,        color: "#ffd54f", label: "CITY" },
      { key: "airports",     active: this.airportsVisible,      color: "#81d4fa", label: "APT" },
      { key: "borders",      active: this.bordersVisible,       color: "#ffd54f", label: "BDR" },
    ]

    const active = layers.filter(l => l.active)
    if (active.length === 0) {
      this.activeLayerPillsTarget.innerHTML = '<span class="bs-no-layers">No layers active</span>'
      return
    }

    this.activeLayerPillsTarget.innerHTML = active.map(l =>
      `<span class="bs-pill" style="--pill-color: ${l.color};">${l.label}</span>`
    ).join("")
  }

  GlobeController.prototype._updateSatBadge = function() {
    if (!this.hasSatBadgeTarget) return
    const count = Object.values(this.satCategoryVisible).filter(v => v).length
    if (count > 0) {
      this.satBadgeTarget.textContent = count
      this.satBadgeTarget.style.display = ""
    } else {
      this.satBadgeTarget.style.display = "none"
    }
  }

  // ── Stats Bar ───────────────────────────────────────────────

  GlobeController.prototype._updateStats = function() {
    const elFlt = document.getElementById("stat-flights")
    if (elFlt) {
      elFlt.textContent = this.flightData.size.toLocaleString()
      if (this.flightsVisible && this.flightData.size > 0) this._markFresh("flights")
    }
    const elSat = document.getElementById("stat-sats")
    if (elSat) {
      elSat.textContent = this.satelliteEntities.size.toLocaleString()
    }
    const elShip = document.getElementById("stat-ships")
    if (elShip) {
      elShip.textContent = this.shipData.size.toLocaleString()
      if (this.shipsVisible && this.shipData.size > 0) this._markFresh("ships")
    }
    const elEvt = document.getElementById("stat-events")
    if (elEvt) {
      const count = (this.earthquakesVisible ? this._earthquakeData.length : 0) +
                    (this.naturalEventsVisible ? this._naturalEventData.length : 0) +
                    (this.camerasVisible ? this._webcamData.length : 0) +
                    (this.powerPlantsVisible ? this._powerPlantData.length : 0) +
                    (this.conflictsVisible ? this._conflictData.length : 0) +
                    (this.fireHotspotsVisible ? this._fireHotspotData.length : 0)
      elEvt.textContent = count.toLocaleString()
      if (this.earthquakesVisible && this._earthquakeData.length > 0) this._markFresh("earthquakes")
      if (this.naturalEventsVisible && this._naturalEventData.length > 0) this._markFresh("naturalEvents")
      if (this.camerasVisible && this._webcamData.length > 0) this._markFresh("cameras")
      if (this.conflictsVisible && this._conflictData.length > 0) this._markFresh("conflicts")
    }

    // Keep quick bar and badges in sync
    this._syncQuickBar()
    this._updateSatBadge()
  }

  GlobeController.prototype._updateClock = function() {
    const elClk = document.getElementById("stat-clock")
    if (elClk) {
      const now = new Date()
      elClk.textContent = now.toUTCString().slice(17, 22)
    }
  }

  // ── JS Tooltips ────────────────────────────────────────────

  GlobeController.prototype._initTooltips = function() {
    const tip = document.getElementById("gt-tooltip")
    if (!tip) return
    this._tipEl = tip

    const GAP = 8
    let currentEl = null

    const show = (e) => {
      const t = e.target
      if (!t || !t.closest) return
      const el = t.closest("[data-tip]")
      if (!el || el === currentEl) return
      currentEl = el
      const text = el.getAttribute("data-tip")
      if (!text) return

      // Set content and measure off-screen first
      tip.textContent = text
      tip.style.left = "-9999px"
      tip.style.top = "-9999px"
      tip.style.opacity = "1"
      tip.style.display = "block"

      // Force layout so offsetWidth/Height are correct
      const tipW = tip.offsetWidth
      const tipH = tip.offsetHeight

      const pos = el.getAttribute("data-tip-pos") || "above"
      const rect = el.getBoundingClientRect()

      let left, top
      if (pos === "right") {
        left = rect.right + GAP
        top = rect.top + rect.height / 2 - tipH / 2
      } else if (pos === "below") {
        left = rect.left + rect.width / 2 - tipW / 2
        top = rect.bottom + GAP
      } else {
        left = rect.left + rect.width / 2 - tipW / 2
        top = rect.top - tipH - GAP
      }

      // Keep on screen
      if (left < 4) left = 4
      if (left + tipW > window.innerWidth - 4) left = window.innerWidth - tipW - 4
      if (top < 4) top = 4

      tip.style.left = left + "px"
      tip.style.top = top + "px"
    }

    const hide = (e) => {
      const t = e.target
      const el = t && t.closest ? t.closest("[data-tip]") : null
      if (el === currentEl) {
        tip.style.opacity = "0"
        currentEl = null
      }
    }

    // Use capture phase to catch events before they're consumed
    document.addEventListener("pointerenter", show, true)
    document.addEventListener("pointerleave", hide, true)
    // Fallback for mouse
    document.addEventListener("mouseover", show)
    document.addEventListener("mouseout", hide)
  }

  // ── Preferences Save/Restore ────────────────────────────────

  GlobeController.prototype._savePrefs = function() {
    if (!this.signedInValue || !this.viewer) return
    clearTimeout(this._savePrefsDebounce)
    this._savePrefsDebounce = setTimeout(() => this._doSavePrefs(), 2000)
  }

  GlobeController.prototype._doSavePrefs = function() {
    const Cesium = window.Cesium
    if (!Cesium || !this.viewer || !this.viewer.camera) return

    let carto
    try { carto = this.viewer.camera.positionCartographic } catch { return }
    const layers = {
      flights: this.flightsVisible,
      trails: this.trailsVisible,
      ships: this.shipsVisible,
      borders: this.bordersVisible,
      cities: this.citiesVisible,
      airports: this.airportsVisible,
      satOrbits: this.satOrbitsVisible,
      satHeatmap: this.satHeatmapVisible,
      buildHeatmap: this._buildHeatmapActive,
      earthquakes: this.earthquakesVisible,
      naturalEvents: this.naturalEventsVisible,
      cameras: this.camerasVisible,
      gpsJamming: this.gpsJammingVisible,
      news: this.newsVisible,
      cables: this.cablesVisible,
      pipelines: this.pipelinesVisible,
      railways: this.railwaysVisible,
      trains: this.trainsVisible,
      outages: this.outagesVisible,
      powerPlants: this.powerPlantsVisible,
      conflicts: this.conflictsVisible,
      traffic: this.trafficVisible,
      notams: this.notamsVisible,
      fireHotspots: this.fireHotspotsVisible,
      weather: this.weatherVisible,
      financial: this.financialVisible,
      weatherLayers: this._weatherActiveLayers ? { ...this._weatherActiveLayers } : {},
      weatherOpacity: this._weatherOpacity || 0.6,
      terrain: this.terrainEnabled || false,
      terrainExaggeration: this.viewer?.scene?.verticalExaggeration || 1,
      buildings: this.hasBuildingsSelectTarget ? this.buildingsSelectTarget.value : "off",
      showCivilian: this.showCivilian,
      showMilitary: this.showMilitary,
      satCategories: { ...this.satCategoryVisible },
    }

    const openSections = []
    this.element.querySelectorAll(".sb-section-head.open").forEach(el => {
      const section = el.closest(".sb-section")?.dataset.section
      if (section) openSections.push(section)
    })

    const prefs = {
      camera_lat: Cesium.Math.toDegrees(carto.latitude),
      camera_lng: Cesium.Math.toDegrees(carto.longitude),
      camera_height: carto.height,
      camera_heading: this.viewer.camera.heading,
      camera_pitch: this.viewer.camera.pitch,
      sidebar_collapsed: this.hasSidebarTarget && this.sidebarTarget.classList.contains("collapsed"),
      right_panel_closed: !!this._rightPanelUserClosed,
      layers,
      selected_countries: [...this.selectedCountries],
      airline_filter: [...this._airlineFilter],
      open_sections: openSections,
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    fetch("/api/preferences", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
      },
      body: JSON.stringify(prefs),
    }).catch(() => {})
  }

  GlobeController.prototype._restorePrefs = function() {
    const prefs = this.savedPrefsValue
    if (!prefs || Object.keys(prefs).length === 0) return

    this._restoredPrefs = prefs
  }

  GlobeController.prototype._applyRestoredPrefs = function() {
    const prefs = this._restoredPrefs
    if (!prefs) return
    this._restoredPrefs = null

    const Cesium = window.Cesium

    // Camera
    if (prefs.camera_lat != null && prefs.camera_lng != null) {
      this.viewer.camera.setView({
        destination: Cesium.Cartesian3.fromDegrees(
          prefs.camera_lng, prefs.camera_lat, prefs.camera_height || 20000000
        ),
        orientation: {
          heading: prefs.camera_heading || 0,
          pitch: prefs.camera_pitch || -Cesium.Math.PI_OVER_TWO,
          roll: 0,
        },
      })
    }

    // Sidebar
    if (prefs.sidebar_collapsed && this.hasSidebarTarget) {
      this.sidebarTarget.classList.add("collapsed")
    }

    // Right panel
    if (prefs.right_panel_closed) {
      this._rightPanelUserClosed = true
    }

    // Open sections
    if (prefs.open_sections && Array.isArray(prefs.open_sections)) {
      prefs.open_sections.forEach(name => {
        const section = this.element.querySelector(`.sb-section[data-section="${name}"] .sb-section-head`)
        if (section) section.classList.add("open")
      })
    }

    // Layers
    if (prefs.layers) {
      const l = prefs.layers

      if (l.flights && this.hasFlightsToggleTarget) {
        this.flightsToggleTarget.checked = true
        this.toggleFlights()
      }
      if (l.trails && this.hasTrailsToggleTarget) {
        this.trailsToggleTarget.checked = true
        this.toggleTrails()
      }
      if (l.ships && this.hasShipsToggleTarget) {
        this.shipsToggleTarget.checked = true
        this.toggleShips()
      }
      if (l.borders && this.hasBordersToggleTarget) {
        this.bordersToggleTarget.checked = true
        this.toggleBorders()
      }
      if (l.cities && this.hasCitiesToggleTarget) {
        this.citiesToggleTarget.checked = true
        this.toggleCities()
      }
      if (l.airports && this.hasAirportsToggleTarget) {
        this.airportsToggleTarget.checked = true
        this.toggleAirports()
      }
      if (l.satOrbits && this.hasSatOrbitsToggleTarget) {
        this.satOrbitsToggleTarget.checked = true
        this.toggleSatOrbits()
      }
      if (l.satHeatmap && this.hasSatHeatmapToggleTarget) {
        this.satHeatmapToggleTarget.checked = true
        this.toggleSatHeatmap()
      }
      if (l.buildHeatmap && this.hasBuildHeatmapToggleTarget) {
        this.buildHeatmapToggleTarget.checked = true
        // Defer until countries are loaded
        this._pendingBuildHeatmap = true
      }
      if (l.earthquakes && this.hasEarthquakesToggleTarget) {
        this.earthquakesToggleTarget.checked = true
        this.toggleEarthquakes()
      }
      if (l.naturalEvents && this.hasNaturalEventsToggleTarget) {
        this.naturalEventsToggleTarget.checked = true
        this.toggleNaturalEvents()
      }
      if (l.cameras && this.hasCamerasToggleTarget) {
        this.camerasToggleTarget.checked = true
        this.toggleCameras()
      }
      if (l.gpsJamming && this.hasGpsJammingToggleTarget) {
        this.gpsJammingToggleTarget.checked = true
        this.toggleGpsJamming()
      }
      if (l.news && this.hasNewsToggleTarget) {
        this.newsToggleTarget.checked = true
        this.toggleNews()
      }
      if (l.cables && this.hasCablesToggleTarget) {
        this.cablesToggleTarget.checked = true
        this.toggleCables()
      }
      if (l.pipelines && this.hasPipelinesToggleTarget) {
        this.pipelinesToggleTarget.checked = true
        this.togglePipelines()
      }
      if (l.railways && this.hasRailwaysToggleTarget) {
        this.railwaysToggleTarget.checked = true
        this.toggleRailways()
      }
      if (l.trains && this.hasTrainsToggleTarget) {
        this.trainsToggleTarget.checked = true
        this.toggleTrains()
      }
      if (l.outages && this.hasOutagesToggleTarget) {
        this.outagesToggleTarget.checked = true
        this.toggleOutages()
      }
      if (l.powerPlants && this.hasPowerPlantsToggleTarget) {
        this.powerPlantsToggleTarget.checked = true
        this.togglePowerPlants()
      }
      if (l.conflicts && this.hasConflictsToggleTarget) {
        this.conflictsToggleTarget.checked = true
        this.toggleConflicts()
      }
      if (l.traffic && this.hasTrafficToggleTarget) {
        this.trafficToggleTarget.checked = true
        this.toggleTraffic()
      }
      if (l.notams && this.hasNotamsToggleTarget) {
        this.notamsToggleTarget.checked = true
        this.toggleNotams()
      }
      if (l.fireHotspots && this.hasFireHotspotsToggleTarget) {
        this.fireHotspotsToggleTarget.checked = true
        this.toggleFireHotspots()
      }
      if (l.weather && this.hasWeatherToggleTarget) {
        this._weatherOpacity = l.weatherOpacity || 0.6
        this.weatherToggleTarget.checked = true
        this._weatherActiveLayers = {}
        this.toggleWeather()
        // Restore specific sublayers
        if (l.weatherLayers && typeof l.weatherLayers === "object") {
          // Remove auto-enabled precipitation first
          this._removeAllWeatherLayers()
          for (const [key, active] of Object.entries(l.weatherLayers)) {
            if (active) this.toggleWeatherSublayer(key)
          }
        }
      }
      if (l.financial && this.hasFinancialToggleTarget) {
        this.financialToggleTarget.checked = true
        this.toggleFinancial()
      }
      if (l.terrain && this.hasTerrainToggleTarget) {
        this.terrainToggleTarget.checked = true
        this.toggleTerrain()
      }
      if (l.terrainExaggeration && l.terrainExaggeration > 1 && this.hasTerrainExaggerationTarget) {
        this.terrainExaggerationTarget.value = l.terrainExaggeration
        this.setTerrainExaggeration()
      }
      if (l.buildings && l.buildings !== "off" && this.hasBuildingsSelectTarget) {
        this.buildingsSelectTarget.value = l.buildings
        this.toggleBuildings()
      }
      // Civilian/military filter (default both on)
      if (l.showCivilian === false && this.hasCivilianToggleTarget) {
        this.civilianToggleTarget.checked = false
        this.showCivilian = false
      }
      if (l.showMilitary === false && this.hasMilitaryToggleTarget) {
        this.militaryToggleTarget.checked = false
        this.showMilitary = false
      }

      // Satellite categories
      if (l.satCategories) {
        for (const [cat, visible] of Object.entries(l.satCategories)) {
          if (!visible) continue
          this.satCategoryVisible[cat] = true
          // Activate the chip button
          const chip = this.element.querySelector(`.sb-chip[data-category="${cat}"]`)
          if (chip) chip.classList.add("active")
          if (!this._loadedSatCategories.has(cat)) {
            this.fetchSatCategory(cat)
          }
        }
      }
    }

    // Selected countries (restore after borders load)
    if (prefs.selected_countries && prefs.selected_countries.length > 0) {
      this._pendingCountryRestore = prefs.selected_countries
    }

    // Airline filter
    if (prefs.airline_filter && prefs.airline_filter.length > 0) {
      this._airlineFilter = new Set(prefs.airline_filter)
    }

    // Sync quick bar and badges after restore
    this._syncQuickBar()
    this._updateSatBadge()

    // Mobile: start sidebar in peek mode so quick bar is visible
    if (this._isMobile()) {
      this.sidebarTarget.classList.remove("collapsed")
      this.sidebarTarget.classList.add("mobile-peek")
    }
  }

}
