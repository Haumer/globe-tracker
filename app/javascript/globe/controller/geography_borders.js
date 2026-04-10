import { getDataSource } from "globe/utils"

const COUNTRY_BORDER_URLS = [
  "/api/geography/boundaries?dataset=countries",
  "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson",
]

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
    this._syncRegionalEconomyMap?.()
    this._savePrefs()
  }

  GlobeController.prototype.loadBorders = async function() {
    if (this._bordersLoadPromise) return this._bordersLoadPromise

    const Cesium = window.Cesium

    this._bordersLoadPromise = (async () => {
      this._toast("Loading borders...")
      try {
        const geojson = await fetchBoundaryDataset(COUNTRY_BORDER_URLS)
        if (!geojson?.features?.length) throw new Error("Country boundary dataset unavailable")

        this._countryFeatures = geojson.features
        this._borderCountryMap.clear()
        this._countryEntities.clear()
        this._countryFillEntities.clear()

        const dataSource = this.getBordersDataSource()
        dataSource.entities.removeAll()

        renderCountryBorders.call(this, dataSource, geojson.features, Cesium)

        this.bordersLoaded = true
        this._ds["borders"].show = this.bordersVisible
        this._toastHide()
        restorePendingSelections.call(this)
        this._requestRender?.()
      } catch (error) {
        console.error("Failed to load borders:", error)
        this._toast("Failed to load borders", "error")
      } finally {
        this._bordersLoadPromise = null
      }
    })()

    return this._bordersLoadPromise
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

  GlobeController.prototype.setCountrySelection = function(countryNames = [], options = {}) {
    const names = [...new Set((countryNames || []).filter(Boolean))]
    const showBorders = options.showBorders !== false && names.length > 0
    const refresh = options.refresh !== false

    this._pendingCountryRestore = names.length > 0 ? names : null
    this._selectedCountriesUseHull = options.useHull !== false
    if (showBorders) ensureBordersVisible.call(this)

    this.selectedCountries.clear()
    names.forEach(name => this.selectedCountries.add(name))
    this._activeCircle = null
    this.countrySelectMode = false
    this.viewer.canvas.style.cursor = ""
    const btn = document.getElementById("country-select-btn")
    if (btn) btn.classList.remove("active")
    this.removeDrawCircle()

    if (this.selectedCountries.size > 0 && this._countryFeatures.length > 0) {
      this._updateSelectedCountriesBbox()
    } else {
      this._selectedCountriesBbox = null
      this._selectedCountriesHull = null
    }

    this.updateBorderColors()
    this._updateDeselectBtn()
    if (refresh) refreshSelectionScopedLayers.call(this, this.selectedCountries.size > 0)
    if (options.showDetail) this.showBorderDetail()
    this._savePrefs()
  }

  GlobeController.prototype.clearCountrySelection = function() {
    this.selectedCountries.clear()
    this._selectedCountriesBbox = null
    this._selectedCountriesHull = null
    this._activeCircle = null
    this._pendingCountryRestore = null
    this._selectedCountriesUseHull = true
    this.countrySelectMode = false
    this.viewer.canvas.style.cursor = ""
    const btn = document.getElementById("country-select-btn")
    if (btn) btn.classList.remove("active")
    this.removeDrawCircle()
    this.updateBorderColors()
    this._updateDeselectBtn()
    this.closeDetail()
    refreshSelectionScopedLayers.call(this)
    this._savePrefs()
  }

  GlobeController.prototype._updateDeselectBtn = function() {
    if (this.hasDeselectAllBtnTarget) {
      this.deselectAllBtnTarget.style.display = this.selectedCountries.size > 0 ? "" : "none"
    }
  }

  GlobeController.prototype.updateBorderColors = function() {
    const Cesium = window.Cesium
    const hasSelection = this.selectedCountries.size > 0
    const adminOverlayActive = Array.isArray(this._regionalAdminEconomyEntities) && this._regionalAdminEconomyEntities.length > 0
    const districtOverlayActive = Array.isArray(this._regionalDistrictEconomyEntities) && this._regionalDistrictEconomyEntities.length > 0
    const subnationalOverlayActive = adminOverlayActive || districtOverlayActive
    const region = this._regionalEconomyRegion?.()
    const normalRegionalView = !!(region && this._regionalEconomyMapView?.(region) === "off")
    const defaultColor = hasSelection
      ? Cesium.Color.fromCssColorString("#5f7387").withAlpha(0.38)
      : Cesium.Color.fromCssColorString("#7fd8ff").withAlpha(0.78)
    const selectedColor = Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.95)
    const defaultFillColor = hasSelection && !normalRegionalView
      ? (subnationalOverlayActive
          ? Cesium.Color.TRANSPARENT
          : Cesium.Color.fromCssColorString("#0b0f14").withAlpha(0.7))
      : Cesium.Color.TRANSPARENT
    const selectedFillColor = hasSelection && !normalRegionalView
      ? (subnationalOverlayActive
          ? Cesium.Color.TRANSPARENT
          : Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.18))
      : Cesium.Color.TRANSPARENT

    for (const [countryName, entities] of this._countryEntities) {
      const isSelected = this.selectedCountries.has(countryName)
      entities.forEach(entity => {
        entity.polyline.material = isSelected ? selectedColor : defaultColor
      })
    }

    for (const [countryName, entities] of this._countryFillEntities) {
      const isSelected = this.selectedCountries.has(countryName)
      const economyStyle = isSelected && !subnationalOverlayActive && !normalRegionalView ? this._regionalEconomyBorderStyles?.[countryName] : null
      entities.forEach(entity => {
        entity.show = hasSelection
        entity.polygon.material = isSelected
          ? (economyStyle?.fillColor || selectedFillColor)
          : defaultFillColor
      })
    }

    this._requestRender?.()
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

async function fetchBoundaryDataset(urls) {
  for (const url of urls) {
    try {
      const response = await fetch(url, url.startsWith("/") ? { credentials: "same-origin" } : undefined)
      if (!response.ok) continue

      const geojson = await response.json()
      if (geojson?.type === "FeatureCollection" && Array.isArray(geojson.features)) return geojson
    } catch (error) {
      console.warn(`Boundary fetch failed for ${url}:`, error)
    }
  }

  return null
}

function renderCountryBorders(dataSource, features, Cesium) {
  const defaultColor = Cesium.Color.fromCssColorString("#7fd8ff").withAlpha(0.78)
  const defaultFillColor = Cesium.Color.TRANSPARENT

  features.forEach((feature, featureIndex) => {
    const geom = feature.geometry
    if (!geom) return

    const countryName = feature.properties?.NAME || feature.properties?.name || `Unknown-${featureIndex}`
    const rings = []
    if (geom.type === "Polygon") rings.push(geom.coordinates[0])
    else if (geom.type === "MultiPolygon") geom.coordinates.forEach(poly => rings.push(poly[0]))

    const countryEntityList = this._countryEntities.get(countryName) || []
    const countryFillEntityList = this._countryFillEntities.get(countryName) || []
    rings.forEach((ring, ringIndex) => {
      if (!Array.isArray(ring) || ring.length < 3) return

      const positions = ring
        .filter(coord => Array.isArray(coord) && coord.length >= 2)
        .map(coord => Cesium.Cartesian3.fromDegrees(coord[0], coord[1]))
      if (positions.length < 2) return

      const fillEntityId = `border-fill-${featureIndex}-${ringIndex}`
      const fillEntity = dataSource.entities.add({
        id: fillEntityId,
        show: false,
        polygon: {
          hierarchy: new Cesium.PolygonHierarchy(positions),
          material: defaultFillColor,
          clampToGround: true,
          classificationType: Cesium.ClassificationType.BOTH,
          outline: false,
        },
      })
      const entityId = `border-${featureIndex}-${ringIndex}`
      const entity = dataSource.entities.add({
        id: entityId,
        polyline: {
          positions,
          width: 2.2,
          material: defaultColor,
          clampToGround: true,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })

      this._borderCountryMap.set(fillEntityId, { name: countryName })
      this._borderCountryMap.set(entityId, { name: countryName })
      countryFillEntityList.push(fillEntity)
      countryEntityList.push(entity)
    })

    this._countryFillEntities.set(countryName, countryFillEntityList)
    this._countryEntities.set(countryName, countryEntityList)
  })
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
  refreshSelectionScopedLayers.call(this, true)
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
  if (this.newsVisible) this.fetchNews?.()
  if (this.weatherVisible) this._renderWeatherAlerts?.()
  if (this.outagesVisible) this._renderOutages?.({ summary: this._outageData || [], events: [] })
  if (this.financialVisible) this._renderCommodities?.()
  this._entityListRequested = forceEntityList || this.selectedCountries.size > 0
  this.updateEntityList()
  if (this.citiesVisible) this.renderCities()
  if (this.airportsVisible) this._fetchAirportData().then(() => this.renderAirports())
  if (this.portsVisible) this.renderPorts?.()
  if (this.powerPlantsVisible) this.renderPowerPlants?.()
  if (this.commoditySitesVisible) this.renderCommoditySites?.()
  if (this.pipelinesVisible) this._renderPipelines?.(this._pipelineData || [])
  if (this.notamsVisible) this.renderNotams?.()
  if (this._buildHeatmapActive) this._initBuildHeatmap()
}
