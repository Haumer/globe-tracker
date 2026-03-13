import { resetTilt, resetView, viewTopDown, zoomIn, zoomOut } from "../camera"
import { getDataSource } from "../utils"

export function applyGeographyMethods(GlobeController) {
  GlobeController.prototype.toggleCities = function() {
    this.citiesVisible = this.hasCitiesToggleTarget && this.citiesToggleTarget.checked
    if (this.citiesVisible) {
      if (!this._citiesLoaded) {
        this.loadCities()
      } else {
        this.renderCities()
      }
    } else {
      this.clearCities()
    }
    this._savePrefs()
  }

  GlobeController.prototype.getCitiesDataSource = function() { return getDataSource(this.viewer, this._ds, "cities") }

  GlobeController.prototype.loadCities = async function() {
    try {
      // Fetch city points and urban area polygons in parallel
      const [placesRes, urbanRes] = await Promise.all([
        fetch("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places_simple.geojson"),
        fetch("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_urban_areas.geojson"),
      ])

      const placesData = await placesRes.json()
      const urbanData = await urbanRes.json()

      this._citiesData = placesData.features
        .filter(f => f.geometry && f.properties)
        .map(f => ({
          name: f.properties.name || f.properties.nameascii || "",
          country: f.properties.adm0name || f.properties.sov0name || "",
          population: f.properties.pop_max || f.properties.pop_min || 0,
          lat: f.geometry.coordinates[1],
          lng: f.geometry.coordinates[0],
          capital: f.properties.adm0cap === 1,
          rank: f.properties.rank_max || 0,
        }))
        .filter(c => c.name && c.population > 100000)
        .sort((a, b) => b.population - a.population)

      this._urbanAreas = urbanData.features
        .filter(f => f.geometry)
        .map(f => ({
          coords: f.geometry.coordinates,
          type: f.geometry.type,
          area: f.properties.area_sqkm || 0,
        }))


      this._citiesLoaded = true
      this.renderCities()
    } catch (e) {
      console.error("Failed to load cities:", e, e.message, e.stack)
    }
  }

  GlobeController.prototype.clearCities = function() {
    const ds = this._ds["cities"]
    if (ds) {
      this._cityEntities.forEach(e => ds.entities.remove(e))
    }
    this._cityEntities = []
  }

  GlobeController.prototype.renderCities = async function() {
    const Cesium = window.Cesium
    this.clearCities()
    if (!this.citiesVisible || this._citiesData.length === 0) return

    const dataSource = this.getCitiesDataSource()
    dataSource.show = true
    const hasFilter = this.hasActiveFilter()

    let cities = this._citiesData

    // Filter to selected countries if active
    if (this.selectedCountries.size > 0) {
      cities = cities.filter(c =>
        this.selectedCountries.has(c.country)
      )
    } else if (hasFilter && this._activeCircle) {
      cities = cities.filter(c => this.pointPassesFilter(c.lat, c.lng))
    }

    // Limit to top 500 cities to avoid overload
    cities = cities.slice(0, 500)

    // Sample terrain heights if terrain is enabled
    let terrainHeights = null
    if (this.terrainEnabled && this.viewer.terrainProvider && !(this.viewer.terrainProvider instanceof Cesium.EllipsoidTerrainProvider)) {
      const positions = cities.map(c => Cesium.Cartographic.fromDegrees(c.lng, c.lat))
      try {
        terrainHeights = await Cesium.sampleTerrainMostDetailed(this.viewer.terrainProvider, positions)
      } catch (e) {
        console.warn("Terrain sampling failed for cities:", e)
      }
    }

    // Bail if cities were toggled off while awaiting terrain
    if (!this.citiesVisible) return

    const maxPop = cities.length > 0 ? cities[0].population : 1

    cities.forEach((city, idx) => {
      try {
        const popRatio = city.population / maxPop
        const pixelSize = city.capital ? 7 : Math.max(3, Math.round(popRatio * 6 + 2))

        const color = city.capital
          ? Cesium.Color.fromCssColorString("#ffd54f")
          : Cesium.Color.fromCssColorString("#e0e0e0")

        const height = terrainHeights ? terrainHeights[idx].height || 0 : 0

        const entity = dataSource.entities.add({
          position: Cesium.Cartesian3.fromDegrees(city.lng, city.lat, height),
          point: {
            pixelSize,
            color: color.withAlpha(0.9),
            outlineColor: color.withAlpha(0.5),
            outlineWidth: 1,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
          label: {
            text: city.name,
            font: city.capital ? "bold 15px JetBrains Mono, monospace" : "13px JetBrains Mono, monospace",
            fillColor: Cesium.Color.WHITE.withAlpha(0.95),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            pixelOffset: new Cesium.Cartesian2(0, -10),
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 1e7, 0.3),
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
        })
        this._cityEntities.push(entity)
      } catch (e) {
        console.warn(`City entity failed: ${city.name}`, e.message)
      }
    })

    // Render urban area polygons
    if (this._urbanAreas && this._urbanAreas.length > 0) {
      const urbanColor = Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.35)
      const urbanOutline = Cesium.Color.fromCssColorString("#ffcc80").withAlpha(0.6)

      // If countries selected, build a bbox for quick filtering
      const filterBbox = this._selectedCountriesBbox
      const hasCircle = !!this._activeCircle

      this._urbanAreas.forEach((urban, i) => {
        const rings = urban.type === "Polygon" ? [urban.coords] : urban.type === "MultiPolygon" ? urban.coords : []

        for (const polyCoords of rings) {
          const outerRing = polyCoords[0]
          if (!outerRing || outerRing.length < 3) continue

          // Quick centroid for filtering
          let cLat = 0, cLng = 0
          for (const coord of outerRing) { cLng += coord[0]; cLat += coord[1] }
          cLat /= outerRing.length
          cLng /= outerRing.length

          // Filter: if countries selected, check bbox then point-in-country
          if (this.selectedCountries.size > 0) {
            if (filterBbox && (cLat < filterBbox.minLat || cLat > filterBbox.maxLat ||
                cLng < filterBbox.minLng || cLng > filterBbox.maxLng)) continue
            if (!this._pointInSelectedCountries(cLat, cLng)) continue
          } else if (hasCircle) {
            if (!this.pointPassesFilter(cLat, cLng)) continue
          }

          const positions = outerRing.map(c => Cesium.Cartesian3.fromDegrees(c[0], c[1]))

          try {
            const entity = dataSource.entities.add({
              polygon: {
                hierarchy: positions,
                material: urbanColor,
                outline: true,
                outlineColor: urbanOutline,
                outlineWidth: 1,
                classificationType: Cesium.ClassificationType.BOTH,
              },
            })
            this._cityEntities.push(entity)
          } catch (e) {
            // skip failed urban polygons
          }
        }
      })
    }
  }

  GlobeController.prototype.toggleCountrySelect = function() {
    this.countrySelectMode = !this.countrySelectMode
    if (this.countrySelectMode) {
      // Auto-enable borders
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
      this.viewer.canvas.style.cursor = "pointer"
    } else {
      this.viewer.canvas.style.cursor = ""
    }
    // Update button state
    const btn = document.getElementById("country-select-btn")
    if (btn) btn.classList.toggle("active", this.countrySelectMode)
  }

  // ── Terrain ──────────────────────────────────────────────

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
    // Reset exaggeration slider to match
    if (this.hasTerrainExaggerationTarget) {
      if (!this.terrainEnabled) {
        this.terrainExaggerationTarget.value = 1
        const label = this.terrainExaggerationTarget.closest(".sb-slider-row")?.querySelector(".sb-slider-val")
        if (label) label.textContent = "1×"
      }
    }
    this._savePrefs()
  }

  GlobeController.prototype.setTerrainExaggeration = function() {
    const val = this.hasTerrainExaggerationTarget ? parseFloat(this.terrainExaggerationTarget.value) : 1
    this.viewer.scene.verticalExaggeration = val
    const label = this.terrainExaggerationTarget?.closest(".sb-slider-row")?.querySelector(".sb-slider-val")
    if (label) label.textContent = `${val}×`
    this._savePrefs()
  }

  GlobeController.prototype.toggleBuildings = async function() {
    const Cesium = window.Cesium
    const mode = this.hasBuildingsSelectTarget ? this.buildingsSelectTarget.value : "off"
    this.buildingsEnabled = mode !== "off"

    // Hide both tilesets first
    if (this._buildingsTileset) this._buildingsTileset.show = false
    if (this._googleTileset) this._googleTileset.show = false

    if (mode === "osm") {
      if (!this._buildingsTileset) {
        try {
          this._buildingsTileset = await Cesium.createOsmBuildingsAsync()
          this.viewer.scene.primitives.add(this._buildingsTileset)
        } catch (e) {
          console.warn("Failed to load OSM buildings:", e)
          if (this.hasBuildingsSelectTarget) this.buildingsSelectTarget.value = "off"
          this.buildingsEnabled = false
          return
        }
      }
      this._buildingsTileset.show = true
    } else if (mode === "google") {
      if (!this._googleTileset) {
        try {
          this._googleTileset = await Cesium.Cesium3DTileset.fromIonAssetId(2275207)
          // Improve visual quality
          this._googleTileset.maximumScreenSpaceError = 8
          this.viewer.scene.primitives.add(this._googleTileset)
        } catch (e) {
          console.warn("Failed to load Google Photorealistic 3D Tiles:", e)
          if (this.hasBuildingsSelectTarget) this.buildingsSelectTarget.value = "off"
          this.buildingsEnabled = false
          return
        }
      }
      this._googleTileset.show = true
      // Hide globe base imagery to avoid z-fighting with Google's ground textures
      this.viewer.scene.globe.show = false
    }

    // Restore globe when not using Google tiles
    if (mode !== "google") {
      this.viewer.scene.globe.show = true
    }
    this._savePrefs()
  }

  GlobeController.prototype.toggleBorders = function() {
    this.bordersVisible = this.hasBordersToggleTarget && this.bordersToggleTarget.checked
    if (this.bordersVisible && !this.bordersLoaded) {
      this.loadBorders()
    }
    if (this._ds["borders"]) {
      this._ds["borders"].show = this.bordersVisible
    }
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
      const wallHeight = 10000

      const defaultColor = Cesium.Color.fromCssColorString("#4fc3f7").withAlpha(0.15)
      const defaultOutline = Cesium.Color.fromCssColorString("#4fc3f7").withAlpha(0.4)

      geojson.features.forEach((feature, fi) => {
        const geom = feature.geometry
        if (!geom) return

        const countryName = feature.properties?.NAME || feature.properties?.name || `Unknown-${fi}`

        const rings = []
        if (geom.type === "Polygon") {
          rings.push(geom.coordinates[0])
        } else if (geom.type === "MultiPolygon") {
          geom.coordinates.forEach(poly => rings.push(poly[0]))
        }

        const countryEntityList = this._countryEntities.get(countryName) || []

        rings.forEach((ring, ri) => {
          if (ring.length < 3) return

          const positions = ring.map(coord =>
            Cesium.Cartesian3.fromDegrees(coord[0], coord[1])
          )
          const heights = new Array(positions.length).fill(wallHeight)

          const entityId = `border-${fi}-${ri}`
          const entity = dataSource.entities.add({
            id: entityId,
            wall: {
              positions: positions,
              maximumHeights: heights,
              minimumHeights: new Array(positions.length).fill(0),
              material: defaultColor,
              outline: true,
              outlineColor: defaultOutline,
              outlineWidth: 1,
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

      // Restore pending country selections from saved preferences
      if (this._pendingCountryRestore && this._pendingCountryRestore.length > 0) {
        this._pendingCountryRestore.forEach(name => {
          this.selectedCountries.add(name)
        })
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
        // Init build heatmap if it was pending
        if (this._pendingBuildHeatmap) {
          this._pendingBuildHeatmap = false
          this._buildHeatmapActive = true
          this._initBuildHeatmap()
        }
      }
    } catch (e) {
      console.error("Failed to load borders:", e)
    }
  }

  GlobeController.prototype.toggleCountrySelection = function(countryName) {
    if (this.selectedCountries.has(countryName)) {
      this.selectedCountries.delete(countryName)
    } else {
      this.selectedCountries.add(countryName)
    }
    this._activeCircle = null // country click overrides circle filter
    this._updateSelectedCountriesBbox()
    this.updateBorderColors()
    this._updateDeselectBtn()

    // Re-fetch active layers with updated filter
    if (this.flightsVisible) this.fetchFlights()
    if (this.shipsVisible) this.fetchShips()
    if (this.camerasVisible) this.fetchWebcams()
    this._entityListRequested = this.selectedCountries.size > 0
    this.updateEntityList()
    if (this.citiesVisible) this.renderCities()
    if (this.airportsVisible) this._fetchAirportData().then(() => this.renderAirports())
    if (this._buildHeatmapActive) this._initBuildHeatmap()
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

    // Re-fetch with no filter (back to viewport)
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
    const defaultColor = Cesium.Color.fromCssColorString("#4fc3f7").withAlpha(0.15)
    const defaultOutline = Cesium.Color.fromCssColorString("#4fc3f7").withAlpha(0.4)
    const selectedColor = Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.35)
    const selectedOutline = Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.8)

    for (const [countryName, entities] of this._countryEntities) {
      const isSelected = this.selectedCountries.has(countryName)
      entities.forEach(entity => {
        entity.wall.material = isSelected ? selectedColor : defaultColor
        entity.wall.outlineColor = isSelected ? selectedOutline : defaultOutline
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

    document.getElementById("draw-circle-btn")?.addEventListener("click", () => this.enterDrawMode())
    document.getElementById("clear-selection-btn")?.addEventListener("click", () => this.clearCountrySelection())
    document.getElementById("area-report-btn")?.addEventListener("click", () => this._generateAreaReport())

    this.detailPanelTarget.style.display = ""
  }

  // ── Draw Circle Tool ────────────────────────────────────

  GlobeController.prototype.enterDrawMode = function() {
    // Auto-enable borders if needed
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
    this.drawMode = true
    this._drawCenter = null
    this.removeDrawCircle()
    this.viewer.scene.screenSpaceCameraController.enableRotate = false
    this.viewer.canvas.style.cursor = "crosshair"

    // Show instruction
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
        },
      })
    }

    // Update instruction with radius
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

  GlobeController.prototype.selectCountriesInCircle = function(center, radius) {
    for (const feature of this._countryFeatures) {
      const geom = feature.geometry
      const name = feature.properties?.NAME || feature.properties?.name
      if (!geom || !name) continue

      const polygons = geom.type === "Polygon" ? [geom.coordinates] : geom.type === "MultiPolygon" ? geom.coordinates : []

      let intersects = false
      for (const poly of polygons) {
        // Check if any vertex of the polygon is inside the circle
        for (const coord of poly[0]) {
          const dist = this.haversineDistance(center, { lat: coord[1], lng: coord[0] })
          if (dist <= radius) {
            intersects = true
            break
          }
        }
        if (intersects) break

        // Also check if the circle center is inside the polygon
        if (this.pointInPolygon(center.lat, center.lng, poly[0])) {
          intersects = true
          break
        }
      }

      if (intersects && this._countryEntities.has(name)) {
        this.selectedCountries.add(name)
      }
    }

    // Store circle as active filter for flights/ships
    this._activeCircle = { center, radius }
    this._updateSelectedCountriesBbox()

    this.updateBorderColors()
    this.showBorderDetail()

    // Re-fetch active layers with new filter
    if (this.flightsVisible) this.fetchFlights()
    if (this.shipsVisible) this.fetchShips()
    if (this.camerasVisible) this.fetchWebcams()
    if (this.citiesVisible) this.renderCities()
    if (this.airportsVisible) this._fetchAirportData().then(() => this.renderAirports())
    this._entityListRequested = true
    this.updateEntityList()
    if (this._buildHeatmapActive) this._initBuildHeatmap()
  }

  GlobeController.prototype.getBordersDataSource = function() { return getDataSource(this.viewer, this._ds, "borders") }

  // ── Camera Controls ──────────────────────────────────────

  GlobeController.prototype.resetView = function() { resetView(this.viewer) }

  GlobeController.prototype.viewTopDown = function() { viewTopDown(this.viewer) }

  GlobeController.prototype.resetTilt = function() { resetTilt(this.viewer) }

  GlobeController.prototype.zoomIn = function() { zoomIn(this.viewer) }

  GlobeController.prototype.zoomOut = function() { zoomOut(this.viewer) }

  // ── Recording ──────────────────────────────────────────────

  GlobeController.prototype.toggleRecording = function() {
    if (this._mediaRecorder && this._mediaRecorder.state === "recording") {
      this._stopRecording()
    } else {
      this._startRecording()
    }
  }

  GlobeController.prototype._startRecording = function() {
    const canvas = this.viewer.scene.canvas
    const stream = canvas.captureStream(30)

    // Try to use WebM VP9, fall back to VP8
    const mimeType = MediaRecorder.isTypeSupported("video/webm;codecs=vp9")
      ? "video/webm;codecs=vp9"
      : "video/webm;codecs=vp8"

    this._recordedChunks = []
    this._mediaRecorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: 8_000_000 })

    this._mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) this._recordedChunks.push(e.data)
    }

    this._mediaRecorder.onstop = () => {
      const blob = new Blob(this._recordedChunks, { type: mimeType })
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `globe-${new Date().toISOString().slice(0, 19).replace(/:/g, "-")}.webm`
      a.click()
      URL.revokeObjectURL(url)
      this._recordedChunks = []
    }

    this._mediaRecorder.start(1000) // collect data every second
    this._recordingStart = Date.now()

    // Update UI
    if (this.hasRecordBtnTarget) this.recordBtnTarget.classList.add("recording")
    if (this.hasRecordIconTarget) this.recordIconTarget.className = "fa-solid fa-stop"

    // Update recording timer in the stats bar
    this._recordingTimerInterval = setInterval(() => this._updateRecordingTimer(), 1000)
  }

  GlobeController.prototype._stopRecording = function() {
    if (this._mediaRecorder) {
      this._mediaRecorder.stop()
      this._mediaRecorder = null
    }
    if (this._recordingTimerInterval) {
      clearInterval(this._recordingTimerInterval)
      this._recordingTimerInterval = null
    }
    if (this.hasRecordBtnTarget) this.recordBtnTarget.classList.remove("recording")
    if (this.hasRecordIconTarget) this.recordIconTarget.className = "fa-solid fa-circle"

    // Remove timer badge
    const badge = document.getElementById("record-timer")
    if (badge) badge.remove()
  }

  GlobeController.prototype._updateRecordingTimer = function() {
    const elapsed = Math.floor((Date.now() - this._recordingStart) / 1000)
    const min = String(Math.floor(elapsed / 60)).padStart(2, "0")
    const sec = String(elapsed % 60).padStart(2, "0")

    let badge = document.getElementById("record-timer")
    if (!badge) {
      badge = document.createElement("div")
      badge.id = "record-timer"
      document.getElementById("controls-bar")?.appendChild(badge)
    }
    badge.textContent = `${min}:${sec}`
  }

  GlobeController.prototype.takeScreenshot = function() {
    const canvas = this.viewer.scene.canvas
    // Force a render to ensure we capture the current frame
    this.viewer.scene.render()

    canvas.toBlob((blob) => {
      if (!blob) return
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `globe-${new Date().toISOString().slice(0, 19).replace(/:/g, "-")}.png`
      a.click()
      URL.revokeObjectURL(url)
    }, "image/png")
  }

  GlobeController.prototype.toggleTrains = function() {
    // Placeholder
  }

  // ── Area Reports ───────────────────────────────────────────

  GlobeController.prototype._generateAreaReport = async function() {
    const container = document.getElementById("area-report-content")
    if (!container) return

    const bounds = this.getFilterBounds()
    if (!bounds) {
      container.innerHTML = `<div style="font:400 10px monospace;color:#888;padding:8px 0;">Select a country or draw a circle first.</div>`
      return
    }

    container.innerHTML = `<div style="font:400 10px monospace;color:#888;padding:8px 0;">Generating report...</div>`

    try {
      const params = new URLSearchParams(bounds)
      const resp = await fetch(`/api/area_report?${params}`)
      if (!resp.ok) { container.innerHTML = ""; return }
      const report = await resp.json()
      container.innerHTML = this._renderAreaReport(report)
    } catch (e) {
      console.warn("Area report failed:", e)
      container.innerHTML = ""
    }
  }

  GlobeController.prototype._renderAreaReport = function(r) {
    let html = `<div style="margin-top:10px;border-top:1px solid #333;padding-top:8px;">`
    html += `<div style="font:600 9px monospace;color:#4fc3f7;letter-spacing:1px;text-transform:uppercase;margin-bottom:8px;">AREA REPORT</div>`

    // Flights
    if (r.flights) {
      const f = r.flights
      html += this._reportSection("fa-plane", "#4fc3f7", "Aviation", [
        `${f.total} flights (${f.military} military, ${f.civilian} civilian)`,
        f.emergency > 0 ? `<span style="color:#f44336;">${f.emergency} emergency</span>` : null,
        f.top_countries ? `Top: ${Object.entries(f.top_countries).map(([c, n]) => `${c} (${n})`).join(", ")}` : null,
      ])
    }

    // Earthquakes
    if (r.earthquakes) {
      const e = r.earthquakes
      html += this._reportSection("fa-house-crack", "#ff7043", "Seismic (7d)", [
        `${e.total} earthquakes, avg M${e.avg_magnitude}`,
        `Strongest: M${e.max_magnitude} ${e.max_title}`,
        e.tsunami_warnings > 0 ? `<span style="color:#f44336;">${e.tsunami_warnings} tsunami warnings</span>` : null,
      ])
    }

    // Fires
    if (r.fires) {
      const f = r.fires
      html += this._reportSection("fa-fire", "#ff5722", `Active Fires (48h)`, [
        `${f.total} hotspots${f.high_confidence > 0 ? ` (${f.high_confidence} high confidence)` : ""}`,
        f.max_frp ? `Max fire power: ${f.max_frp} MW` : null,
        f.satellites?.length > 0 ? `Detected by: ${f.satellites.join(", ")}` : null,
      ])
    }

    // Conflicts
    if (r.conflicts) {
      const c = r.conflicts
      html += this._reportSection("fa-crosshairs", "#f44336", "Conflicts", [
        `${c.total} events, ${c.casualties} casualties`,
        c.conflicts.join(", "),
      ])
    }

    // Jamming
    if (r.jamming) {
      const j = r.jamming
      html += this._reportSection("fa-satellite-dish", "#ff9800", "GPS Jamming", [
        j.high_cells > 0 ? `${j.high_cells} high-intensity cells` : null,
        j.medium_cells > 0 ? `${j.medium_cells} medium-intensity cells` : null,
      ])
    }

    // Infrastructure
    if (r.infrastructure) {
      const i = r.infrastructure
      const infraItems = [
        `${i.power_plants} power plants (${i.total_capacity_mw.toLocaleString()} MW)`,
        i.nuclear > 0 ? `<span style="color:#fdd835;">${i.nuclear} nuclear</span>` : null,
        i.submarine_cables > 0 ? `${i.submarine_cables} submarine cables` : null,
        i.fuel_mix ? Object.entries(i.fuel_mix).map(([f, n]) => `${f}: ${n}`).join(", ") : null,
      ]
      if (i.country_shares && i.country_shares.length > 0) {
        infraItems.push(`<span style="color:#fdd835;font-weight:600;">National capacity share:</span>`)
        i.country_shares.forEach(s => {
          infraItems.push(`${s.country}: ${s.area_mw.toLocaleString()} / ${s.national_mw.toLocaleString()} MW (${s.pct}%)`)
        })
      }
      html += this._reportSection("fa-bolt", "#fdd835", "Infrastructure", infraItems)
    }

    // Anomalies
    if (r.anomalies && r.anomalies.length > 0) {
      const items = r.anomalies.map(a => `<span style="color:${a.color};">${a.title}</span>`)
      html += this._reportSection("fa-triangle-exclamation", "#f44336", "Active Anomalies", items)
    }

    // No data
    const sections = [r.flights, r.earthquakes, r.fires, r.conflicts, r.jamming, r.infrastructure, r.anomalies]
    if (sections.every(s => !s)) {
      html += `<div style="font:400 10px monospace;color:#666;padding:4px 0;">No significant data in this area.</div>`
    }

    html += `</div>`
    return html
  }

  GlobeController.prototype._reportSection = function(icon, color, title, items) {
    const filtered = items.filter(Boolean)
    if (filtered.length === 0) return ""
    return `<div style="margin-bottom:8px;padding:5px 7px;background:rgba(255,255,255,0.03);border-left:3px solid ${color};border-radius:0 4px 4px 0;">
      <div style="display:flex;align-items:center;gap:5px;margin-bottom:3px;">
        <i class="fa-solid ${icon}" style="color:${color};font-size:10px;"></i>
        <span style="font:600 10px monospace;color:${color};">${title}</span>
      </div>
      ${filtered.map(item => `<div style="font:400 10px monospace;color:#aaa;padding:1px 0;">${item}</div>`).join("")}
    </div>`
  }

  // ── News Events ────────────────────────────────────────────

}
