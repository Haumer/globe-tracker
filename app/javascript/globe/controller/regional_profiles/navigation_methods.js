import { applyDeepLink } from "globe/deeplinks"
import { REGIONS, REGION_GROUPS, REGION_MAP } from "globe/regions"
import {
  regionCameraCenter,
  regionCameraHeight,
  regionDefaultLayers,
} from "globe/controller/regional_profiles/shared"

export function applyRegionalNavigationMethods(GlobeController) {
  GlobeController.prototype.enterRegion = function(regionKey) {
    const region = REGION_MAP[regionKey]
    if (!region) return

    if (!this._activeRegion) {
      this._preRegionState = this._buildWorkspacePayload("__snapshot__")
    }

    this._clearAllLayers()

    if (this._activeLocalProfileKey && this._activeLocalProfileKey !== region.key) {
      this._activeLocalProfileKey = null
    }
    this._activeRegion = region
    this.setCountrySelection?.(region.countries || [], {
      refresh: false,
      showBorders: regionDefaultLayers(region).includes("borders"),
      useHull: false,
    })

    const Cesium = window.Cesium
    if (Cesium && this.viewer) {
      const center = regionCameraCenter(region)
      const height = regionCameraHeight(region)
      const pitch = region.camera?.pitch || -Cesium.Math.PI_OVER_TWO
      const tiltFromDown = Math.abs(pitch + Math.PI / 2)
      const heightKm = height / 1000
      const latOffset = tiltFromDown * Math.sqrt(heightKm) * 0.25
      const camLat = center.lat - latOffset

      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(center.lng, camLat, height),
        orientation: {
          heading: region.camera?.heading || 0,
          pitch,
          roll: 0,
        },
        duration: 2.0,
      })
    }

    const state = {
      layers: regionDefaultLayers(region),
      satCategories: region.satCategories || [],
    }

    if (state.layers.includes("flights") && !state.layers.includes("militaryFlights")) {
      state.layers.push("militaryFlights")
      state.showMilitary = true
      state.showCivilian = true
    }
    if (state.layers.includes("ships") && !state.layers.includes("navalVessels")) {
      state.layers.push("navalVessels")
    }

    applyDeepLink(this, state)

    this._renderRegionIndicator()
    this._renderLocalProfile?.()
    this._loadRegionalEconomyMap?.(region)
    this._syncQuickBar()
    this._savePrefs()

    const select = document.getElementById("region-select")
    if (select) select.value = regionKey
  }

  GlobeController.prototype.exitRegion = function() {
    if (!this._activeRegion) return
    this._activeRegion = null
    this._activeLocalProfileKey = null
    this._regionalEconomyMapViewSelection = "country"
    this._regionalEconomySectorSelection = "all"
    this._regionalIndicatorMapData = []
    this._clearRegionalEconomyMap?.()
    this._clearRegionalAdminEconomyMap?.()
    this._clearRegionalDistrictMap?.()
    this._clearRegionalMunicipalityMap?.()

    if (this._preRegionState) {
      this._clearAllLayers()
      this.setCountrySelection?.([], { refresh: false })

      const state = { camera: {} }
      const pre = this._preRegionState
      if (pre.camera_lat != null) {
        state.camera = {
          lat: pre.camera_lat,
          lng: pre.camera_lng,
          height: pre.camera_height || 20000000,
          heading: pre.camera_heading || 0,
          pitch: pre.camera_pitch || -Math.PI / 2,
        }
      }

      if (pre.layers) {
        state.layers = Object.entries(pre.layers)
          .filter(([key, value]) => value === true && key !== "showCivilian" && key !== "showMilitary" && key !== "terrain")
          .map(([key]) => key)
        if (pre.layers.terrain) state.layers.push("terrain")
        state.showCivilian = pre.layers.showCivilian
        state.showMilitary = pre.layers.showMilitary
        if (pre.layers.satCategories) {
          state.satCategories = Object.entries(pre.layers.satCategories)
            .filter(([, value]) => value)
            .map(([key]) => key)
        }
      }
      if (pre.filters?.selected_countries?.length > 0) {
        state.countries = pre.filters.selected_countries
      }

      applyDeepLink(this, state)
      this._preRegionState = null
    } else {
      this._clearAllLayers()
      this.setCountrySelection?.([], { refresh: false })
      const Cesium = window.Cesium
      if (Cesium && this.viewer) {
        this.viewer.camera.flyTo({
          destination: Cesium.Cartesian3.fromDegrees(10, 30, 20000000),
          duration: 1.5,
        })
      }
    }

    this._renderRegionIndicator()
    this._renderLocalProfile?.()
    this._syncQuickBar()
    this._savePrefs()

    const select = document.getElementById("region-select")
    if (select) select.value = ""
  }

  GlobeController.prototype.selectRegion = function(event) {
    const key = event.target.value
    if (key) this.enterRegion(key)
    else this.exitRegion()
  }

  GlobeController.prototype._renderRegionDropdown = function() {
    const select = document.getElementById("region-select")
    if (!select) return

    let html = '<option value="">Select Region</option>'
    for (const group of REGION_GROUPS) {
      const regions = REGIONS.filter(region => region.group === group)
      html += `<optgroup label="${group}">`
      for (const region of regions) {
        html += `<option value="${region.key}">${region.name}</option>`
      }
      html += "</optgroup>"
    }
    select.innerHTML = html
  }

  GlobeController.prototype._renderRegionIndicator = function() {
    const indicator = document.getElementById("region-indicator")
    if (!indicator) return

    if (this._activeRegion) {
      const bar = document.createElement("div")
      bar.className = "region-active-bar"

      const badge = document.createElement("span")
      badge.className = "region-badge"
      badge.textContent = this._activeRegion.name
      bar.appendChild(badge)

      const desc = document.createElement("span")
      desc.className = "region-desc"
      desc.textContent = this._activeRegion.description
      bar.appendChild(desc)

      if (this.signedInValue) {
        const payload = this._buildAreaWorkspacePayload()
        if (payload && this._buildAreaWorkspaceForm) {
          bar.appendChild(this._buildAreaWorkspaceForm(payload, {
            formClass: "region-track-form",
            submitClass: "region-track-btn",
            submitLabel: "Track Area",
            submitTitle: "Track area",
          }))
        }
      } else {
        const link = document.createElement("a")
        link.className = "region-track-btn"
        link.href = "/users/sign_in"
        link.textContent = "Sign In"
        bar.appendChild(link)
      }

      const localBtn = document.createElement("button")
      localBtn.type = "button"
      localBtn.className = "region-local-btn"
      localBtn.textContent = "Local View"
      localBtn.addEventListener("click", event => {
        event.preventDefault()
        this.openLocalProfile?.(this._activeRegion?.key)
      })
      bar.appendChild(localBtn)

      const exitBtn = document.createElement("button")
      exitBtn.type = "button"
      exitBtn.className = "region-exit-btn"
      exitBtn.title = "Exit region"
      exitBtn.textContent = "\u00d7"
      exitBtn.addEventListener("click", event => {
        event.preventDefault()
        this.exitRegion()
      })
      bar.appendChild(exitBtn)

      indicator.replaceChildren(bar)
      indicator.style.display = ""
    } else {
      indicator.innerHTML = ""
      indicator.style.display = "none"
    }
  }

  GlobeController.prototype._hasActiveLocalProfile = function() {
    return !!(this._activeLocalProfileKey && this._activeRegion?.key === this._activeLocalProfileKey)
  }

  GlobeController.prototype._localProfileRegion = function() {
    return this._hasActiveLocalProfile() ? REGION_MAP[this._activeLocalProfileKey] : null
  }

  GlobeController.prototype.openDachLocalProfile = function(event) {
    event?.preventDefault?.()
    this.openLocalProfile("dach")
  }

  GlobeController.prototype.openLocalProfile = function(regionKey = this._activeRegion?.key) {
    const targetKey = regionKey || this._activeRegion?.key
    if (!targetKey) return
    const targetRegion = REGION_MAP[targetKey]

    if (this._activeRegion?.key !== targetKey) {
      this.enterRegion(targetKey)
    }

    if (targetRegion?.mode === "economic") {
      this._regionalEconomyMapViewSelection = "admin"
      this._regionalEconomySectorSelection = "all"
    }

    this._activeLocalProfileKey = targetKey
    this._renderLocalProfile()
    this._syncRegionalEconomyMap?.()
    this._showRightPanel?.("localProfile")
    this._savePrefs()
  }

  GlobeController.prototype.closeLocalProfile = function(event) {
    event?.preventDefault?.()
    this._activeLocalProfileKey = null
    this._regionalEconomyMapViewSelection = "country"
    this._regionalEconomySectorSelection = "all"
    this._renderLocalProfile()
    this._clearRegionalAdminEconomyMap?.()
    this._clearRegionalDistrictMap?.()
    this._clearRegionalMunicipalityMap?.()
    this._loadRegionalEconomyMap?.()
    this._syncRightPanels?.()
    this._savePrefs()
  }
}
