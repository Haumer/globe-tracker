import { getDataSource } from "../utils"

export function applyGeographyBorderMethods(GlobeController) {
  GlobeController.prototype.toggleCountrySelect = function() {
    this.countrySelectMode = !this.countrySelectMode
    if (this.countrySelectMode) {
      ensureBordersVisible.call(this)
      this.viewer.canvas.style.cursor = "pointer"
    } else {
      this.viewer.canvas.style.cursor = ""
    }

    const btn = document.getElementById("country-select-btn")
    if (btn) btn.classList.toggle("active", this.countrySelectMode)
  }

  GlobeController.prototype.toggleBorders = function() {
    this.bordersVisible = this.hasBordersToggleTarget && this.bordersToggleTarget.checked
    if (this.bordersVisible && !this.bordersLoaded) this.loadBorders()
    if (this._ds["borders"]) this._ds["borders"].show = this.bordersVisible
    this._savePrefs()
  }

  GlobeController.prototype.loadBorders = async function() {
    const Cesium = window.Cesium

    this._toast("Loading borders...")
    try {
      const response = await fetch("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson")
      if (!response.ok) return
      const geojson = await response.json()

      this._countryFeatures = geojson.features
      const dataSource = this.getBordersDataSource()
      const defaultColor = Cesium.Color.fromCssColorString("#4fc3f7").withAlpha(0.4)

      geojson.features.forEach((feature, featureIndex) => {
        const geom = feature.geometry
        if (!geom) return

        const countryName = feature.properties?.NAME || feature.properties?.name || `Unknown-${featureIndex}`
        const rings = []
        if (geom.type === "Polygon") rings.push(geom.coordinates[0])
        else if (geom.type === "MultiPolygon") geom.coordinates.forEach(poly => rings.push(poly[0]))

        const countryEntityList = this._countryEntities.get(countryName) || []
        rings.forEach((ring, ringIndex) => {
          if (ring.length < 3) return

          const positions = ring.map(coord => Cesium.Cartesian3.fromDegrees(coord[0], coord[1]))
          const entityId = `border-${featureIndex}-${ringIndex}`
          const entity = dataSource.entities.add({
            id: entityId,
            polyline: {
              positions,
              width: 1.5,
              material: defaultColor,
              clampToGround: true,
              classificationType: Cesium.ClassificationType.BOTH,
            },
          })

          this._borderCountryMap.set(entityId, { name: countryName })
          countryEntityList.push(entity)
        })

        this._countryEntities.set(countryName, countryEntityList)
      })

      this.bordersLoaded = true
      this._ds["borders"].show = this.bordersVisible
      this._toastHide()
      restorePendingSelections.call(this)
    } catch (error) {
      console.error("Failed to load borders:", error)
    }
  }

  GlobeController.prototype.toggleCountrySelection = function(countryName) {
    if (this.selectedCountries.has(countryName)) this.selectedCountries.delete(countryName)
    else this.selectedCountries.add(countryName)

    this._activeCircle = null
    this._updateSelectedCountriesBbox()
    this.updateBorderColors()
    this._updateDeselectBtn()
    refreshSelectionScopedLayers.call(this)
    this._savePrefs()
  }

  GlobeController.prototype.clearCountrySelection = function() {
    this.selectedCountries.clear()
    this._selectedCountriesBbox = null
    this._activeCircle = null
    this.countrySelectMode = false
    this.viewer.canvas.style.cursor = ""
    this.removeDrawCircle()
    this.updateBorderColors()
    this._updateDeselectBtn()
    this.closeDetail()

    if (this.flightsVisible) this.fetchFlights()
    if (this.shipsVisible) this.fetchShips()
    if (this.camerasVisible) this.fetchWebcams()
    this._entityListRequested = false
    this.updateEntityList()
  }

  GlobeController.prototype._updateDeselectBtn = function() {
    if (this.hasDeselectAllBtnTarget) {
      this.deselectAllBtnTarget.style.display = this.selectedCountries.size > 0 ? "" : "none"
    }
  }

  GlobeController.prototype.updateBorderColors = function() {
    const Cesium = window.Cesium
    const defaultColor = Cesium.Color.fromCssColorString("#4fc3f7").withAlpha(0.4)
    const selectedColor = Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.8)

    for (const [countryName, entities] of this._countryEntities) {
      const isSelected = this.selectedCountries.has(countryName)
      entities.forEach(entity => {
        entity.polyline.material = isSelected ? selectedColor : defaultColor
      })
    }
  }

  GlobeController.prototype.showBorderDetail = function() {
    if (this.selectedCountries.size === 0) {
      this.closeDetail()
      return
    }

    const countryList = [...this.selectedCountries].sort().join(", ")
    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign">Selected Countries</div>
      <div class="detail-country">${this.selectedCountries.size} countries</div>
      <div class="detail-country-list">${countryList}</div>
      <div class="detail-border-actions">
        ${this.signedInValue ? `
        <button class="detail-track-btn" id="track-area-btn" style="background:rgba(76,175,80,0.14);border-color:rgba(76,175,80,0.28);color:#81c784;">
          <i class="fa-solid fa-layer-group"></i> Track Area
        </button>` : `
        <a class="detail-track-btn" href="/users/sign_in" style="background:rgba(76,175,80,0.14);border-color:rgba(76,175,80,0.28);color:#81c784;text-decoration:none;">
          <i class="fa-solid fa-right-to-bracket"></i> Sign In To Track
        </a>`}
        <button class="detail-track-btn" id="draw-circle-btn">
          <i class="fa-solid fa-circle-dot"></i> Draw Circle
        </button>
        <button class="detail-track-btn" id="area-report-btn" style="background:rgba(79,195,247,0.15);border-color:rgba(79,195,247,0.3);color:#4fc3f7;">
          <i class="fa-solid fa-chart-bar"></i> Area Report
        </button>
        <button class="detail-track-btn" id="clear-selection-btn">Clear Selection</button>
      </div>
      <div id="area-report-content"></div>
    `

    document.getElementById("track-area-btn")?.addEventListener("click", () => this.trackCurrentArea())
    document.getElementById("draw-circle-btn")?.addEventListener("click", () => this.enterDrawMode())
    document.getElementById("clear-selection-btn")?.addEventListener("click", () => this.clearCountrySelection())
    document.getElementById("area-report-btn")?.addEventListener("click", () => this._generateAreaReport())
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype.enterDrawMode = function() {
    ensureBordersVisible.call(this)
    this.drawMode = true
    this._drawCenter = null
    this.removeDrawCircle()
    this.viewer.scene.screenSpaceCameraController.enableRotate = false
    this.viewer.canvas.style.cursor = "crosshair"
    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign">Draw Circle</div>
      <div class="detail-country">Click and drag to draw a circle</div>
      <button class="detail-track-btn" id="cancel-draw-btn">Cancel</button>
    `
    document.getElementById("cancel-draw-btn")?.addEventListener("click", () => this.exitDrawMode())
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype.exitDrawMode = function() {
    this.drawMode = false
    this._drawCenter = null
    this.viewer.scene.screenSpaceCameraController.enableRotate = true
    this.viewer.canvas.style.cursor = ""
    this.showBorderDetail()
  }

  GlobeController.prototype.showDrawPreview = function(center, radius) {
    const Cesium = window.Cesium
    const dataSource = this.getBordersDataSource()

    this._drawRadius = Math.max(radius, 1000)
    if (!this._drawCircleEntity) {
      this._drawCircleEntity = dataSource.entities.add({
        id: "draw-circle",
        position: Cesium.Cartesian3.fromDegrees(center.lng, center.lat),
        ellipse: {
          semiMajorAxis: new Cesium.CallbackProperty(() => this._drawRadius, false),
          semiMinorAxis: new Cesium.CallbackProperty(() => this._drawRadius, false),
          material: Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.08),
          outline: true,
          outlineColor: Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.6),
          outlineWidth: 2,
          height: 0,
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
    }

    const radiusKm = Math.round(radius / 1000)
    const instrEl = this.detailContentTarget.querySelector(".detail-country")
    if (instrEl && radiusKm > 0) {
      instrEl.textContent = `Radius: ${radiusKm.toLocaleString()} km — release to confirm`
    }
  }

  GlobeController.prototype.removeDrawCircle = function() {
    if (this._drawCircleEntity && this._ds["borders"]) {
      this._ds["borders"].entities.remove(this._drawCircleEntity)
      this._drawCircleEntity = null
      this._drawRadius = 0
    }
  }

  GlobeController.prototype.applyCircleFilter = function(center, radius, options = {}) {
    ensureBordersVisible.call(this)

    if (!options.keepCountries) {
      this.selectedCountries.clear()
      this._selectedCountriesBbox = null
      this._selectedCountriesHull = null
      this.updateBorderColors()
      this._updateDeselectBtn()
    }

    this._activeCircle = { center, radius }
    this.showDrawPreview(center, radius)
    refreshSelectionScopedLayers.call(this, !!options.forceEntityList)
    this._savePrefs()

    if (options.showDetail) this.showBorderDetail()
  }

  GlobeController.prototype.selectCountriesInCircle = function(center, radius) {
    for (const feature of this._countryFeatures) {
      const geom = feature.geometry
      const name = feature.properties?.NAME || feature.properties?.name
      if (!geom || !name) continue

      const polygons = geom.type === "Polygon" ? [geom.coordinates] : geom.type === "MultiPolygon" ? geom.coordinates : []
      let intersects = false

      for (const poly of polygons) {
        for (const coord of poly[0]) {
          const dist = this.haversineDistance(center, { lat: coord[1], lng: coord[0] })
          if (dist <= radius) {
            intersects = true
            break
          }
        }
        if (intersects) break
        if (this.pointInPolygon(center.lat, center.lng, poly[0])) {
          intersects = true
          break
        }
      }

      if (intersects && this._countryEntities.has(name)) this.selectedCountries.add(name)
    }

    this._updateSelectedCountriesBbox()
    this.updateBorderColors()
    this.applyCircleFilter(center, radius, { showDetail: true, keepCountries: true, forceEntityList: true })
  }

  GlobeController.prototype.getBordersDataSource = function() {
    return getDataSource(this.viewer, this._ds, "borders")
  }
}

function ensureBordersVisible() {
  if (!this.bordersLoaded) {
    this.bordersVisible = true
    if (this.hasBordersToggleTarget) this.bordersToggleTarget.checked = true
    this.loadBorders()
  }

  if (!this.bordersVisible) {
    this.bordersVisible = true
    if (this.hasBordersToggleTarget) this.bordersToggleTarget.checked = true
    if (this._ds["borders"]) this._ds["borders"].show = true
  }
}

function restorePendingSelections() {
  if (!this._pendingCountryRestore?.length) return

  this._pendingCountryRestore.forEach(name => this.selectedCountries.add(name))
  this._pendingCountryRestore = null
  this._updateSelectedCountriesBbox()
  this.updateBorderColors()
  this._updateDeselectBtn()
  if (this.flightsVisible) this.fetchFlights()
  if (this.shipsVisible) this.fetchShips()
  if (this.camerasVisible) this.fetchWebcams()
  if (this.citiesVisible) this.renderCities()
  if (this.airportsVisible) this._fetchAirportData().then(() => this.renderAirports())
  this._entityListRequested = true
  this.updateEntityList()
  if (this._pendingBuildHeatmap) {
    this._pendingBuildHeatmap = false
    this._buildHeatmapActive = true
    this._initBuildHeatmap()
  }
}

function refreshSelectionScopedLayers(forceEntityList = false) {
  if (this.flightsVisible) this.fetchFlights()
  if (this.shipsVisible) this.fetchShips()
  if (this.camerasVisible) this.fetchWebcams()
  this._entityListRequested = forceEntityList || this.selectedCountries.size > 0
  this.updateEntityList()
  if (this.citiesVisible) this.renderCities()
  if (this.airportsVisible) this._fetchAirportData().then(() => this.renderAirports())
  if (this._buildHeatmapActive) this._initBuildHeatmap()
}
