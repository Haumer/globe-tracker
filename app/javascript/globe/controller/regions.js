// ── Region Mode ──────────────────────────────────────────────
// Focused regional analysis with curated layer profiles.
// Entering a region: snapshots current state, clears layers,
// flies camera to region, enables region-specific layers,
// and scopes all data fetches to the region's bounding box.

import { REGIONS, REGION_MAP, REGION_GROUPS } from "../regions"
import { applyDeepLink } from "../deeplinks"

export function applyRegionMethods(GlobeController) {

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
      const pitch = region.camera.pitch || -Cesium.Math.PI_OVER_TWO
      const tiltFromDown = Math.abs(pitch + Math.PI / 2) // 0 = straight down, ~0.7 = 45°
      const heightKm = region.camera.height / 1000
      // Degrees-lat offset: sqrt of height keeps it sane at high altitudes
      const latOffset = tiltFromDown * Math.sqrt(heightKm) * 0.25
      const camLat = region.camera.lat - latOffset

      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(
          region.camera.lng, camLat, region.camera.height
        ),
        orientation: {
          heading: region.camera.heading || 0,
          pitch: pitch,
          roll: 0,
        },
        duration: 2.0,
      })
    }

    // Enable region layers via applyDeepLink (reuses existing toggle logic)
    const state = {
      layers: region.layers,
      satCategories: region.satCategories || [],
    }

    // Also enable military flights by default for conflict regions
    if (region.layers.includes("flights")) {
      state.showMilitary = true
      state.showCivilian = true
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
      indicator.innerHTML =
        `<div class="region-active-bar">` +
          `<span class="region-badge">${this._activeRegion.name}</span>` +
          `<span class="region-desc">${this._activeRegion.description}</span>` +
          `${this.signedInValue ? `<button class="region-track-btn" data-action="click->globe#trackCurrentArea" title="Track area">Track Area</button>` : `<a class="region-track-btn" href="/users/sign_in">Sign In</a>`}` +
          `<button class="region-exit-btn" data-action="click->globe#exitRegion" title="Exit region">&times;</button>` +
        `</div>`
      indicator.style.display = ""
    } else {
      indicator.innerHTML = ""
      indicator.style.display = "none"
    }
  }
}
