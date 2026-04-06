import { isLayerTemporarilyDisabled } from "globe/controller/ui/registry"

export function applyUiPreferenceMethods(GlobeController) {
  GlobeController.prototype._savePrefs = function() {
    if (!this.signedInValue || !this.viewer) return
    clearTimeout(this._savePrefsDebounce)
    this._savePrefsDebounce = setTimeout(() => this._doSavePrefs(), 2000)
  }

  GlobeController.prototype._doSavePrefs = function() {
    const Cesium = window.Cesium
    if (!Cesium || !this.viewer?.camera) return

    let carto
    try {
      carto = this.viewer.camera.positionCartographic
    } catch {
      return
    }

    const prefs = {
      camera_lat: Cesium.Math.toDegrees(carto.latitude),
      camera_lng: Cesium.Math.toDegrees(carto.longitude),
      camera_height: carto.height,
      camera_heading: this.viewer.camera.heading,
      camera_pitch: this.viewer.camera.pitch,
      sidebar_collapsed: this.hasSidebarTarget && this.sidebarTarget.classList.contains("collapsed"),
      right_panel_closed: !!this._rightPanelUserClosed,
      layers: buildLayerPrefs.call(this),
      selected_countries: [...this.selectedCountries],
      airline_filter: [...this._airlineFilter],
      open_sections: openSectionsFor(this.element),
      active_region: this._activeRegion?.key || null,
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

    restoreCamera.call(this, prefs)
    restoreChromeState.call(this, prefs)
    applyLayerPrefs.call(this, prefs.layers)
    restoreSelections.call(this, prefs)

    this._syncQuickBar()
    this._updateSatBadge()

    if (this._isMobile()) {
      this.sidebarTarget.classList.remove("collapsed")
      this.sidebarTarget.classList.add("mobile-peek")
    }
  }

  GlobeController.prototype._applyDefaultPrimaryLayers = function() {
    const defaults = [
      ["situationsToggle", "toggleSituations"],
      ["newsToggle", "toggleNews"],
    ]

    defaults.forEach(([targetBase, methodName]) => {
      const hasTarget = `has${capitalize(targetBase)}Target`
      if (!this[hasTarget]) return
      const target = this[`${targetBase}Target`]
      if (target.checked) return
      target.checked = true
      this[methodName]()
    })
  }
}

function buildLayerPrefs() {
  return {
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
    ports: this.portsVisible,
    shippingLanes: this.shippingLanesVisible,
    pipelines: this.pipelinesVisible,
    railways: this.railwaysVisible,
    trains: this.trainsVisible,
    outages: this.outagesVisible,
    powerPlants: this.powerPlantsVisible,
    conflicts: this.conflictsVisible,
    situations: this.situationsVisible,
    traffic: this.trafficVisible,
    notams: this.notamsVisible,
    insights: this.insightsVisible,
    fireHotspots: this.fireHotspotsVisible,
    fireClusters: this.fireClustersVisible,
    strikeArcs: this._strikeArcsVisible,
    hexTheater: this._hexTheaterVisible,
    verifiedStrikes: this.verifiedStrikesVisible,
    heatSignatures: this.heatSignaturesVisible,
    strikes: this.strikesVisible,
    weather: this.weatherVisible,
    financial: this.financialVisible,
    chokepoints: this.chokepointsVisible,
    militaryBases: this.militaryBasesVisible,
    militaryFlights: this._milFlightsActive,
    airbases: this.airbasesVisible,
    navalVessels: this.navalVesselsVisible,
    weatherLayers: this._weatherActiveLayers ? { ...this._weatherActiveLayers } : {},
    weatherOpacity: this._weatherOpacity || 0.6,
    terrain: this.terrainEnabled || false,
    terrainExaggeration: this.viewer?.scene?.verticalExaggeration || 1,
    buildings: this.hasBuildingsSelectTarget ? this.buildingsSelectTarget.value : "off",
    showCivilian: this.showCivilian,
    showMilitary: this.showMilitary,
    satCategories: { ...this.satCategoryVisible },
  }
}

function openSectionsFor(element) {
  const openSections = []
  element.querySelectorAll(".sb-section-head.open").forEach(head => {
    const section = head.closest(".sb-section")?.dataset.section
    if (section) openSections.push(section)
  })
  return openSections
}

function restoreCamera(prefs) {
  const Cesium = window.Cesium
  if (prefs.camera_lat == null || prefs.camera_lng == null) return
  this.viewer.camera.setView({
    destination: Cesium.Cartesian3.fromDegrees(
      prefs.camera_lng,
      prefs.camera_lat,
      prefs.camera_height || 20000000
    ),
    orientation: {
      heading: prefs.camera_heading || 0,
      pitch: prefs.camera_pitch || -Cesium.Math.PI_OVER_TWO,
      roll: 0,
    },
  })
}

function restoreChromeState(prefs) {
  if (prefs.sidebar_collapsed && this.hasSidebarTarget) this.sidebarTarget.classList.add("collapsed")
  if (prefs.right_panel_closed) this._rightPanelUserClosed = true
  if (!Array.isArray(prefs.open_sections)) return

  prefs.open_sections.forEach(name => {
    const section = this.element.querySelector(`.sb-section[data-section="${name}"] .sb-section-head`)
    if (section) section.classList.add("open")
  })
}

function applyLayerPrefs(layers) {
  if (!layers) return
  const l = layers

  toggleIf.call(this, l.flights, "flightsToggle", "toggleFlights")
  toggleIf.call(this, l.trails, "trailsToggle", "toggleTrails")
  toggleIf.call(this, l.ships, "shipsToggle", "toggleShips")
  toggleIf.call(this, l.borders, "bordersToggle", "toggleBorders")
  toggleIf.call(this, l.cities, "citiesToggle", "toggleCities")
  toggleIf.call(this, l.airports, "airportsToggle", "toggleAirports")
  toggleIf.call(this, l.satOrbits, "satOrbitsToggle", "toggleSatOrbits")
  toggleIf.call(this, l.satHeatmap, "satHeatmapToggle", "toggleSatHeatmap")
  if (l.buildHeatmap && this.hasBuildHeatmapToggleTarget) {
    this.buildHeatmapToggleTarget.checked = true
    this._pendingBuildHeatmap = true
  }
  toggleIf.call(this, l.earthquakes, "earthquakesToggle", "toggleEarthquakes")
  toggleIf.call(this, l.naturalEvents, "naturalEventsToggle", "toggleNaturalEvents")
  toggleIf.call(this, l.cameras, "camerasToggle", "toggleCameras")
  toggleIf.call(this, l.gpsJamming, "gpsJammingToggle", "toggleGpsJamming")
  toggleIf.call(this, l.news, "newsToggle", "toggleNews")
  toggleIf.call(this, l.cables, "cablesToggle", "toggleCables")
  toggleIf.call(this, l.ports, "portsToggle", "togglePorts")
  toggleIf.call(this, l.shippingLanes, "shippingLanesToggle", "toggleShippingLanes")
  toggleIf.call(this, l.pipelines, "pipelinesToggle", "togglePipelines")
  toggleIf.call(this, l.railways, "railwaysToggle", "toggleRailways")
  toggleIf.call(this, l.trains, "trainsToggle", "toggleTrains")
  toggleIf.call(this, l.outages, "outagesToggle", "toggleOutages")
  toggleIf.call(this, l.powerPlants, "powerPlantsToggle", "togglePowerPlants")
  toggleIf.call(this, l.conflicts, "conflictsToggle", "toggleConflicts")

  if (this.hasStrikeArcsToggleTarget) {
    const enabled = l.strikeArcs === true
    this.strikeArcsToggleTarget.checked = enabled
    this._strikeArcsVisible = enabled
  }
  if (this.hasHexTheaterToggleTarget) {
    const enabled = l.hexTheater === true
    this.hexTheaterToggleTarget.checked = enabled
    this._hexTheaterVisible = enabled
  }

  toggleIf.call(this, l.situations, "situationsToggle", "toggleSituations")
  toggleIf.call(this, l.traffic, "trafficToggle", "toggleTraffic")
  toggleIf.call(this, l.notams, "notamsToggle", "toggleNotams")
  toggleIf.call(this, l.insights, "insightsToggle", "toggleInsights")
  toggleIf.call(this, l.fireHotspots, "fireHotspotsToggle", "toggleFireHotspots")

  if (this.hasFireClustersToggleTarget) {
    const fireClustersEnabled = l.fireClusters !== false
    this.fireClustersToggleTarget.checked = fireClustersEnabled
    this.fireClustersVisible = fireClustersEnabled
  }

  const legacyStrikesEnabled = l.strikes === true
  toggleIf.call(this, l.verifiedStrikes ?? legacyStrikesEnabled, "verifiedStrikesToggle", "toggleVerifiedStrikes")
  toggleIf.call(this, l.heatSignatures ?? legacyStrikesEnabled, "heatSignaturesToggle", "toggleHeatSignatures")
  restoreWeather.call(this, l)
  toggleIf.call(this, l.financial, "financialToggle", "toggleFinancial")
  toggleIf.call(this, l.chokepoints, "chokepointsToggle", "toggleChokepoints")
  toggleIf.call(this, l.militaryBases, "militaryBasesToggle", "toggleMilitaryBases")
  toggleIf.call(this, l.militaryFlights, "militaryFlightsToggle", "toggleMilitaryFlightsFilter")
  toggleIf.call(this, l.airbases, "airbasesToggle", "toggleAirbases")
  toggleIf.call(this, l.navalVessels, "navalVesselsToggle", "toggleNavalVessels")
  toggleIf.call(this, l.terrain, "terrainToggle", "toggleTerrain")

  if (l.terrainExaggeration && l.terrainExaggeration > 1 && this.hasTerrainExaggerationTarget) {
    this.terrainExaggerationTarget.value = l.terrainExaggeration
    this.setTerrainExaggeration()
  }
  if (l.buildings && l.buildings !== "off" && this.hasBuildingsSelectTarget) {
    this.buildingsSelectTarget.value = l.buildings
    this.toggleBuildings()
  }

  if (l.showCivilian === false && this.hasCivilianToggleTarget) {
    this.civilianToggleTarget.checked = false
    this.showCivilian = false
  }
  if (l.showMilitary === false && this.hasMilitaryToggleTarget) {
    this.militaryToggleTarget.checked = false
    this.showMilitary = false
  }

  if (l.satCategories) {
    for (const [category, visible] of Object.entries(l.satCategories)) {
      if (!visible) continue
      this.satCategoryVisible[category] = true
      const chip = this.element.querySelector(`.sb-chip[data-category="${category}"]`)
      if (chip) chip.classList.add("active")
      if (!this._loadedSatCategories.has(category)) this.fetchSatCategory(category)
    }
  }
}

function restoreSelections(prefs) {
  if (prefs.selected_countries?.length > 0) this._pendingCountryRestore = prefs.selected_countries
  if (prefs.airline_filter?.length > 0) this._airlineFilter = new Set(prefs.airline_filter)
  if (prefs.active_region && this.enterRegion) this.enterRegion(prefs.active_region)
}

function toggleIf(enabled, targetBase, methodName) {
  const layerKey = targetBase.replace(/Toggle$/, "")
  if (isLayerTemporarilyDisabled(layerKey)) return
  const hasTarget = `has${capitalize(targetBase)}Target`
  if (!enabled || !this[hasTarget]) return
  this[`${targetBase}Target`].checked = true
  this[methodName]()
}

function restoreWeather(layers) {
  if (!layers.weather || !this.hasWeatherToggleTarget) return
  this._weatherOpacity = layers.weatherOpacity || 0.6
  this.weatherToggleTarget.checked = true
  this._weatherActiveLayers = {}
  this.toggleWeather()
  if (layers.weatherLayers && typeof layers.weatherLayers === "object") {
    this._removeAllWeatherLayers()
    for (const [key, active] of Object.entries(layers.weatherLayers)) {
      if (active) this.toggleWeatherSublayer(key)
    }
  }
}

function capitalize(value) {
  return value.charAt(0).toUpperCase() + value.slice(1)
}
