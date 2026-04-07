import { applyDeepLink } from "globe/deeplinks"
import { LAYER_REGISTRY, LAYER_REGISTRY_BY_KEY } from "globe/controller/ui/registry"

export function applyWorkspaceMethods(GlobeController) {

  GlobeController.prototype._loadWorkspaceList = async function() {
    if (!this.signedInValue || !this.hasWorkspaceSelectTarget) return
    try {
      const resp = await fetch("/api/workspaces")
      if (!resp.ok) return
      this._workspaces = await resp.json()
      this._renderWorkspaceOptions()
    } catch { /* silent */ }
  }

  GlobeController.prototype._renderWorkspaceOptions = function() {
    const select = this.workspaceSelectTarget
    const current = select.value
    // Keep the default option, rebuild rest
    select.innerHTML = '<option value="">— Workspaces —</option>'
    for (const ws of this._workspaces || []) {
      const opt = document.createElement("option")
      opt.value = ws.id
      opt.textContent = ws.name + (ws.is_default ? " ★" : "")
      select.appendChild(opt)
    }
    // Restore selection if still valid
    if (current && [...select.options].some(o => o.value === current)) {
      select.value = current
    }
    // Show/hide delete button
    if (this.hasWorkspaceDeleteBtnTarget) {
      this.workspaceDeleteBtnTarget.style.display = select.value ? "" : "none"
    }
  }

  GlobeController.prototype.loadWorkspace = function() {
    const id = this.workspaceSelectTarget.value
    if (!id) {
      if (this.hasWorkspaceDeleteBtnTarget) this.workspaceDeleteBtnTarget.style.display = "none"
      return
    }
    const ws = (this._workspaces || []).find(w => String(w.id) === id)
    if (!ws) return

    if (this.hasWorkspaceDeleteBtnTarget) this.workspaceDeleteBtnTarget.style.display = ""

    // Turn off all layers first
    this._clearAllLayers()

    // Build state from workspace
    const state = { camera: {} }
    if (ws.camera_lat != null) {
      state.camera = {
        lat: ws.camera_lat,
        lng: ws.camera_lng,
        height: ws.camera_height || 20000000,
        heading: ws.camera_heading || 0,
        pitch: ws.camera_pitch || -Math.PI / 2,
      }
    }

    // Layers
    if (ws.layers) {
      state.layers = Object.entries(ws.layers)
        .filter(([k, v]) => v === true && !!LAYER_REGISTRY_BY_KEY[k])
        .map(([k]) => k)
      if (ws.layers.satCategories) {
        state.satCategories = Object.entries(ws.layers.satCategories)
          .filter(([, v]) => v)
          .map(([k]) => k)
      }
      if (ws.layers.showCivilian !== undefined) state.showCivilian = ws.layers.showCivilian
      if (ws.layers.showMilitary !== undefined) state.showMilitary = ws.layers.showMilitary
    }

    // Filters (countries)
    if (ws.filters?.selected_countries?.length > 0) {
      state.countries = ws.filters.selected_countries
    }

    applyDeepLink(this, state)
    this._toast(`Loaded "${ws.name}"`)
  }

  GlobeController.prototype.saveWorkspace = function() {
    const selectedId = this.hasWorkspaceSelectTarget ? this.workspaceSelectTarget.value : ""
    if (selectedId) {
      // Update existing workspace
      const ws = (this._workspaces || []).find(w => String(w.id) === selectedId)
      this._doUpdateWorkspace(selectedId, ws?.name || "Workspace")
    } else {
      // Create new
      const name = prompt("Workspace name:")
      if (!name || !name.trim()) return
      this._doSaveWorkspace(name.trim())
    }
  }

  GlobeController.prototype._doUpdateWorkspace = async function(id, name) {
    const body = this._buildWorkspacePayload(name)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const resp = await fetch(`/api/workspaces/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
        body: JSON.stringify(body),
      })
      if (!resp.ok) {
        this._toast("Failed to update")
        return
      }
      await this._loadWorkspaceList()
      this.workspaceSelectTarget.value = String(id)
      this._toast(`Updated "${name}"`)
    } catch {
      this._toast("Failed to update workspace")
    }
  }

  GlobeController.prototype._buildWorkspacePayload = function(name) {
    const Cesium = window.Cesium
    let carto
    try { carto = this.viewer.camera.positionCartographic } catch { return { name } }

    const layerPrefs = Object.fromEntries(
      LAYER_REGISTRY.map(layer => [layer.key, !!this[layer.visibleProp]])
    )

    return {
      name,
      camera_lat: Cesium.Math.toDegrees(carto.latitude),
      camera_lng: Cesium.Math.toDegrees(carto.longitude),
      camera_height: carto.height,
      camera_heading: this.viewer.camera.heading,
      camera_pitch: this.viewer.camera.pitch,
      layers: {
        flights: this.flightsVisible,
        trails: this.trailsVisible,
        ships: this.shipsVisible,
        borders: this.bordersVisible,
        cities: this.citiesVisible,
        airports: this.airportsVisible,
        earthquakes: this.earthquakesVisible,
        naturalEvents: this.naturalEventsVisible,
        cameras: this.camerasVisible,
        insights: this.insightsVisible,
        situations: this.situationsVisible,
        gpsJamming: this.gpsJammingVisible,
        news: this.newsVisible,
        cables: this.cablesVisible,
        ports: this.portsVisible,
        shippingLanes: this.shippingLanesVisible,
        outages: this.outagesVisible,
        powerPlants: this.powerPlantsVisible,
        commoditySites: this.commoditySitesVisible,
        conflicts: this.conflictsVisible,
        traffic: this.trafficVisible,
        notams: this.notamsVisible,
        strikeArcs: this._strikeArcsVisible,
        hexTheater: this._hexTheaterVisible,
        fireClusters: this.fireClustersVisible,
        weatherLayers: this._weatherActiveLayers ? { ...this._weatherActiveLayers } : {},
        weatherOpacity: this._weatherOpacity || 0.6,
        terrainExaggeration: this.viewer?.scene?.verticalExaggeration || 1,
        buildings: this.hasBuildingsSelectTarget ? this.buildingsSelectTarget.value : "off",
        militaryFlights: this._milFlightsActive,
        airbases: this.airbasesVisible,
        navalVessels: this.navalVesselsVisible,
        militaryBases: this.militaryBasesVisible,
        verifiedStrikes: this.verifiedStrikesVisible,
        heatSignatures: this.heatSignaturesVisible,
        fireHotspots: this.fireHotspotsVisible,
        weather: this.weatherVisible,
        financial: this.financialVisible,
        chokepoints: this.chokepointsVisible,
        showCivilian: this.showCivilian,
        showMilitary: this.showMilitary,
        satCategories: { ...this.satCategoryVisible },
      },
      filters: this.selectedCountries?.size > 0
        ? { selected_countries: [...this.selectedCountries] }
        : {},
    }
  }

  GlobeController.prototype._doSaveWorkspace = async function(name) {
    if (!window.Cesium || !this.viewer?.camera) return

    const body = this._buildWorkspacePayload(name)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      const resp = await fetch("/api/workspaces", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
        body: JSON.stringify(body),
      })
      if (!resp.ok) {
        const err = await resp.json().catch(() => ({}))
        this._toast(err.errors?.[0] || "Failed to save")
        return
      }
      const ws = await resp.json()
      await this._loadWorkspaceList()
      this.workspaceSelectTarget.value = String(ws.id)
      if (this.hasWorkspaceDeleteBtnTarget) this.workspaceDeleteBtnTarget.style.display = ""
      this._toast(`Saved "${name}"`)
    } catch {
      this._toast("Failed to save workspace")
    }
  }

  GlobeController.prototype.deleteWorkspace = async function() {
    const id = this.workspaceSelectTarget.value
    if (!id) return
    const ws = (this._workspaces || []).find(w => String(w.id) === id)
    if (!ws) return
    if (!confirm(`Delete "${ws.name}"?`)) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      await fetch(`/api/workspaces/${id}`, {
        method: "DELETE",
        headers: { "X-CSRF-Token": csrfToken },
      })
      this._toast(`Deleted "${ws.name}"`)
      await this._loadWorkspaceList()
    } catch {
      this._toast("Failed to delete")
    }
  }

  // Turn off all visible layers so we start clean when loading a workspace
  GlobeController.prototype._clearAllLayers = function() {
    const layerToggles = [
      ["flightsVisible", "flightsToggle", "toggleFlights"],
      ["trailsVisible", "trailsToggle", "toggleTrails"],
      ["shipsVisible", "shipsToggle", "toggleShips"],
      ["bordersVisible", "bordersToggle", "toggleBorders"],
      ["citiesVisible", "citiesToggle", "toggleCities"],
      ["airportsVisible", "airportsToggle", "toggleAirports"],
      ["earthquakesVisible", "earthquakesToggle", "toggleEarthquakes"],
      ["naturalEventsVisible", "naturalEventsToggle", "toggleNaturalEvents"],
      ["camerasVisible", "camerasToggle", "toggleCameras"],
      ["insightsVisible", "insightsToggle", "toggleInsights"],
      ["situationsVisible", "situationsToggle", "toggleSituations"],
      ["gpsJammingVisible", "gpsJammingToggle", "toggleGpsJamming"],
      ["newsVisible", "newsToggle", "toggleNews"],
      ["cablesVisible", "cablesToggle", "toggleCables"],
      ["portsVisible", "portsToggle", "togglePorts"],
      ["shippingLanesVisible", "shippingLanesToggle", "toggleShippingLanes"],
      ["fireHotspotsVisible", "fireHotspotsToggle", "toggleFireHotspots"],
      ["verifiedStrikesVisible", "verifiedStrikesToggle", "toggleVerifiedStrikes"],
      ["heatSignaturesVisible", "heatSignaturesToggle", "toggleHeatSignatures"],
      ["weatherVisible", "weatherToggle", "toggleWeather"],
      ["financialVisible", "financialToggle", "toggleFinancial"],
      ["chokepointsVisible", "chokepointsToggle", "toggleChokepoints"],
      ["militaryBasesVisible", "militaryBasesToggle", "toggleMilitaryBases"],
      ["_milFlightsActive", "militaryFlightsToggle", "toggleMilitaryFlightsFilter"],
      ["airbasesVisible", "airbasesToggle", "toggleAirbases"],
      ["navalVesselsVisible", "navalVesselsToggle", "toggleNavalVessels"],
      ["outagesVisible", "outagesToggle", "toggleOutages"],
      ["powerPlantsVisible", "powerPlantsToggle", "togglePowerPlants"],
      ["commoditySitesVisible", "commoditySitesToggle", "toggleCommoditySites"],
      ["conflictsVisible", "conflictsToggle", "toggleConflicts"],
      ["trafficVisible", "trafficToggle", "toggleTraffic"],
      ["notamsVisible", "notamsToggle", "toggleNotams"],
    ]

    for (const [visibleProp, toggleTarget, methodName] of layerToggles) {
      if (!this[visibleProp] || typeof this[methodName] !== "function") continue

      const hasTarget = `has${toggleTarget.charAt(0).toUpperCase()}${toggleTarget.slice(1)}Target`
      if (this[hasTarget]) {
        this[`${toggleTarget}Target`].checked = false
      }

      this[methodName]()
    }

    // Clear satellite categories
    for (const [cat, visible] of Object.entries(this.satCategoryVisible)) {
      if (visible) {
        this.satCategoryVisible[cat] = false
        const chip = this.element.querySelector(`.sb-chip[data-category="${cat}"]`)
        if (chip) chip.classList.remove("active")
      }
    }

    this._syncQuickBar()
    this._updateSatBadge()
  }
}
