import { resetTilt, resetView, viewTopDown, zoomIn, zoomOut } from "../camera"

export function applyGeographyEnvironmentMethods(GlobeController) {
  GlobeController.prototype.toggleTerrain = function() {
    const Cesium = window.Cesium
    this.terrainEnabled = this.hasTerrainToggleTarget && this.terrainToggleTarget.checked

    if (this.terrainEnabled) {
      this.viewer.scene.setTerrain(Cesium.Terrain.fromWorldTerrain({
        requestWaterMask: true,
        requestVertexNormals: true,
      }))
    } else {
      this.viewer.scene.setTerrain(new Cesium.Terrain(new Cesium.EllipsoidTerrainProvider()))
      this.viewer.scene.verticalExaggeration = 1.0
    }

    if (this.hasTerrainExaggerationTarget && !this.terrainEnabled) {
      this.terrainExaggerationTarget.value = 1
      const label = this.terrainExaggerationTarget.closest(".sb-slider-row")?.querySelector(".sb-slider-val")
      if (label) label.textContent = "1×"
    }
    this._savePrefs()
  }

  GlobeController.prototype.setTerrainExaggeration = function() {
    const value = this.hasTerrainExaggerationTarget ? parseFloat(this.terrainExaggerationTarget.value) : 1
    this.viewer.scene.verticalExaggeration = value
    const label = this.terrainExaggerationTarget?.closest(".sb-slider-row")?.querySelector(".sb-slider-val")
    if (label) label.textContent = `${value}×`
    this._savePrefs()
  }

  GlobeController.prototype.toggleBuildings = async function() {
    const Cesium = window.Cesium
    const mode = this.hasBuildingsSelectTarget ? this.buildingsSelectTarget.value : "off"
    this.buildingsEnabled = mode !== "off"

    if (this._buildingsTileset) this._buildingsTileset.show = false
    if (this._googleTileset) this._googleTileset.show = false

    if (mode === "osm") await showOsmBuildings.call(this, Cesium)
    else if (mode === "google") await showGoogleBuildings.call(this, Cesium)

    if (mode !== "google") this.viewer.scene.globe.show = true
    this._savePrefs()
  }

  GlobeController.prototype.resetView = function() { resetView(this.viewer) }
  GlobeController.prototype.viewTopDown = function() { viewTopDown(this.viewer) }
  GlobeController.prototype.resetTilt = function() { resetTilt(this.viewer) }
  GlobeController.prototype.zoomIn = function() { zoomIn(this.viewer) }
  GlobeController.prototype.zoomOut = function() { zoomOut(this.viewer) }
}

async function showOsmBuildings(Cesium) {
  if (!this._buildingsTileset) {
    try {
      this._buildingsTileset = await Cesium.createOsmBuildingsAsync()
      this.viewer.scene.primitives.add(this._buildingsTileset)
    } catch (error) {
      console.warn("Failed to load OSM buildings:", error)
      if (this.hasBuildingsSelectTarget) this.buildingsSelectTarget.value = "off"
      this.buildingsEnabled = false
      return
    }
  }
  this._buildingsTileset.show = true
}

async function showGoogleBuildings(Cesium) {
  if (!this._googleTileset) {
    try {
      this._googleTileset = await Cesium.Cesium3DTileset.fromIonAssetId(2275207)
      this._googleTileset.maximumScreenSpaceError = 8
      this.viewer.scene.primitives.add(this._googleTileset)
    } catch (error) {
      console.warn("Failed to load Google Photorealistic 3D Tiles:", error)
      if (this.hasBuildingsSelectTarget) this.buildingsSelectTarget.value = "off"
      this.buildingsEnabled = false
      return
    }
  }
  this._googleTileset.show = true
  this.viewer.scene.globe.show = false
}
