// ── Region Mode ──────────────────────────────────────────────
// Focused regional analysis with curated layer profiles.
// Entering a region: snapshots current state, clears layers,
// flies camera to region, enables region-specific layers,
// and scopes all data fetches to the region's bounding box.

import { REGIONS, REGION_MAP, REGION_GROUPS } from "globe/regions"
import { applyDeepLink } from "globe/deeplinks"

export function applyRegionMethods(GlobeController) {
  function regionBoundsCenter(bounds = {}) {
    return {
      lat: ((bounds.lamin || 0) + (bounds.lamax || 0)) / 2.0,
      lng: ((bounds.lomin || 0) + (bounds.lomax || 0)) / 2.0,
    }
  }

  function regionCameraCenter(region) {
    const center = regionBoundsCenter(region.bounds)
    return {
      lat: region.camera?.lat ?? center.lat,
      lng: region.camera?.lng ?? center.lng,
    }
  }

  function regionCameraHeight(region) {
    const bounds = region.bounds || {}
    const center = regionBoundsCenter(bounds)
    const latSpanKm = Math.abs((bounds.lamax || 0) - (bounds.lamin || 0)) * 111.0
    const lngSpanKm = Math.abs((bounds.lomax || 0) - (bounds.lomin || 0)) * 111.0 * Math.abs(Math.cos(center.lat * Math.PI / 180))
    const derivedHeight = Math.round((Math.max(latSpanKm, lngSpanKm) * 1250.0) / 10000) * 10000
    return Math.max(region.camera?.height || 0, derivedHeight, 300000)
  }

  GlobeController.prototype._initRegions = function() {
    this._activeRegion = null
    this._preRegionState = null
    this._renderRegionDropdown()
  }

  GlobeController.prototype.enterRegion = function(regionKey) {
    const region = REGION_MAP[regionKey]
    if (!region) return

    // Snapshot current state for restore on exit
    if (!this._activeRegion) {
      this._preRegionState = this._buildWorkspacePayload("__snapshot__")
    }

    // Clear all current layers
    this._clearAllLayers()

    // Set active region
    this._activeRegion = region

    // Fly camera to region — offset south so the tilted view centers on the region.
    // When pitch is not straight-down, the camera looks north of its position,
    // so we shift the camera south proportional to height and tilt angle.
    const Cesium = window.Cesium
    if (Cesium && this.viewer) {
      const center = regionCameraCenter(region)
      const height = regionCameraHeight(region)
      const pitch = region.camera?.pitch || -Cesium.Math.PI_OVER_TWO
      const tiltFromDown = Math.abs(pitch + Math.PI / 2) // 0 = straight down, ~0.7 = 45°
      const heightKm = height / 1000
      // Degrees-lat offset: sqrt of height keeps it sane at high altitudes
      const latOffset = tiltFromDown * Math.sqrt(heightKm) * 0.25
      const camLat = center.lat - latOffset

      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(
          center.lng, camLat, height
        ),
        orientation: {
          heading: region.camera?.heading || 0,
          pitch: pitch,
          roll: 0,
        },
        duration: 2.0,
      })
    }

    // Enable region layers via applyDeepLink (reuses existing toggle logic)
    const state = {
      layers: [...region.layers],
      satCategories: region.satCategories || [],
    }

    // Region presets should preserve the old "full picture" behavior even now that
    // civilian and military feeds are split into separate toggles.
    if (region.layers.includes("flights") && !state.layers.includes("militaryFlights")) {
      state.layers.push("militaryFlights")
      state.showMilitary = true
      state.showCivilian = true
    }
    if (region.layers.includes("ships") && !state.layers.includes("navalVessels")) {
      state.layers.push("navalVessels")
    }

    applyDeepLink(this, state)

    // Update UI
    this._renderRegionIndicator()
    this._syncQuickBar()
    this._savePrefs()

    // Sync dropdown
    const select = document.getElementById("region-select")
    if (select) select.value = regionKey
  }

  GlobeController.prototype.exitRegion = function() {
    if (!this._activeRegion) return
    this._activeRegion = null

    // Restore previous state or go to global default
    if (this._preRegionState) {
      this._clearAllLayers()

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

      // Rebuild layer list from saved state
      if (pre.layers) {
        state.layers = Object.entries(pre.layers)
          .filter(([k, v]) => v === true && k !== "showCivilian" && k !== "showMilitary" && k !== "terrain")
          .map(([k]) => k)
        if (pre.layers.terrain) state.layers.push("terrain")
        state.showCivilian = pre.layers.showCivilian
        state.showMilitary = pre.layers.showMilitary
        if (pre.layers.satCategories) {
          state.satCategories = Object.entries(pre.layers.satCategories)
            .filter(([, v]) => v)
            .map(([k]) => k)
        }
      }

      applyDeepLink(this, state)
      this._preRegionState = null
    } else {
      this._clearAllLayers()
      const Cesium = window.Cesium
      if (Cesium && this.viewer) {
        this.viewer.camera.flyTo({
          destination: Cesium.Cartesian3.fromDegrees(10, 30, 20000000),
          duration: 1.5,
        })
      }
    }

    this._renderRegionIndicator()
    this._syncQuickBar()
    this._savePrefs()

    // Reset dropdown
    const select = document.getElementById("region-select")
    if (select) select.value = ""
  }

  GlobeController.prototype.selectRegion = function(event) {
    const key = event.target.value
    if (key) {
      this.enterRegion(key)
    } else {
      this.exitRegion()
    }
  }

  GlobeController.prototype._renderRegionDropdown = function() {
    const select = document.getElementById("region-select")
    if (!select) return

    // Build optgroups
    let html = '<option value="">Select Region</option>'
    for (const group of REGION_GROUPS) {
      const regions = REGIONS.filter(r => r.group === group)
      html += `<optgroup label="${group}">`
      for (const r of regions) {
        html += `<option value="${r.key}">${r.name}</option>`
      }
      html += '</optgroup>'
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
}
