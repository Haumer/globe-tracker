import { Controller } from "@hotwired/stimulus"
import { screenToLatLng, haversineDistance, pointInPolygon, findCountryAtPoint, createPlaneIcon, createSatelliteIcon, getDataSource } from "../globe/utils"
import { saveCamera, restoreCamera, getViewportBounds, resetView, viewTopDown, resetTilt, zoomIn, zoomOut } from "../globe/camera"
import { renderDetailHTML, detailField } from "../globe/details"

export default class extends Controller {
  static values = { cesiumToken: String, signedIn: Boolean, savedPrefs: Object }
  static targets = ["flightsToggle", "trainsToggle", "camerasToggle", "civilianToggle", "militaryToggle", "detailPanel", "detailContent", "flightCount", "trailsToggle", "satStationsToggle", "satStarlinkToggle", "satGpsToggle", "satWeatherToggle", "satOrbitsToggle", "satHeatmapToggle", "buildHeatmapToggle", "shipsToggle", "bordersToggle", "citiesToggle", "airportsToggle", "earthquakesToggle", "naturalEventsToggle", "terrainToggle", "terrainExaggeration", "buildingsToggle", "buildingsSelect", "searchInput", "searchResults", "searchClear", "entityListPanel", "entityListHeader", "entityListContent", "entityFlightCount", "entityShipCount", "entitySatCount", "sidebar", "statsBar", "statFlights", "statSats", "statShips", "statEvents", "statClock", "airlineFilter", "airlineChips", "entityAirlineBar", "entityAirlineChips", "recordBtn", "recordIcon", "deselectAllBtn", "qlFlights", "qlSatellites", "qlShips", "qlCities", "qlAirports", "qlBorders", "qlTerrain", "qlEarthquakes", "qlEvents", "qlCameras", "flightsBadge", "satBadge", "timelineBar", "timelinePlayBtn", "timelinePlayIcon", "timelineScrubber", "timelineTimeStart", "timelineTimeEnd", "timelineCursorDate", "timelineCursorTime", "timelineCursorDisplay", "timelineSpeed", "timelineLiveBadge", "gpsJammingToggle", "qlGpsJamming", "newsToggle", "qlNews", "newsArcControls", "newsArcFrom", "newsArcTo", "newsArcMax", "newsArcsToggle", "newsBlobsToggle", "newsFeedPanel", "newsFeedCount", "newsFeedContent", "newsArticlesPane", "newsFlowsPane", "newsArticleCatFilter", "newsArticleSearch", "newsArticleList", "threatsPanel", "threatsCount", "threatsContent", "cablesToggle", "qlCables", "outagesToggle", "qlOutages", "selectionTray", "selectionTrayItems", "powerPlantsToggle", "qlPowerPlants", "conflictsToggle", "qlConflicts", "trafficToggle", "qlTraffic", "trafficArcsToggle", "trafficBlobsToggle", "trafficArcControls", "notamsToggle", "qlNotams"]

  connect() {
    this.flightsVisible = false
    this.flightInterval = null
    this.flightData = new Map()
    this.selectedFlights = new Set()
    this.selectedShips = new Set()
    this.selectedSats = new Set()
    this._selectionBoxEntities = new Map() // key: "flight-id"|"ship-mmsi"|"sat-noradId" → entity
    this._focusedSelection = null // { type: "flight"|"ship"|"sat", id: string }
    this._selBoxImgGreen = null
    this._selBoxImgYellow = null
    this.animationFrame = null
    this.lastAnimTime = null
    this.trailsVisible = false
    this.trailHistory = new Map()
    this.trackedFlightId = null
    this.showCivilian = true
    this.showMilitary = true
    this.satelliteData = []
    this._loadedSatCategories = new Set()
    this.satelliteEntities = new Map()
    this.satCategoryVisible = { stations: false, starlink: false, "gps-ops": false, glonass: false, galileo: false, weather: false, resource: false, science: false, military: false, analyst: false, geo: false, iridium: false, oneweb: false, planet: false, spire: false, gnss: false, tdrss: false, radar: false, sbas: false, cubesat: false, amateur: false, sarsat: false, "last-30-days": false, beidou: false, molniya: false, geodetic: false, dmc: false, argos: false, intelsat: false, ses: false, "x-comm": false, globalstar: false }
    this.satOrbitsVisible = false
    this.satOrbitEntities = new Map()
    this.selectedSatNoradId = null
    this._satFootprintEntities = []
    this.satHeatmapVisible = false
    this._heatmapEntities = []
    this._heatmapGrid = new Map()       // key "row,col" → { lat, lng, hits: [timestamp, ...] }
    this._heatmapHitLifeSec = 60        // each hit layer lasts 60s
    this._heatmapLastUpdate = 0         // throttle: timestamp of last computation
    this._sweepEntities = []             // live satellite footprint hexes on country
    this._lastSatPositions = []          // cached for sweep rendering between recomputes
    this._buildHeatmapActive = false     // "Build Heatmap" mode — country hex grid that accumulates
    this._buildHeatmapBaseEntities = []  // flat hex grid entities covering selected countries
    this._buildHeatmapGrid = new Map()   // key "row,col" → { lat, lng, hits: 0, entity: null }
    this.shipsVisible = false
    this.shipData = new Map()
    this.shipInterval = null
    this.bordersVisible = false
    this.bordersLoaded = false
    this.selectedCountries = new Set()
    this._selectedCountriesBbox = null
    this._borderCountryMap = new Map()
    this._countryEntities = new Map()
    this._countryFeatures = []          // raw GeoJSON features for hit testing
    this.citiesVisible = false
    this._citiesData = []
    this._urbanAreas = []
    this._citiesLoaded = false
    this._cityEntities = []
    this.earthquakesVisible = false
    this._earthquakeData = []
    this._earthquakeEntities = []
    this.naturalEventsVisible = false
    this._naturalEventData = []
    this._naturalEventEntities = []
    this._eventsInterval = null
    this.camerasVisible = false
    this.gpsJammingVisible = false
    this._gpsJammingEntities = []
    this._gpsJammingInterval = null
    this.newsVisible = false
    this.newsArcsVisible = true
    this.newsBlobsVisible = true
    this._newsData = []
    this._newsEntities = []
    this._newsArcEntities = []
    this._newsInterval = null
    this._newsActiveTab = "articles"
    this.cablesVisible = false
    this._cableEntities = []
    this._landingPointEntities = []
    this.outagesVisible = false
    this._outageData = []
    this._outageEntities = []
    this._outageInterval = null
    this.powerPlantsVisible = false
    this._powerPlantData = []
    this._powerPlantEntities = []
    this.conflictsVisible = false
    this._conflictData = []
    this._conflictEntities = []
    this.trafficVisible = false
    this.trafficArcsVisible = true
    this.trafficBlobsVisible = true
    this._trafficData = null
    this._trafficEntities = []
    this.notamsVisible = false
    this._notamData = []
    this._notamEntities = []
    this._satVisEntities = []
    this._satVisEventPos = null
    this.airportsVisible = false
    this._airportEntities = []
    this._webcamData = []
    this._webcamEntities = []
    this._webcamLastFetchCenter = null
    this.countrySelectMode = false
    this.drawMode = false
    this._drawCenter = null
    this._drawing = false
    this._drawCircleEntity = null
    // Satellite footprint country mode
    this._satFootprintCountryMode = false
    // Airline filter
    this._airlineFilter = new Set() // active airline ICAO codes (empty = show all)
    this._detectedAirlines = new Map() // code → count
    this._pendingCountryRestore = null
    this._ds = {} // shared datasource cache for getDataSource()
    this._backgroundRefreshRetryTimers = {}
    this._backgroundRefreshRetryCounts = {}
    // Stats clock
    this._clockInterval = setInterval(() => this._updateClock(), 1000)
    this._updateClock()
    // JS tooltips — position fixed so they escape overflow:hidden containers
    this._initTooltips()
    // Restore saved preferences
    this._restorePrefs()
    this.loadCesium()
  }

  loadCesium() {
    const needed = []

    if (!window.Cesium) {
      const link = document.createElement("link")
      link.rel = "stylesheet"
      link.href = "https://cesium.com/downloads/cesiumjs/releases/1.124/Build/Cesium/Widgets/widgets.css"
      document.head.appendChild(link)

      needed.push(this.loadScript("https://cesium.com/downloads/cesiumjs/releases/1.124/Build/Cesium/Cesium.js"))
    }

    if (!window.satellite) {
      needed.push(this.loadScript("https://cdn.jsdelivr.net/npm/satellite.js@5.0.0/dist/satellite.min.js"))
    }

    if (needed.length === 0) {
      this.initViewer()
    } else {
      Promise.all(needed).then(() => this.initViewer())
    }
  }

  loadScript(src) {
    return new Promise((resolve) => {
      const script = document.createElement("script")
      script.src = src
      script.onload = resolve
      document.head.appendChild(script)
    })
  }

  initViewer() {
    const Cesium = window.Cesium

    Cesium.Ion.defaultAccessToken = this.cesiumTokenValue

    this.terrainEnabled = false
    this.viewer = new Cesium.Viewer("cesium-viewer", {
      baseLayerPicker: false,
      geocoder: false,
      homeButton: false,
      navigationHelpButton: false,
      sceneModePicker: false,
      timeline: false,
      animation: false,
      fullscreenButton: false,
      vrButton: false,
      infoBox: false,
      selectionIndicator: true,
      creditContainer: document.createElement("div"),
      requestRenderMode: true,
      maximumRenderTimeChange: Infinity,
    })

    this.viewer.scene.globe.enableLighting = true
    this.viewer.scene.skyAtmosphere.show = true
    this.viewer.scene.fog.enabled = true
    this.viewer.scene.globe.showGroundAtmosphere = true

    // Generate selection bracket images
    this._selBoxImgGreen = this._makeSelectionBracket("#4caf50", 0.9)
    this._selBoxImgYellow = this._makeSelectionBracket("#fdd835", 0.8)

    // Restore camera: prefer DB prefs (signed-in), then sessionStorage, then default
    restoreCamera(this.viewer, this._restoredPrefs)

    this.viewer.scene.skyBox.show = true
    this.viewer.scene.backgroundColor = Cesium.Color.BLACK

    // Apply DB-saved preferences (camera, layers, sections, countries)
    this._applyRestoredPrefs()

    // Save camera position on move (sessionStorage + DB)
    this.viewer.camera.moveEnd.addEventListener(() => {
      this.saveCamera()
      this._savePrefs()
    })

    // Click handler for custom detail panel
    const handler = new Cesium.ScreenSpaceEventHandler(this.viewer.scene.canvas)
    handler.setInputAction((click) => {
      // Draw mode handled by mouse down/move/up
      if (this.drawMode) return

      const picked = this.viewer.scene.pick(click.position)
      if (Cesium.defined(picked) && picked.id) {
        const entityId = picked.id.id || picked.id
        const flightData = this.flightData.get(entityId)
        if (flightData) {
          this.toggleFlightSelection(entityId)
          this.showDetail(entityId, flightData)
          return
        }
        if (typeof entityId === "string" && entityId.startsWith("ship-")) {
          const mmsi = entityId.replace("ship-", "")
          const shipData = this.shipData.get(mmsi)
          if (shipData) {
            this.toggleShipSelection(mmsi)
            this.showShipDetail(shipData)
            return
          }
        }
        if (this.countrySelectMode && typeof entityId === "string" && entityId.startsWith("border-")) {
          const countryData = this._borderCountryMap?.get(entityId)
          if (countryData) {
            this.toggleCountrySelection(countryData.name)
            this.showBorderDetail()
            return
          }
        }
        if (typeof entityId === "string" && entityId.startsWith("sat-")) {
          const noradId = parseInt(entityId.replace("sat-", ""))
          const satData = this.satelliteData.find(s => s.norad_id === noradId)
          if (satData) {
            this.toggleSatSelection(noradId)
            this.showSatelliteDetail(satData)
            return
          }
        }
        if (typeof entityId === "string" && entityId.startsWith("airport-")) {
          const icao = entityId.replace("airport-", "")
          this.showAirportDetail(icao)
          return
        }
        if (typeof entityId === "string" && entityId.startsWith("eq-")) {
          const eqId = entityId.replace("eq-", "")
          const eq = this._earthquakeData.find(e => e.id === eqId)
          if (eq) { this.showEarthquakeDetail(eq); return }
        }
        if (typeof entityId === "string" && entityId.startsWith("eonet-")) {
          const eoId = entityId.replace("eonet-", "")
          const ev = this._naturalEventData.find(e => e.id === eoId)
          if (ev) { this.showNaturalEventDetail(ev); return }
        }
        if (typeof entityId === "string" && entityId.startsWith("news-arc-")) {
          const arcIdx = parseInt(entityId.replace(/^news-arc-(?:lbl-|arr-)?/, ""))
          if (!isNaN(arcIdx)) { this.showNewsArcDetail(arcIdx); return }
        }
        if (typeof entityId === "string" && entityId.startsWith("news-")) {
          const idx = parseInt(entityId.replace("news-", ""))
          const ev = this._newsData?.[idx]
          if (ev) { this.showNewsDetail(ev); return }
        }
        if (typeof entityId === "string" && entityId.startsWith("outage-") && !entityId.startsWith("outage-ring-")) {
          const code = entityId.replace("outage-", "")
          this.showOutageDetail(code)
          return
        }
        if (typeof entityId === "string" && entityId.startsWith("cable-")) {
          const props = picked.id.properties
          if (props) {
            const name = props.cableName?.getValue() || "Unknown cable"
            this.detailContentTarget.innerHTML = `
              <div class="detail-callsign" style="color:#00bcd4;">
                <i class="fa-solid fa-network-wired" style="margin-right:6px;"></i>Submarine Cable
              </div>
              <div class="detail-country">${this._escapeHtml(name)}</div>
              <a href="https://www.submarinecablemap.com/submarine-cable/${props.cableId?.getValue() || ''}" target="_blank" rel="noopener" class="detail-track-btn">View on TeleGeography →</a>
            `
            this.detailPanelTarget.style.display = ""
            return
          }
        }
        if (typeof entityId === "string" && entityId.startsWith("cam-")) {
          const camId = entityId.replace("cam-", "")
          const cam = this._webcamData.find(c => String(c.id) === camId)
          if (cam) { this.showWebcamDetail(cam); return }
        }
        if (typeof entityId === "string" && entityId.startsWith("pp-")) {
          const ppId = parseInt(entityId.replace("pp-", ""))
          const pp = this._powerPlantData.find(p => p.id === ppId)
          if (pp) { this.showPowerPlantDetail(pp); return }
        }
        if (typeof entityId === "string" && entityId.startsWith("conf-") && !entityId.startsWith("conf-ring-")) {
          const confId = parseInt(entityId.replace("conf-", ""))
          const c = this._conflictData.find(e => e.id === confId)
          if (c) { this.showConflictDetail(c); return }
        }
        if (typeof entityId === "string" && entityId.startsWith("traf-") && !entityId.startsWith("traf-atk-") && !entityId.startsWith("traf-arc-")) {
          const code = entityId.replace("traf-", "")
          this.showTrafficDetail(code)
          return
        }
        if (typeof entityId === "string" && entityId.startsWith("notam-") && !entityId.startsWith("notam-warn-") && !entityId.startsWith("notam-lbl-")) {
          const nId = entityId.replace("notam-", "")
          const n = this._notamData?.find(x => String(x.id) === nId)
          if (n) { this.showNotamDetail(n); return }
        }
        if (typeof entityId === "string" && entityId.startsWith("notam-lbl-")) {
          const nId = entityId.replace("notam-lbl-", "")
          const n = this._notamData?.find(x => String(x.id) === nId)
          if (n) { this.showNotamDetail(n); return }
        }
      }

      // Click on globe surface — select country only in country select mode
      if (this.countrySelectMode && this.bordersLoaded) {
        const globePos = this.screenToLatLng(click.position)
        if (globePos) {
          const country = this.findCountryAtPoint(globePos.lat, globePos.lng)
          if (country) {
            this.toggleCountrySelection(country)
            this.showBorderDetail()
            return
          }
        }
      }

      this.closeDetail()
    }, Cesium.ScreenSpaceEventType.LEFT_CLICK)

    // Draw mode: click+drag
    handler.setInputAction((click) => {
      if (!this.drawMode) return
      const globePos = this.screenToLatLng(click.position)
      if (!globePos) return
      this._drawCenter = globePos
      this._drawing = true
      this.showDrawPreview(globePos, 0)
    }, Cesium.ScreenSpaceEventType.LEFT_DOWN)

    handler.setInputAction((movement) => {
      if (!this.drawMode || !this._drawing || !this._drawCenter) return
      const globePos = this.screenToLatLng(movement.endPosition)
      if (globePos) {
        const radius = this.haversineDistance(this._drawCenter, globePos)
        this.showDrawPreview(this._drawCenter, radius)
      }
    }, Cesium.ScreenSpaceEventType.MOUSE_MOVE)

    handler.setInputAction((click) => {
      if (!this.drawMode || !this._drawing || !this._drawCenter) return
      const globePos = this.screenToLatLng(click.position)
      if (globePos) {
        const radius = this.haversineDistance(this._drawCenter, globePos)
        if (radius > 10000) { // minimum 10km
          this.selectCountriesInCircle(this._drawCenter, radius)
        }
      }
      this._drawing = false
      this.exitDrawMode()
    }, Cesium.ScreenSpaceEventType.LEFT_UP)

    this._handler = handler

    // Create plane icon
    this.planeIcon = this.createPlaneIcon("#4fc3f7")
    this.planeIconGround = this.createPlaneIcon("#888888")
    this.planeIconMil = this.createPlaneIcon("#ef5350")

    // Pre-build satellite icons per category color
    this._satIcons = {}
    this._satPrevPositions = new Map() // norad_id -> { lat, lng, alt, time }

    // Layers start disabled — fetching begins when toggled on

    // Start animation loop
    this.lastAnimTime = performance.now()
    this.animate()
  }

  _requestRender() { if (this.viewer) this.viewer.scene.requestRender() }

  createPlaneIcon(color) { return createPlaneIcon(color) }

  saveCamera() { saveCamera(this.viewer) }
  getViewportBounds() { return getViewportBounds(this.viewer) }

  // Returns filter bounds from circle/countries, or viewport if no filter active
  getFilterBounds() {
    // Circle filter takes priority
    if (this._activeCircle) {
      const { center, radius } = this._activeCircle
      const degOffset = (radius / 111320) * 1.1 // rough deg conversion + 10% margin
      return {
        lamin: center.lat - degOffset,
        lamax: center.lat + degOffset,
        lomin: center.lng - degOffset / Math.cos(center.lat * Math.PI / 180),
        lomax: center.lng + degOffset / Math.cos(center.lat * Math.PI / 180),
      }
    }

    // Country filter: compute bounding box of all selected countries
    if (this.selectedCountries.size > 0 && this._countryFeatures.length > 0) {
      let lats = [], lngs = []
      for (const feature of this._countryFeatures) {
        const name = feature.properties?.NAME || feature.properties?.name
        if (!name || !this.selectedCountries.has(name)) continue
        const geom = feature.geometry
        const polys = geom.type === "Polygon" ? [geom.coordinates] : geom.type === "MultiPolygon" ? geom.coordinates : []
        for (const poly of polys) {
          for (const coord of poly[0]) {
            lngs.push(coord[0])
            lats.push(coord[1])
          }
        }
      }
      if (lats.length > 0) {
        return {
          lamin: Math.min(...lats),
          lamax: Math.max(...lats),
          lomin: Math.min(...lngs),
          lomax: Math.max(...lngs),
        }
      }
    }

    return this.getViewportBounds()
  }

  // Check if a point passes the active filter (circle or country)
  pointPassesFilter(lat, lng) {
    if (this._activeCircle) {
      const dist = this.haversineDistance(this._activeCircle.center, { lat, lng })
      return dist <= this._activeCircle.radius
    }

    if (this.selectedCountries.size > 0 && this._countryFeatures.length > 0) {
      // Fast bbox rejection first
      const fb = this._selectedCountriesBbox
      if (fb && (lat < fb.minLat || lat > fb.maxLat || lng < fb.minLng || lng > fb.maxLng)) {
        return false
      }
      // Only test polygons of selected countries (not all countries)
      return this._pointInSelectedCountries(lat, lng)
    }

    return true // no filter active
  }

  // Test point against selected countries' polygons OR their convex hull (international waters)
  _pointInSelectedCountries(lat, lng) {
    // Check exact country polygons first
    for (const feature of this._countryFeatures) {
      const name = feature.properties?.NAME || feature.properties?.name
      if (!name || !this.selectedCountries.has(name)) continue

      const geom = feature.geometry
      const polygons = geom.type === "Polygon" ? [geom.coordinates] : geom.type === "MultiPolygon" ? geom.coordinates : []
      for (const poly of polygons) {
        if (this.pointInPolygon(lat, lng, poly[0])) return true
      }
    }
    // Fall back to convex hull (captures international waters between selected countries)
    if (this._selectedCountriesHull && this._selectedCountriesHull.length >= 3) {
      return this.pointInPolygon(lat, lng, this._selectedCountriesHull)
    }
    return false
  }

  // Recompute bounding box and convex hull whenever selection changes
  _updateSelectedCountriesBbox() {
    if (this.selectedCountries.size === 0) {
      this._selectedCountriesBbox = null
      this._selectedCountriesHull = null
      return
    }
    let minLat = 90, maxLat = -90, minLng = 180, maxLng = -180
    const allPoints = []
    for (const feature of this._countryFeatures) {
      const name = feature.properties?.NAME || feature.properties?.name
      if (!name || !this.selectedCountries.has(name)) continue

      const geom = feature.geometry
      const polygons = geom.type === "Polygon" ? [geom.coordinates] : geom.type === "MultiPolygon" ? geom.coordinates : []
      for (const poly of polygons) {
        for (const coord of poly[0]) {
          if (coord[0] < minLng) minLng = coord[0]
          if (coord[0] > maxLng) maxLng = coord[0]
          if (coord[1] < minLat) minLat = coord[1]
          if (coord[1] > maxLat) maxLat = coord[1]
          allPoints.push(coord)
        }
      }
    }
    this._selectedCountriesBbox = { minLat, maxLat, minLng, maxLng }
    this._selectedCountriesHull = this._computeConvexHull(allPoints)
  }

  // Andrew's monotone chain convex hull algorithm — O(n log n)
  _computeConvexHull(points) {
    if (points.length < 3) return points.slice()
    // Downsample for performance: take every Nth point if there are too many
    let pts = points
    if (pts.length > 5000) {
      const step = Math.ceil(pts.length / 5000)
      pts = pts.filter((_, i) => i % step === 0)
    }
    pts = pts.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1])
    // Remove duplicates
    pts = pts.filter((p, i) => i === 0 || p[0] !== pts[i - 1][0] || p[1] !== pts[i - 1][1])
    if (pts.length < 3) return pts

    const cross = (O, A, B) => (A[0] - O[0]) * (B[1] - O[1]) - (A[1] - O[1]) * (B[0] - O[0])
    const lower = []
    for (const p of pts) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) lower.pop()
      lower.push(p)
    }
    const upper = []
    for (let i = pts.length - 1; i >= 0; i--) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], pts[i]) <= 0) upper.pop()
      upper.push(pts[i])
    }
    lower.pop()
    upper.pop()
    return lower.concat(upper)
  }

  hasActiveFilter() {
    return !!this._activeCircle || this.selectedCountries.size > 0
  }

  // ── Toast ──────────────────────────────────────────────────
  _toast(msg) {
    const el = document.getElementById("gt-toast")
    if (!el) return
    el.textContent = msg
    el.classList.add("visible")
    clearTimeout(this._toastTimer)
    this._toastTimer = setTimeout(() => el.classList.remove("visible"), 2000)
  }
  _toastHide() {
    const el = document.getElementById("gt-toast")
    if (el) el.classList.remove("visible")
    clearTimeout(this._toastTimer)
  }

  _handleBackgroundRefresh(resp, key, hasData, retryFn) {
    const queued = resp.headers.get("X-Background-Refresh") === "queued"
    if (!queued || hasData) {
      if (this._backgroundRefreshRetryTimers[key]) {
        clearTimeout(this._backgroundRefreshRetryTimers[key])
        delete this._backgroundRefreshRetryTimers[key]
      }
      delete this._backgroundRefreshRetryCounts[key]
      return
    }

    const attempts = this._backgroundRefreshRetryCounts[key] || 0
    if (attempts >= 3) return

    if (this._backgroundRefreshRetryTimers[key]) {
      clearTimeout(this._backgroundRefreshRetryTimers[key])
    }

    this._backgroundRefreshRetryCounts[key] = attempts + 1
    this._backgroundRefreshRetryTimers[key] = setTimeout(() => {
      delete this._backgroundRefreshRetryTimers[key]
      retryFn()
    }, 1500)
  }

  async fetchFlights() {
    if (!this.flightsVisible || this._timelineActive) return

    this._toast("Loading flights...")
    try {
      let url = "/api/flights"
      const bounds = this.getFilterBounds()
      if (bounds) {
        const params = new URLSearchParams(bounds).toString()
        url += `?${params}`
      }

      const response = await fetch(url)
      if (!response.ok) return

      let flights = await response.json()

      // Apply precise filter (circle or country boundaries)
      if (this.hasActiveFilter()) {
        flights = flights.filter(f => f.latitude && f.longitude && this.pointPassesFilter(f.latitude, f.longitude))
      }

      this.renderFlights(flights)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch flights:", e)
    }
  }

  renderFlights(flights) {
    const Cesium = window.Cesium
    const dataSource = this.getFlightsDataSource()
    const currentIds = new Set()

    flights.forEach(flight => {
      if (!flight.latitude || !flight.longitude) return

      const id = flight.icao24
      currentIds.add(id)

      const alt = flight.altitude || 0
      const heading = flight.heading || 0
      const speed = flight.speed || 0
      const callsign = (flight.callsign || flight.icao24 || "").trim()
      const onGround = flight.on_ground

      const existing = this.flightData.get(id)

      // Record trail history (only when trails are visible)
      if (this.trailsVisible) {
        let trail = this.trailHistory.get(id)
        if (!trail) {
          trail = []
          this.trailHistory.set(id, trail)
        }
        const lastPoint = trail[trail.length - 1]
        if (!lastPoint || lastPoint.lat !== flight.latitude || lastPoint.lng !== flight.longitude) {
          trail.push({ lat: flight.latitude, lng: flight.longitude, alt })
          if (trail.length > 200) trail.shift()
        }
      }

      // Pre-project the reported position forward by data age
      // so our dead reckoning starts from a more accurate point
      const verticalRate = flight.vertical_rate || 0
      let projLat = flight.latitude
      let projLng = flight.longitude
      let projAlt = alt

      if (flight.time_position && speed > 0 && !onGround) {
        const dataAge = (Date.now() / 1000) - flight.time_position
        if (dataAge > 0 && dataAge < 60) {
          const headingRad = Cesium.Math.toRadians(heading)
          const dist = speed * dataAge
          projLat += (dist * Math.cos(headingRad)) / 111320
          projLng += (dist * Math.sin(headingRad)) / (111320 * Math.cos(Cesium.Math.toRadians(projLat)))
          projAlt += verticalRate * dataAge
        }
      }

      if (existing) {
        existing.heading = heading
        existing.speed = speed
        existing.verticalRate = verticalRate
        existing.onGround = onGround
        existing.originCountry = flight.origin_country
        existing.source = flight.source
        existing.registration = flight.registration
        existing.aircraftType = flight.aircraft_type

        // Only correct position if the server has genuinely new data
        const newTimePos = flight.time_position || 0
        if (newTimePos !== existing.lastTimePosition) {
          // Snap directly if the correction is large (> ~500m), otherwise smooth
          const dlat = Math.abs(projLat - existing.currentLat)
          const dlng = Math.abs(projLng - existing.currentLng)
          if (dlat > 0.005 || dlng > 0.005) {
            existing.currentLat = projLat
            existing.currentLng = projLng
            existing.currentAlt = projAlt
          } else {
            existing.currentLat = existing.currentLat * 0.15 + projLat * 0.85
            existing.currentLng = existing.currentLng * 0.15 + projLng * 0.85
            existing.currentAlt = existing.currentAlt * 0.15 + projAlt * 0.85
          }
          existing.lastTimePosition = newTimePos
        }

        const milCheck = { id, callsign }
        const isMil = this._isMilitaryFlight(milCheck)
        existing.entity.billboard.image = onGround ? this.planeIconGround : (isMil ? this.planeIconMil : this.planeIcon)
        existing.entity.billboard.rotation = -Cesium.Math.toRadians(heading)
        existing.entity.label.text = callsign
      } else {
        const milCheck = { id, callsign }
        const isMil = this._isMilitaryFlight(milCheck)
        const pos = Cesium.Cartesian3.fromDegrees(projLng, projLat, projAlt)
        const entity = dataSource.entities.add({
          id: id,
          position: pos,
          billboard: {
            image: onGround ? this.planeIconGround : (isMil ? this.planeIconMil : this.planeIcon),
            scale: 0.8,
            rotation: -Cesium.Math.toRadians(heading),
            alignedAxis: Cesium.Cartesian3.UNIT_Z,
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.3),
          },
          label: {
            text: callsign,
            font: "15px JetBrains Mono, monospace",
            fillColor: Cesium.Color.WHITE.withAlpha(0.95),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            pixelOffset: new Cesium.Cartesian2(0, -18),
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 5e6, 0),
            translucencyByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0),
          },
        })

        this.flightData.set(id, {
          entity,
          id,
          callsign,
          latitude: projLat,
          longitude: projLng,
          altitude: alt,
          currentLat: projLat,
          currentLng: projLng,
          currentAlt: projAlt,
          heading,
          speed,
          verticalRate,
          onGround,
          originCountry: flight.origin_country,
          lastTimePosition: flight.time_position || 0,
          source: flight.source,
          registration: flight.registration,
          aircraftType: flight.aircraft_type,
        })
        // Apply civilian/military filter
        entity.show = isMil ? this.showMilitary : this.showCivilian
      }
    })

    // Remove flights no longer in view
    for (const [id, data] of this.flightData) {
      if (!currentIds.has(id)) {
        dataSource.entities.remove(data.entity)
        this.flightData.delete(id)
        this.trailHistory.delete(id)
        // Clean up selection highlight if present
        if (this.selectedFlights.has(id)) {
          this.selectedFlights.delete(id)
          this._removeFlightHighlight(id)
          this._renderSelectionTray()
        }
      }
    }

    // Update stats and airline detection
    this._updateStats()
    this._detectAirlines()

    // Render trails
    if (this.trailsVisible) this.renderTrails()

    // Update entity list if visible
    if (this.hasActiveFilter() && this.entityListPanelTarget.style.display !== "none") {
      this.updateEntityList()
    }

    this.viewer.scene.requestRender()
  }

  // Simplify trail by removing redundant straight-line points (Ramer-Douglas-Peucker),
  // then smooth the remaining key points with a Catmull-Rom spline.
  _interpolateTrailSpline(positions, segmentsPerPoint = 4) {
    const Cesium = window.Cesium
    if (positions.length < 3) return positions

    // Step 1: Simplify — strip out points that lie on a straight course
    const simplified = this._rdpSimplify(positions, 500) // 500m tolerance
    if (simplified.length < 3) return simplified

    // Step 2: Spline through the key waypoints for a flowing curve
    const times = simplified.map((_, i) => i / (simplified.length - 1))
    const spline = new Cesium.CatmullRomSpline({ times, points: simplified })

    const smoothed = []
    const totalSegments = (simplified.length - 1) * segmentsPerPoint
    for (let i = 0; i <= totalSegments; i++) {
      smoothed.push(spline.evaluate(i / totalSegments))
    }
    return smoothed
  }

  // Ramer-Douglas-Peucker: keep start/end + points that deviate from the straight line
  // by more than `epsilon` meters. Removes noise on straight segments, keeps real turns.
  _rdpSimplify(points, epsilon) {
    if (points.length <= 2) return points

    const Cesium = window.Cesium
    // Find the point farthest from the line between first and last
    const first = points[0], last = points[points.length - 1]
    let maxDist = 0, maxIdx = 0

    for (let i = 1; i < points.length - 1; i++) {
      const d = this._pointToLineDist(points[i], first, last, Cesium)
      if (d > maxDist) { maxDist = d; maxIdx = i }
    }

    if (maxDist > epsilon) {
      const left = this._rdpSimplify(points.slice(0, maxIdx + 1), epsilon)
      const right = this._rdpSimplify(points.slice(maxIdx), epsilon)
      return left.slice(0, -1).concat(right)
    }
    return [first, last]
  }

  // Perpendicular distance from point P to line segment A→B, in meters
  _pointToLineDist(p, a, b, Cesium) {
    const ap = Cesium.Cartesian3.subtract(p, a, new Cesium.Cartesian3())
    const ab = Cesium.Cartesian3.subtract(b, a, new Cesium.Cartesian3())
    const abLen = Cesium.Cartesian3.magnitude(ab)
    if (abLen < 1e-10) return Cesium.Cartesian3.distance(p, a)

    const cross = Cesium.Cartesian3.cross(ap, ab, new Cesium.Cartesian3())
    return Cesium.Cartesian3.magnitude(cross) / abLen
  }

  renderTrails() {
    const Cesium = window.Cesium
    const trailSource = this.getTrailsDataSource()

    if (!this._trailEntities) this._trailEntities = new Map()

    const activeIds = new Set()

    for (const [id, trail] of this.trailHistory) {
      if (trail.length < 2) continue
      activeIds.add(id)

      const raw = trail.map(p => Cesium.Cartesian3.fromDegrees(p.lng, p.lat, p.alt))
      const positions = this._interpolateTrailSpline(raw)
      const existing = this._trailEntities.get(id)

      if (existing) {
        // Update positions directly instead of per-frame CallbackProperty
        existing.polyline.positions = positions
      } else {
        const entity = trailSource.entities.add({
          id: `trail-${id}`,
          polyline: {
            positions,
            width: 2.5,
            material: Cesium.Color.fromCssColorString("#4fc3f7").withAlpha(0.4),
            clampToGround: false,
          },
        })
        this._trailEntities.set(id, entity)
      }
    }

    // Remove stale trails
    for (const [id, entity] of this._trailEntities) {
      if (!activeIds.has(id)) {
        trailSource.entities.remove(entity)
        this._trailEntities.delete(id)
      }
    }
  }

  getTrailsDataSource() { return getDataSource(this.viewer, this._ds, "trails") }

  toggleTrails() {
    this.trailsVisible = this.hasTrailsToggleTarget && this.trailsToggleTarget.checked
    if (this._ds["trails"]) {
      this._ds["trails"].show = this.trailsVisible
    }
    if (this.trailsVisible) {
      this.renderTrails()
    } else {
      // Free trail entities and history when disabled
      if (this._trailEntities) {
        const trailSource = this.getTrailsDataSource()
        for (const [, entity] of this._trailEntities) {
          trailSource.entities.remove(entity)
        }
        this._trailEntities.clear()
      }
      this.trailHistory.clear()
    }
    this._requestRender()
  }

  toggleFlightFilter() {
    this.showCivilian = this.hasCivilianToggleTarget && this.civilianToggleTarget.checked
    this.showMilitary = this.hasMilitaryToggleTarget && this.militaryToggleTarget.checked
    // Show/hide existing flight entities based on filter
    for (const [id, data] of this.flightData) {
      const isMil = this._isMilitaryFlight(data)
      const visible = isMil ? this.showMilitary : this.showCivilian
      data.entity.show = visible
    }
    this.updateEntityList()
    this._savePrefs()
  }

  animate() {
    const Cesium = window.Cesium
    const now = performance.now()

    // Throttle to ~30fps (33ms) — no need to update positions faster than that
    if (this.lastAnimTime && (now - this.lastAnimTime) < 33) {
      this.animationFrame = requestAnimationFrame(() => this.animate())
      return
    }

    const dt = (now - this.lastAnimTime) / 1000
    this.lastAnimTime = now
    let needsRender = false

    // Dead reckoning for flights (skip during timeline playback)
    if (dt > 0 && dt < 1 && this.flightData.size > 0 && !this._timelineActive) {
      for (const [, data] of this.flightData) {
        if (data.onGround || !data.speed) continue

        const headingRad = Cesium.Math.toRadians(data.heading)
        const distanceM = data.speed * dt

        data.currentLat += (distanceM * Math.cos(headingRad)) / 111320
        data.currentLng += (distanceM * Math.sin(headingRad)) / (111320 * Math.cos(Cesium.Math.toRadians(data.currentLat)))

        if (data.verticalRate) {
          data.currentAlt += data.verticalRate * dt
        }

        data.entity.position = Cesium.Cartesian3.fromDegrees(
          data.currentLng, data.currentLat, data.currentAlt
        )
        needsRender = true
      }
    }

    // Update trails during animation (every ~2s — trail data only refreshes every 10s)
    if (this.trailsVisible && this.flightData.size > 0 && !this._timelineActive) {
      if (!this._lastTrailUpdate || now - this._lastTrailUpdate > 2000) {
        this._lastTrailUpdate = now
        for (const [, data] of this.flightData) {
          if (data.onGround || !data.speed) continue
          let trail = this.trailHistory.get(data.id)
          if (!trail) {
            trail = []
            this.trailHistory.set(data.id, trail)
          }
          const last = trail[trail.length - 1]
          if (!last || Math.abs(last.lat - data.currentLat) > 0.001 || Math.abs(last.lng - data.currentLng) > 0.001) {
            trail.push({ lat: data.currentLat, lng: data.currentLng, alt: data.currentAlt })
            if (trail.length > 200) trail.shift()
          }
        }
        this.renderTrails()
        needsRender = true
      }
    }

    // Animate news arc blobs inline (instead of separate rAF loop)
    if (this.newsVisible && this.newsBlobsVisible && this._newsArcEntities?.length > 0) {
      const t = Date.now() / 1000
      const scratch = this._animScratch || (this._animScratch = new Cesium.Cartesian3())
      for (const e of this._newsArcEntities) {
        if (!e._blobArc) continue
        const pos = e._blobArc
        const n = pos.length
        const f = (t * e._blobSpeed + e._blobPhase) % 1.0
        const fi = f * (n - 1)
        const lo = Math.floor(fi)
        const hi = Math.min(lo + 1, n - 1)
        e.position = Cesium.Cartesian3.lerp(pos[lo], pos[hi], fi - lo, scratch)
      }
      needsRender = true
    }

    // Animate traffic arc blobs inline (instead of separate rAF loop)
    if (this.trafficVisible && this.trafficBlobsVisible && this._trafficEntities?.length > 0) {
      const t = Date.now() / 1000
      const scratch = this._animScratch || (this._animScratch = new Cesium.Cartesian3())
      for (const e of this._trafficEntities) {
        if (!e._blobArc) continue
        const pos = e._blobArc
        const n = pos.length
        const f = (t * e._blobSpeed + e._blobPhase) % 1.0
        const fi = f * (n - 1)
        const lo = Math.floor(fi)
        const hi = Math.min(lo + 1, n - 1)
        e.position = Cesium.Cartesian3.lerp(pos[lo], pos[hi], fi - lo, scratch)
      }
      needsRender = true
    }

    // Follow tracked flight
    if (this.trackedFlightId) {
      const tracked = this.flightData.get(this.trackedFlightId)
      if (tracked) {
        const offset = this.viewer.camera.positionCartographic.height
        this.viewer.camera.setView({
          destination: Cesium.Cartesian3.fromDegrees(
            tracked.currentLng,
            tracked.currentLat,
            Math.max(offset, 50000)
          ),
        })
        needsRender = true
      } else {
        this.trackedFlightId = null
      }
    }

    // Update satellite positions (every ~2 seconds to save CPU)
    if (this.satelliteData.length > 0 && Object.values(this.satCategoryVisible).some(v => v)) {
      if (!this._lastSatUpdate || now - this._lastSatUpdate > 2000) {
        this._lastSatUpdate = now
        this.updateSatellitePositions()
        needsRender = true
      }

      // Smooth lerp satellite positions between updates
      if (this._satPrevPositions.size > 0 && this.satelliteEntities.size > 0) {
        // Smoothly update footprint/ground line for selected satellite
        if (this._selectedSatGeoLerp && this.selectedSatNoradId) {
          const gl = this._selectedSatGeoLerp
          const t = Math.min((now - gl.startTime) / gl.duration, 1.0)
          const lat = gl.fromLat + (gl.toLat - gl.fromLat) * t
          const lng = gl.fromLng + (gl.toLng - gl.fromLng) * t
          const alt = gl.fromAlt + (gl.toAlt - gl.fromAlt) * t
          const altKm = gl.fromAltKm + (gl.toAltKm - gl.fromAltKm) * t
          this._selectedSatPosition = { lat, lng, alt, altKm, color: gl.color }
          this.renderSatHexFootprint(this._selectedSatPosition)
        }
        needsRender = true
      }
    }

    if (needsRender) this.viewer.scene.requestRender()

    this.animationFrame = requestAnimationFrame(() => this.animate())
  }

  showDetail(id, data) {
    this._focusedSelection = { type: "flight", id }
    this._renderSelectionTray()
    const callsign = data.callsign || id
    const alt = data.currentAlt
    const speed = data.speed
    const heading = data.heading
    const vrate = data.verticalRate || 0

    const isTracking = this.trackedFlightId === id

    let vrateDisplay = "—"
    if (vrate > 0.5) vrateDisplay = `+${Math.round(vrate)} m/s ↑`
    else if (vrate < -0.5) vrateDisplay = `${Math.round(vrate)} m/s ↓`
    else if (!data.onGround) vrateDisplay = "Level"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign">${callsign || id}</div>
      <div class="detail-country">${data.originCountry || "Unknown"}</div>
      <div class="detail-route" id="detail-route">Loading route...</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Altitude</span>
          <span class="detail-value">${alt ? Math.round(alt).toLocaleString() + " m" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Speed</span>
          <span class="detail-value">${speed ? Math.round(speed * 3.6) + " km/h" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Heading</span>
          <span class="detail-value">${heading ? Math.round(heading) + "°" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">V/S</span>
          <span class="detail-value">${vrateDisplay}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">ICAO24</span>
          <span class="detail-value" style="font-size:12px; opacity:0.7;">${id}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Status</span>
          <span class="detail-value">${data.onGround ? "On Ground" : "Airborne"}</span>
        </div>
        ${data.registration ? `<div class="detail-field">
          <span class="detail-label">Reg</span>
          <span class="detail-value">${data.registration}</span>
        </div>` : ""}
        ${data.aircraftType ? `<div class="detail-field">
          <span class="detail-label">Type</span>
          <span class="detail-value">${data.aircraftType}</span>
        </div>` : ""}
        <div class="detail-field">
          <span class="detail-label">Source</span>
          <span class="detail-value" style="font-size:11px;">${data.source === "adsb" ? "ADS-B Exchange" : "OpenSky"}</span>
        </div>
      </div>
      <div class="detail-links">
        <a href="https://www.flightradar24.com/${callsign}" target="_blank" rel="noopener">FR24</a>
        <a href="https://www.flightaware.com/live/flight/${callsign}" target="_blank" rel="noopener">FlightAware</a>
        <a href="https://globe.adsbexchange.com/?icao=${id}" target="_blank" rel="noopener">ADS-B</a>
      </div>
      <button class="detail-track-btn ${isTracking ? "tracking" : ""}" data-flight-id="${id}">
        ${isTracking ? "Stop Tracking" : "Track Flight"}
      </button>
    `

    // Bind track button
    this.detailContentTarget.querySelector(".detail-track-btn").addEventListener("click", (e) => {
      const fid = e.target.dataset.flightId
      if (this.trackedFlightId === fid) {
        this.stopTracking()
      } else {
        this.trackFlight(fid)
      }
      const d = this.flightData.get(fid)
      if (d) this.showDetail(fid, d)
    })

    this.detailPanelTarget.style.display = ""

    // Show cached route immediately, or fetch async
    const cached = this._routeCache && this._routeCache[callsign]
    const routeEl = document.getElementById("detail-route")
    if (cached && routeEl) {
      routeEl.innerHTML = `
        <span class="route-airport">${cached.originLabel}</span>
        <span class="route-arrow">→</span>
        <span class="route-airport">${cached.destLabel}</span>
      `
      if (cached.origin && cached.dest) {
        this._drawFlightRoute(callsign, cached.origin, cached.dest)
      }
    } else if (callsign) {
      this.fetchRoute(callsign)
    }
  }

  // Airport data fetched from API — keyed by ICAO code
  _airportDb = {}

  _getAirport(icao) {
    return this._airportDb[icao] || null
  }

  async _fetchAirportData() {
    if (this._airportDataLoaded) return
    try {
      const resp = await fetch("/api/airports")
      if (!resp.ok) return
      const airports = await resp.json()
      this._airportDb = {}
      airports.forEach(a => {
        this._airportDb[a.icao] = {
          lat: a.lat, lng: a.lng, name: a.name,
          iata: a.iata, type: a.type, elevation: a.elevation,
          country: a.country, municipality: a.municipality, military: a.military,
        }
      })
      this._airportDataLoaded = true
    } catch (e) {
      console.warn("Failed to fetch airports:", e)
    }
  }

  async fetchRoute(callsign) {
    await this._fetchAirportData()
    // Store which callsign we're fetching for — if it changes, discard stale results
    this._fetchingRouteFor = callsign

    try {
      const response = await fetch(`/api/flights/${encodeURIComponent(callsign)}`)
      if (this._fetchingRouteFor !== callsign) return

      const el = document.getElementById("detail-route")

      if (!response.ok) {
        console.warn("Route API error:", response.status)
        if (el) el.innerHTML = `<span class="route-unavailable">Route unavailable</span>`
        return
      }

      const data = await response.json()
      if (data.error || !data.route || data.route.length < 2) {
        console.warn("No route data:", data)
        if (el) el.innerHTML = `<span class="route-unavailable">Route not found</span>`
        return
      }

      const originIcao = data.route[0]
      const destIcao = data.route[data.route.length - 1]
      const origin = this._getAirport(originIcao)
      const dest = this._getAirport(destIcao)

      const originLabel = origin ? `${origin.name} (${originIcao})` : originIcao
      const destLabel = dest ? `${dest.name} (${destIcao})` : destIcao

      // Cache route for this callsign
      if (!this._routeCache) this._routeCache = {}
      this._routeCache[callsign] = { originIcao, destIcao, origin, dest, originLabel, destLabel }

      // Update the route element if still in DOM
      if (el) {
        el.innerHTML = `
          <span class="route-airport">${originLabel}</span>
          <span class="route-arrow">→</span>
          <span class="route-airport">${destLabel}</span>
        `
      }

      // Draw route arc on globe
      if (origin && dest) {
        this._drawFlightRoute(callsign, origin, dest)
      }
    } catch (e) {
      console.warn("Route fetch failed:", e)
      const el = document.getElementById("detail-route")
      if (el) el.innerHTML = `<span class="route-unavailable">Route unavailable</span>`
    }
  }

  _drawFlightRoute(callsign, origin, dest) {
    const Cesium = window.Cesium
    const dataSource = this.getFlightsDataSource()

    // Remove previous route arc
    this._clearFlightRoute()

    this._flightRouteEntities = []

    // Build great-circle arc with intermediate points
    const points = this._greatCirclePoints(origin.lat, origin.lng, dest.lat, dest.lng, 80)
    const positions = points.map(p => Cesium.Cartesian3.fromDegrees(p.lng, p.lat, 0))

    // Route arc line
    const arc = dataSource.entities.add({
      id: `route-arc-${callsign}`,
      polyline: {
        positions,
        width: 2,
        material: new Cesium.PolylineDashMaterialProperty({
          color: Cesium.Color.fromCssColorString("#4fc3f7").withAlpha(0.5),
          dashLength: 12,
        }),
        clampToGround: true,
      },
    })
    this._flightRouteEntities.push(arc)

    // Origin airport marker
    const originEntity = dataSource.entities.add({
      id: `route-origin-${callsign}`,
      position: Cesium.Cartesian3.fromDegrees(origin.lng, origin.lat, 0),
      point: {
        pixelSize: 8,
        color: Cesium.Color.fromCssColorString("#66bb6a").withAlpha(0.9),
        outlineColor: Cesium.Color.fromCssColorString("#66bb6a").withAlpha(0.3),
        outlineWidth: 4,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      label: {
        text: origin.name,
        font: "12px JetBrains Mono, monospace",
        fillColor: Cesium.Color.fromCssColorString("#66bb6a"),
        outlineColor: Cesium.Color.BLACK.withAlpha(0.7),
        outlineWidth: 3,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        verticalOrigin: Cesium.VerticalOrigin.TOP,
        pixelOffset: new Cesium.Cartesian2(0, 10),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
        scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0.4),
      },
    })
    this._flightRouteEntities.push(originEntity)

    // Destination airport marker
    const destEntity = dataSource.entities.add({
      id: `route-dest-${callsign}`,
      position: Cesium.Cartesian3.fromDegrees(dest.lng, dest.lat, 0),
      point: {
        pixelSize: 8,
        color: Cesium.Color.fromCssColorString("#ef5350").withAlpha(0.9),
        outlineColor: Cesium.Color.fromCssColorString("#ef5350").withAlpha(0.3),
        outlineWidth: 4,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      label: {
        text: dest.name,
        font: "12px JetBrains Mono, monospace",
        fillColor: Cesium.Color.fromCssColorString("#ef5350"),
        outlineColor: Cesium.Color.BLACK.withAlpha(0.7),
        outlineWidth: 3,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        verticalOrigin: Cesium.VerticalOrigin.TOP,
        pixelOffset: new Cesium.Cartesian2(0, 10),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
        scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0.4),
      },
    })
    this._flightRouteEntities.push(destEntity)
  }

  _clearFlightRoute() {
    if (!this._flightRouteEntities) return
    const ds = this._ds["flights"]
    if (ds) {
      this._flightRouteEntities.forEach(e => ds.entities.remove(e))
    }
    this._flightRouteEntities = []
  }

  _greatCirclePoints(lat1, lng1, lat2, lng2, numPoints) {
    const toRad = d => d * Math.PI / 180
    const toDeg = r => r * 180 / Math.PI
    const φ1 = toRad(lat1), λ1 = toRad(lng1)
    const φ2 = toRad(lat2), λ2 = toRad(lng2)

    const d = 2 * Math.asin(Math.sqrt(
      Math.sin((φ2 - φ1) / 2) ** 2 +
      Math.cos(φ1) * Math.cos(φ2) * Math.sin((λ2 - λ1) / 2) ** 2
    ))

    const points = []
    for (let i = 0; i <= numPoints; i++) {
      const f = i / numPoints
      const A = Math.sin((1 - f) * d) / Math.sin(d)
      const B = Math.sin(f * d) / Math.sin(d)
      const x = A * Math.cos(φ1) * Math.cos(λ1) + B * Math.cos(φ2) * Math.cos(λ2)
      const y = A * Math.cos(φ1) * Math.sin(λ1) + B * Math.cos(φ2) * Math.sin(λ2)
      const z = A * Math.sin(φ1) + B * Math.sin(φ2)
      points.push({
        lat: toDeg(Math.atan2(z, Math.sqrt(x * x + y * y))),
        lng: toDeg(Math.atan2(y, x)),
      })
    }
    return points
  }

  showSatelliteDetail(satData) {
    this._focusedSelection = { type: "sat", id: satData.norad_id }
    this._renderSelectionTray()
    const sat = window.satellite
    const now = new Date()
    const satrec = sat.twoline2satrec(satData.tle_line1, satData.tle_line2)
    const posVel = sat.propagate(satrec, now)
    const gmst = sat.gstime(now)

    let altKm = "—"
    let speedKms = "—"
    if (posVel.position) {
      const posGd = sat.eciToGeodetic(posVel.position, gmst)
      altKm = Math.round(posGd.height).toLocaleString() + " km"
    }
    if (posVel.velocity) {
      const v = posVel.velocity
      const speed = Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
      speedKms = Math.round(speed * 10) / 10 + " km/s"
    }

    const operatorHtml = satData.operator ? `
        <div class="detail-field">
          <span class="detail-label">Operator</span>
          <span class="detail-value">${satData.operator}</span>
        </div>` : ""
    const missionHtml = satData.mission_type ? `
        <div class="detail-field">
          <span class="detail-label">Mission</span>
          <span class="detail-value">${satData.mission_type.replace(/_/g, " ")}</span>
        </div>` : ""

    // Enrichment fields — UCS for regular sats, orbital analysis for classified
    const isClassified = satData.category === "analyst"
    const enrichmentFields = [
      ["Country", satData.country_owner],
      ["Users", satData.users],
      ["Purpose", satData.purpose],
      ["Orbit", satData.orbit_class],
      ["Launched", satData.launch_date],
      ["Launch Site", satData.launch_site],
      ["Vehicle", satData.launch_vehicle],
      isClassified ? ["Co-orbital Group", satData.contractor] : ["Contractor", satData.contractor],
      ["Lifetime", satData.expected_lifetime ? satData.expected_lifetime + " yrs" : null],
    ].filter(([, v]) => v).map(([label, value]) => `
        <div class="detail-field">
          <span class="detail-label">${label}</span>
          <span class="detail-value">${this._escapeHtml(value)}</span>
        </div>`).join("")

    // Classified badge + orbital analysis callout
    const classifiedBanner = isClassified ? `
      <div class="classified-banner">
        <span class="classified-badge">CLASSIFIED</span>
        <span class="classified-label">Unacknowledged payload — orbital analysis</span>
      </div>` : ""

    const analysisCallout = isClassified && satData.detailed_purpose ? `
      <div class="orbital-analysis-callout">
        <div class="oac-icon"><i class="fa-solid fa-satellite-dish"></i></div>
        <div class="oac-text">${this._escapeHtml(satData.detailed_purpose)}</div>
      </div>` : ""

    const subtitlePurpose = !isClassified && satData.purpose
      ? '<div style="font:500 10px var(--gt-mono);color:var(--gt-text-dim);margin:-4px 0 8px;">' + this._escapeHtml(satData.detailed_purpose || satData.purpose) + '</div>'
      : ""

    const categoryLabel = isClassified ? "ANALYST" : satData.category.toUpperCase()
    const operatorSuffix = satData.country_owner ? " — " + satData.country_owner : (satData.operator ? " — " + satData.operator : "")

    this.detailContentTarget.innerHTML = `
      ${classifiedBanner}
      <div class="detail-callsign">${satData.name}</div>
      <div class="detail-country">${categoryLabel}${operatorSuffix}</div>
      ${subtitlePurpose}
      ${analysisCallout}
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">NORAD ID</span>
          <span class="detail-value">${satData.norad_id}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Altitude</span>
          <span class="detail-value">${altKm}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Speed</span>
          <span class="detail-value">${speedKms}</span>
        </div>
        ${operatorHtml}
        ${missionHtml}
        ${enrichmentFields}
      </div>
      ${this.selectedCountries.size > 0 ? `
      <button class="detail-track-btn ${this._satFootprintCountryMode ? 'tracking' : ''}"
              data-action="click->globe#toggleSatFootprintCountryMode">
        ${this._satFootprintCountryMode ? 'Show Radial Footprint' : 'Map to Selected Countries'}
      </button>` : ''}
      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showGroundEvents" data-norad="${satData.norad_id}">
        <i class="fa-solid fa-crosshairs" style="margin-right:4px;"></i>Show Ground Events in Footprint
      </button>
    `
    this.detailPanelTarget.style.display = ""

    // Show footprint for this satellite
    this.selectSatFootprint(satData.norad_id)
  }

  trackFlight(id) {
    this.trackedFlightId = id
    const data = this.flightData.get(id)
    if (data) {
      const Cesium = window.Cesium
      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(data.currentLng, data.currentLat, 200000),
        duration: 1.5,
      })
    }
  }

  stopTracking() {
    this.trackedFlightId = null
  }

  closeDetail() {
    this.detailPanelTarget.style.display = "none"
    this._focusedSelection = null
    this._renderSelectionTray()
    this.stopTracking()
    this.clearSatFootprint()
    this._clearFlightRoute()
    this._clearSatVisEntities()
  }

  // ── Entity List Panel ─────────────────────────────────────

  updateEntityList() {
    if (!this.hasActiveFilter()) {
      this.entityListPanelTarget.style.display = "none"
      return
    }

    const flights = this.flightsVisible
      ? [...this.flightData.values()].filter(f => f.currentLat && f.currentLng && this.pointPassesFilter(f.currentLat, f.currentLng))
      : []
    const ships = this.shipsVisible
      ? [...this.shipData.values()].filter(s => s.latitude && s.longitude && this.pointPassesFilter(s.latitude, s.longitude))
      : []
    const sats = this.satelliteData.filter(s => {
      if (!this.satCategoryVisible[s.category]) return false
      const entity = this.satelliteEntities.get(`sat-${s.norad_id}`)
      return !!entity
    }).filter(s => {
      // Check if the satellite entity is within the filter
      const sat = window.satellite
      if (!sat) return false
      try {
        const now = new Date()
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) return false
        const gmst = sat.gstime(now)
        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        return this.pointPassesFilter(sat.degreesLat(posGd.latitude), sat.degreesLong(posGd.longitude))
      } catch { return false }
    })

    this.entityFlightCountTarget.textContent = flights.length
    this.entityShipCountTarget.textContent = ships.length
    this.entitySatCountTarget.textContent = sats.length

    // Store for tab rendering
    this._entityListData = { flights, ships, sats }

    // Set header
    const label = this._activeCircle
      ? "Circle Selection"
      : [...this.selectedCountries].join(", ")
    this.entityListHeaderTarget.textContent = label

    this.entityListPanelTarget.style.display = "block"

    // Render active tab
    const activeTab = this.entityListPanelTarget.querySelector(".entity-tab.active")?.dataset.tab || "flights"
    this.renderEntityTab(activeTab)
  }

  switchEntityTab(event) {
    const tab = event.currentTarget.dataset.tab
    this.entityListPanelTarget.querySelectorAll(".entity-tab").forEach(t => t.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this.renderEntityTab(tab)
  }

  renderEntityTab(tab) {
    const data = this._entityListData
    if (!data) return

    let html = ""

    if (tab === "flights") {
      // Show airline bar in entity list
      if (this.hasEntityAirlineBarTarget) {
        this.entityAirlineBarTarget.style.display = data.flights.length > 0 ? "" : "none"
        this._updateAirlineChips()
      }

      if (this.selectedFlights.size > 0) {
        html = `<div class="entity-selection-bar">
          <span>${this.selectedFlights.size} selected</span>
          <button class="entity-clear-btn" data-action="click->globe#clearFlightSelection">Clear</button>
        </div>`
      }

      // Apply airline filter
      let flights = data.flights
      if (this._airlineFilter.size > 0) {
        flights = flights.filter(f => this._flightPassesAirlineFilter(f))
      }

      if (flights.length === 0) {
        html += '<div class="entity-empty">No flights in area</div>'
      } else {
        // Sort: selected first, then military, then by altitude
        html += flights
          .map(f => ({ ...f, _mil: this._isMilitaryFlight(f), _sel: this.selectedFlights.has(f.id) ? 1 : 0 }))
          .sort((a, b) => (b._sel - a._sel) || (b._mil - a._mil) || (b.altitude || 0) - (a.altitude || 0))
          .map(f => {
          const alt = f.currentAlt || f.altitude || 0
          const vr = f.verticalRate || 0
          const spd = f.speed || 0
          const isMil = f._mil
          const airlineCode = this._extractAirlineCode(f.callsign)
          const airlineName = airlineCode ? this._getAirlineName(airlineCode) : ""

          // Status icon
          let statusIcon, statusColor
          if (isMil) {
            statusIcon = "fa-jet-fighter"
            statusColor = "#ef5350"
          } else if (f.onGround) {
            statusIcon = "fa-plane-arrival"
            statusColor = "#78909c"
          } else if (vr > 200) {
            statusIcon = "fa-plane-up"
            statusColor = "#66bb6a"
          } else if (vr < -200) {
            statusIcon = "fa-plane-down"
            statusColor = "#ffa726"
          } else {
            statusIcon = "fa-plane"
            statusColor = "#4fc3f7"
          }

          // Altitude label
          const altFt = Math.round(alt * 3.281)
          let altLabel
          if (f.onGround) altLabel = "GND"
          else if (altFt > 30000) altLabel = `FL${Math.round(altFt / 100)}`
          else altLabel = `${altFt.toLocaleString()} ft`

          const milBadge = isMil ? '<span class="entity-badge mil">MIL</span>' : ''
          const isSelected = this.selectedFlights.has(f.id)
          const selClass = isSelected ? " entity-selected" : ""
          const airlineLabel = airlineName && airlineName !== airlineCode ? airlineName : ""

          return `
          <div class="entity-row${isMil ? " entity-military" : ""}${selClass}" data-action="click->globe#flyToFlight" data-id="${f.id || f.hex}">
            <span class="entity-select-dot ${isSelected ? "active" : ""}"></span>
            <span class="entity-icon" style="color: ${statusColor}"><i class="fa-solid ${statusIcon}"></i></span>
            <span class="entity-name">${f.callsign || f.id || "—"}${milBadge}</span>
            <span class="entity-detail">${airlineLabel}</span>
            <span class="entity-detail">${altLabel}</span>
          </div>`
        }).join("")
      }
    } else if (tab === "ships") {
      if (data.ships.length === 0) {
        html = '<div class="entity-empty">No ships in area</div>'
      } else {
        html = data.ships.map(s => `
          <div class="entity-row" data-action="click->globe#flyToShip" data-mmsi="${s.mmsi}">
            <span class="entity-icon"><i class="fa-solid fa-ship"></i></span>
            <span class="entity-name">${s.name || s.mmsi}</span>
            <span class="entity-detail">${s.speed != null ? s.speed.toFixed(1) + " kts" : ""}</span>
            <span class="entity-detail">${s.flag || ""}</span>
          </div>
        `).join("")
      }
    } else if (tab === "satellites") {
      if (data.sats.length === 0) {
        html = '<div class="entity-empty">No satellites in area</div>'
      } else {
        html = data.sats.map(s => `
          <div class="entity-row" data-action="click->globe#flyToSat" data-norad="${s.norad_id}">
            <span class="entity-icon" style="color: ${this.satCategoryColors[s.category] || "#ab47bc"}"><i class="fa-solid fa-satellite"></i></span>
            <span class="entity-name">${s.name}</span>
            <span class="entity-detail">${s.category}</span>
          </div>
        `).join("")
      }
    }

    this.entityListContentTarget.innerHTML = html
  }

  closeEntityList() {
    this.entityListPanelTarget.style.display = "none"
  }

  // ── Selection Tray ───────────────────────────────────────

  toggleFlightSelection(id) {
    if (this.selectedFlights.has(id)) {
      this.selectedFlights.delete(id)
      this._removeFlightHighlight(id)
    } else {
      this.selectedFlights.add(id)
      this._addFlightHighlight(id)
    }
    this._renderSelectionTray()
    if (this.entityListPanelTarget.style.display !== "none") {
      this.renderEntityTab("flights")
    }
  }

  toggleShipSelection(mmsi) {
    if (this.selectedShips.has(mmsi)) {
      this.selectedShips.delete(mmsi)
      this._removeSelectionBox("ship", mmsi)
    } else {
      this.selectedShips.add(mmsi)
      this._addSelectionBox("ship", mmsi)
    }
    this._renderSelectionTray()
  }

  toggleSatSelection(noradId) {
    const key = String(noradId)
    if (this.selectedSats.has(key)) {
      this.selectedSats.delete(key)
      this._removeSelectionBox("sat", key)
    } else {
      this.selectedSats.add(key)
      this._addSelectionBox("sat", key)
    }
    this._renderSelectionTray()
  }

  clearAllSelections() {
    this.clearFlightSelection()
    for (const mmsi of this.selectedShips) this._removeSelectionBox("ship", mmsi)
    this.selectedShips.clear()
    for (const nid of this.selectedSats) this._removeSelectionBox("sat", nid)
    this.selectedSats.clear()
    this._focusedSelection = null
    this._renderSelectionTray()
  }

  _renderSelectionTray() {
    const total = this.selectedFlights.size + this.selectedShips.size + this.selectedSats.size
    if (total === 0) {
      this.selectionTrayTarget.style.display = "none"
      return
    }

    this.selectionTrayTarget.style.display = ""
    let html = ""

    for (const id of this.selectedFlights) {
      const f = this.flightData.get(id)
      const name = f?.callsign || id
      const isMil = f && this._isMilitaryFlight(f)
      const focused = this._focusedSelection?.type === "flight" && this._focusedSelection?.id === id
      html += `<div class="sel-chip${focused ? " sel-focused" : ""}${isMil ? " sel-mil" : ""}" data-action="click->globe#focusSelection" data-sel-type="flight" data-sel-id="${id}">
        <i class="fa-solid fa-plane"></i>
        <span class="sel-chip-name">${this._escapeHtml(name)}</span>
        <button class="sel-chip-remove" data-action="click->globe#removeSelection" data-sel-type="flight" data-sel-id="${id}">&times;</button>
      </div>`
    }

    for (const mmsi of this.selectedShips) {
      const s = this.shipData.get(mmsi)
      const name = s?.name || mmsi
      const focused = this._focusedSelection?.type === "ship" && this._focusedSelection?.id === mmsi
      html += `<div class="sel-chip${focused ? " sel-focused" : ""}" data-action="click->globe#focusSelection" data-sel-type="ship" data-sel-id="${mmsi}">
        <i class="fa-solid fa-ship"></i>
        <span class="sel-chip-name">${this._escapeHtml(name)}</span>
        <button class="sel-chip-remove" data-action="click->globe#removeSelection" data-sel-type="ship" data-sel-id="${mmsi}">&times;</button>
      </div>`
    }

    for (const noradId of this.selectedSats) {
      const s = this.satelliteData.find(sat => String(sat.norad_id) === noradId)
      const name = s?.name || `SAT ${noradId}`
      const color = s ? (this.satCategoryColors[s.category] || "#ab47bc") : "#ab47bc"
      const focused = this._focusedSelection?.type === "sat" && String(this._focusedSelection?.id) === noradId
      html += `<div class="sel-chip${focused ? " sel-focused" : ""}" data-action="click->globe#focusSelection" data-sel-type="sat" data-sel-id="${noradId}" style="--sel-color: ${color}">
        <i class="fa-solid fa-satellite"></i>
        <span class="sel-chip-name">${this._escapeHtml(name)}</span>
        <button class="sel-chip-remove" data-action="click->globe#removeSelection" data-sel-type="sat" data-sel-id="${noradId}">&times;</button>
      </div>`
    }

    this.selectionTrayItemsTarget.innerHTML = html
    this._updateSelectionBoxColors()
  }

  focusSelection(event) {
    // Don't trigger if the remove button was clicked
    if (event.target.closest(".sel-chip-remove")) return
    const type = event.currentTarget.dataset.selType
    const id = event.currentTarget.dataset.selId
    const Cesium = window.Cesium

    this._focusedSelection = { type, id }

    if (type === "flight") {
      const f = this.flightData.get(id)
      if (f) {
        this.viewer.camera.flyTo({
          destination: Cesium.Cartesian3.fromDegrees(f.currentLng, f.currentLat, 200000),
          duration: 1.0,
        })
        this.showDetail(id, f)
        return
      }
    } else if (type === "ship") {
      const s = this.shipData.get(id)
      if (s) {
        this.viewer.camera.flyTo({
          destination: Cesium.Cartesian3.fromDegrees(s.longitude, s.latitude, 100000),
          duration: 1.0,
        })
        this.showShipDetail(s)
        return
      }
    } else if (type === "sat") {
      const noradId = parseInt(id)
      const s = this.satelliteData.find(sat => sat.norad_id === noradId)
      if (s) {
        const sat = window.satellite
        try {
          const now = new Date()
          const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
          const posVel = sat.propagate(satrec, now)
          if (posVel.position) {
            const gmst = sat.gstime(now)
            const posGd = sat.eciToGeodetic(posVel.position, gmst)
            const lng = sat.degreesLong(posGd.longitude)
            const lat = sat.degreesLat(posGd.latitude)
            const alt = posGd.height * 1000
            this.viewer.camera.flyTo({
              destination: Cesium.Cartesian3.fromDegrees(lng, lat, alt + 500000),
              duration: 1.0,
            })
          }
        } catch { /* skip */ }
        this.showSatelliteDetail(s)
        return
      }
    }
    this._renderSelectionTray()
  }

  removeSelection(event) {
    event.stopPropagation()
    const type = event.currentTarget.dataset.selType
    const id = event.currentTarget.dataset.selId

    if (type === "flight") {
      this.selectedFlights.delete(id)
      this._removeSelectionBox("flight", id)
    } else if (type === "ship") {
      this.selectedShips.delete(id)
      this._removeSelectionBox("ship", id)
    } else if (type === "sat") {
      this.selectedSats.delete(id)
      this._removeSelectionBox("sat", id)
    }

    // Clear focus if removing the focused item
    if (this._focusedSelection?.type === type && String(this._focusedSelection?.id) === id) {
      this._focusedSelection = null
    }
    this._renderSelectionTray()
  }

  _addFlightHighlight(id) {
    this._addSelectionBox("flight", id)
  }

  _removeFlightHighlight(id) {
    this._removeSelectionBox("flight", id)
  }

  _makeSelectionBracket(color, alpha) {
    const size = 48
    const c = document.createElement("canvas")
    c.width = size
    c.height = size
    const ctx = c.getContext("2d")
    const L = 12 // bracket arm length
    const pad = 2
    ctx.strokeStyle = color
    ctx.globalAlpha = alpha
    ctx.lineWidth = 2.5
    ctx.lineCap = "square"
    // top-left
    ctx.beginPath(); ctx.moveTo(pad, pad + L); ctx.lineTo(pad, pad); ctx.lineTo(pad + L, pad); ctx.stroke()
    // top-right
    ctx.beginPath(); ctx.moveTo(size - pad - L, pad); ctx.lineTo(size - pad, pad); ctx.lineTo(size - pad, pad + L); ctx.stroke()
    // bottom-left
    ctx.beginPath(); ctx.moveTo(pad, size - pad - L); ctx.lineTo(pad, size - pad); ctx.lineTo(pad + L, size - pad); ctx.stroke()
    // bottom-right
    ctx.beginPath(); ctx.moveTo(size - pad - L, size - pad); ctx.lineTo(size - pad, size - pad); ctx.lineTo(size - pad, size - pad - L); ctx.stroke()
    return c.toDataURL()
  }

  _addSelectionBox(type, id) {
    const key = `${type}-${id}`
    if (this._selectionBoxEntities.has(key)) return

    const Cesium = window.Cesium
    const isFocused = this._focusedSelection?.type === type && String(this._focusedSelection?.id) === String(id)
    const img = isFocused ? this._selBoxImgGreen : this._selBoxImgYellow

    let positionProp
    let dataSource
    if (type === "flight") {
      dataSource = this.getFlightsDataSource()
      positionProp = new Cesium.CallbackProperty(() => {
        const fd = this.flightData.get(id)
        if (!fd) return Cesium.Cartesian3.fromDegrees(0, 0, 0)
        return Cesium.Cartesian3.fromDegrees(fd.currentLng, fd.currentLat, fd.currentAlt)
      }, false)
    } else if (type === "ship") {
      dataSource = getDataSource(this.viewer, this._ds, "ships")
      positionProp = new Cesium.CallbackProperty(() => {
        const sd = this.shipData.get(id)
        if (!sd) return Cesium.Cartesian3.fromDegrees(0, 0, 0)
        return Cesium.Cartesian3.fromDegrees(sd.currentLng, sd.currentLat, 0)
      }, false)
    } else if (type === "sat") {
      dataSource = this.getSatellitesDataSource()
      const noradId = parseInt(id)
      positionProp = new Cesium.CallbackProperty(() => {
        const ent = this.satelliteEntities.get(`sat-${noradId}`)
        return ent ? ent.position?.getValue(Cesium.JulianDate.now()) : Cesium.Cartesian3.fromDegrees(0, 0, 0)
      }, false)
    }

    if (!dataSource) return

    const entity = dataSource.entities.add({
      id: `selbox-${key}`,
      position: positionProp,
      billboard: {
        image: img,
        scale: type === "sat" ? 0.7 : 0.85,
        verticalOrigin: Cesium.VerticalOrigin.CENTER,
        horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
        scaleByDistance: type === "sat"
          ? new Cesium.NearFarScalar(5e5, 1.0, 1e7, 0.5)
          : new Cesium.NearFarScalar(1e5, 1.0, 5e6, 0.4),
      },
    })
    this._selectionBoxEntities.set(key, { entity, dataSource })
  }

  _removeSelectionBox(type, id) {
    const key = `${type}-${id}`
    const entry = this._selectionBoxEntities.get(key)
    if (!entry) return
    try { entry.dataSource.entities.remove(entry.entity) } catch { /* ds may be gone */ }
    this._selectionBoxEntities.delete(key)
  }

  _updateSelectionBoxColors() {
    const Cesium = window.Cesium
    for (const [key, entry] of this._selectionBoxEntities) {
      const [type, ...rest] = key.split("-")
      const id = rest.join("-")
      const isFocused = this._focusedSelection?.type === type && String(this._focusedSelection?.id) === String(id)
      entry.entity.billboard.image = isFocused ? this._selBoxImgGreen : this._selBoxImgYellow
    }
  }

  clearFlightSelection() {
    for (const id of this.selectedFlights) {
      this._removeFlightHighlight(id)
    }
    this.selectedFlights.clear()
    this._renderSelectionTray()
    if (this.entityListPanelTarget.style.display !== "none") {
      this.renderEntityTab("flights")
    }
  }

  flyToFlight(event) {
    const id = event.currentTarget.dataset.id
    this.toggleFlightSelection(id)
    const f = this.flightData.get(id)
    if (f && f.currentLat && f.currentLng) {
      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(f.currentLng, f.currentLat, 200000),
        duration: 1.0,
      })
    }
  }

  flyToShip(event) {
    const mmsi = event.currentTarget.dataset.mmsi
    const s = this.shipData.get(mmsi)
    if (s && s.latitude && s.longitude) {
      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(s.longitude, s.latitude, 100000),
        duration: 1.0,
      })
    }
  }

  flyToSat(event) {
    const noradId = parseInt(event.currentTarget.dataset.norad)
    const s = this.satelliteData.find(sat => sat.norad_id === noradId)
    if (s) {
      const sat = window.satellite
      const now = new Date()
      try {
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (posVel.position) {
          const gmst = sat.gstime(now)
          const posGd = sat.eciToGeodetic(posVel.position, gmst)
          const lng = sat.degreesLong(posGd.longitude)
          const lat = sat.degreesLat(posGd.latitude)
          const alt = posGd.height * 1000
          this.viewer.camera.flyTo({
            destination: Cesium.Cartesian3.fromDegrees(lng, lat, alt + 500000),
            duration: 1.0,
          })
        }
      } catch { /* skip */ }
    }
  }

  // ── Search ─────────────────────────────────────────────────

  onSearchInput() {
    clearTimeout(this._searchDebounce)
    const query = this.searchInputTarget.value.trim()

    if (query.length === 0) {
      this.searchResultsTarget.style.display = "none"
      this.searchClearTarget.style.display = "none"
      return
    }

    this.searchClearTarget.style.display = "block"
    this._searchDebounce = setTimeout(() => this._runSearch(query), 150)
  }

  onSearchKeydown(event) {
    if (event.key === "Escape") {
      this.clearSearch()
    }
  }

  clearSearch() {
    this.searchInputTarget.value = ""
    this.searchResultsTarget.style.display = "none"
    this.searchClearTarget.style.display = "none"
  }

  _runSearch(query) {
    const q = query.toLowerCase()
    const results = []
    const MAX = 8

    // Search flights (by callsign, ICAO, or airline name)
    for (const [id, f] of this.flightData) {
      if (results.length >= MAX) break
      const cs = (f.callsign || "").toLowerCase()
      const ic = (f.id || "").toLowerCase()
      const airlineCode = this._extractAirlineCode(f.callsign)
      const airlineName = airlineCode ? this._getAirlineName(airlineCode).toLowerCase() : ""
      if (cs.includes(q) || ic.includes(q) || airlineName.includes(q)) {
        const isMil = this._isMilitaryFlight(f)
        results.push({
          type: "flight",
          icon: isMil ? "fa-jet-fighter" : "fa-plane",
          color: isMil ? "#ef5350" : "#4fc3f7",
          name: f.callsign || f.id,
          detail: airlineCode ? this._getAirlineName(airlineCode) : (f.originCountry || ""),
          lat: f.currentLat,
          lng: f.currentLng,
          alt: f.currentAlt || 200000,
          id,
        })
      }
    }

    // Search ships
    for (const [mmsi, s] of this.shipData) {
      if (results.length >= MAX) break
      const name = (s.name || "").toLowerCase()
      const mmsiStr = mmsi.toLowerCase()
      if (name.includes(q) || mmsiStr.includes(q)) {
        results.push({
          type: "ship",
          icon: "fa-ship",
          color: "#26c6da",
          name: s.name || mmsi,
          detail: s.flag || "",
          lat: s.latitude,
          lng: s.longitude,
          alt: 100000,
        })
      }
    }

    // Search satellites
    for (const s of this.satelliteData) {
      if (results.length >= MAX) break
      const name = (s.name || "").toLowerCase()
      const norad = String(s.norad_id)
      if (name.includes(q) || norad.includes(q)) {
        const sat = window.satellite
        let lat = 0, lng = 0, alt = 500000
        if (sat) {
          try {
            const now = new Date()
            const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
            const posVel = sat.propagate(satrec, now)
            if (posVel.position) {
              const gmst = sat.gstime(now)
              const posGd = sat.eciToGeodetic(posVel.position, gmst)
              lng = sat.degreesLong(posGd.longitude)
              lat = sat.degreesLat(posGd.latitude)
              alt = posGd.height * 1000 + 500000
            }
          } catch { /* skip */ }
        }
        results.push({
          type: "satellite",
          icon: "fa-satellite",
          color: this.satCategoryColors[s.category] || "#ab47bc",
          name: s.name,
          detail: s.category,
          lat, lng, alt,
        })
      }
    }

    // Search earthquakes
    for (const eq of this._earthquakeData) {
      if (results.length >= MAX) break
      const title = (eq.title || "").toLowerCase()
      if (title.includes(q) || `m${eq.mag}`.includes(q)) {
        results.push({
          type: "earthquake",
          icon: "fa-house-crack",
          color: "#ff7043",
          name: `M${eq.mag.toFixed(1)}`,
          detail: eq.title,
          lat: eq.lat,
          lng: eq.lng,
          alt: 500000,
        })
      }
    }

    // Search natural events
    for (const ev of this._naturalEventData) {
      if (results.length >= MAX) break
      const title = (ev.title || "").toLowerCase()
      const cat = (ev.categoryTitle || "").toLowerCase()
      if (title.includes(q) || cat.includes(q)) {
        const catInfo = this.eonetCategoryIcons[ev.categoryId] || { icon: "circle-exclamation", color: "#78909c" }
        results.push({
          type: "event",
          icon: `fa-${catInfo.icon}`,
          color: catInfo.color,
          name: ev.title.length > 30 ? ev.title.substring(0, 28) + "…" : ev.title,
          detail: ev.categoryTitle,
          lat: ev.lat,
          lng: ev.lng,
          alt: 500000,
        })
      }
    }

    // Search airports
    if (this.airportsVisible) {
      for (const [icao, ap] of Object.entries(this._airportDb)) {
        if (results.length >= MAX) break
        if (icao.toLowerCase().includes(q) || ap.name.toLowerCase().includes(q)) {
          results.push({
            type: "airport",
            icon: "fa-plane-departure",
            color: "#ffd54f",
            name: ap.name,
            detail: icao,
            lat: ap.lat,
            lng: ap.lng,
            alt: 200000,
          })
        }
      }
    }

    // Search webcams
    for (const w of this._webcamData) {
      if (results.length >= MAX) break
      const title = (w.title || "").toLowerCase()
      const city = (w.city || "").toLowerCase()
      if (title.includes(q) || city.includes(q)) {
        results.push({
          type: "webcam",
          icon: "fa-video",
          color: "#29b6f6",
          name: w.title.length > 30 ? w.title.substring(0, 28) + "…" : w.title,
          detail: [w.city, w.country].filter(Boolean).join(", "),
          lat: w.lat,
          lng: w.lng,
          alt: 50000,
        })
      }
    }

    // Search cities
    for (const c of this._citiesData) {
      if (results.length >= MAX) break
      if (c.name.toLowerCase().includes(q) || c.country.toLowerCase().includes(q)) {
        results.push({
          type: "city",
          icon: c.capital ? "fa-landmark" : "fa-city",
          color: c.capital ? "#ffd54f" : "#e0e0e0",
          name: c.name,
          detail: `${c.country} · ${(c.population / 1e6).toFixed(1)}M`,
          lat: c.lat,
          lng: c.lng,
          alt: 200000,
        })
      }
    }

    this._renderSearchResults(results, query)
  }

  _renderSearchResults(results, query) {
    if (results.length === 0) {
      this.searchResultsTarget.innerHTML = '<div class="search-empty">No results</div>'
      this.searchResultsTarget.style.display = "block"
      return
    }

    const html = results.map((r, i) => `
      <div class="search-result-row" data-action="click->globe#searchResultClick" data-idx="${i}">
        <span class="search-result-icon" style="color: ${r.color}"><i class="fa-solid ${r.icon}"></i></span>
        <span class="search-result-name">${r.name}</span>
        <span class="search-result-detail">${r.detail}</span>
      </div>
    `).join("")

    this.searchResultsTarget.innerHTML = html
    this.searchResultsTarget.style.display = "block"
    this._searchResults = results
  }

  searchResultClick(event) {
    const idx = parseInt(event.currentTarget.dataset.idx)
    const r = this._searchResults?.[idx]
    if (!r) return

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(r.lng, r.lat, r.alt),
      duration: 1.5,
    })

    // Select/highlight the entity
    if (r.type === "flight" && r.id) {
      this.toggleFlightSelection(r.id)
      const f = this.flightData.get(r.id)
      if (f) this.showDetail(r.id, f)
    }

    this.clearSearch()
  }

  getFlightsDataSource() { return getDataSource(this.viewer, this._ds, "flights") }

  toggleFlights() {
    this.flightsVisible = this.flightsToggleTarget.checked
    if (this._ds["flights"]) {
      this._ds["flights"].show = this.flightsVisible
    }
    if (this.flightsVisible) {
      this.fetchFlights()
      if (!this.flightInterval) {
        this.flightInterval = setInterval(() => this.fetchFlights(), 10000)
        this._flightCameraCb = () => this.fetchFlights()
        this.viewer.camera.moveEnd.addEventListener(this._flightCameraCb)
      }
    } else {
      if (this.flightInterval) { clearInterval(this.flightInterval); this.flightInterval = null }
      if (this._flightCameraCb) { this.viewer.camera.moveEnd.removeEventListener(this._flightCameraCb); this._flightCameraCb = null }
    }
    this._savePrefs()
  }

  async fetchSatCategory(cat) {
    this._toast("Loading satellites...")
    try {
      const response = await fetch(`/api/satellites?category=${cat}`)
      if (!response.ok) return
      const sats = await response.json()
      this._handleBackgroundRefresh(response, `satellites-${cat}`, sats.length > 0, () => {
        if (this.satCategoryVisible[cat]) this.fetchSatCategory(cat)
      })

      // Remove old data for this category, add fresh
      this.satelliteData = this.satelliteData.filter(s => s.category !== cat)
      this.satelliteData.push(...sats)
      this._loadedSatCategories.add(cat)

      this.updateSatellitePositions()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch satellites:", e)
    }
  }

  get satCategoryColors() {
    return {
      stations: "#ff5252",
      starlink: "#ab47bc",
      "gps-ops": "#66bb6a",
      glonass: "#5c6bc0",
      galileo: "#0288d1",
      weather: "#ffa726",
      resource: "#29b6f6",
      science: "#ec407a",
      military: "#ef5350",
      geo: "#78909c",
      iridium: "#26c6da",
      oneweb: "#7e57c2",
      planet: "#8d6e63",
      spire: "#9ccc65",
      gnss: "#42a5f5",
      tdrss: "#78909c",
      radar: "#8d6e63",
      sbas: "#26a69a",
      cubesat: "#ffee58",
      amateur: "#ef5350",
      sarsat: "#ff8a65",
      analyst: "#b71c1c",
      beidou: "#ff6e40",
      molniya: "#d50000",
      globalstar: "#00897b",
      intelsat: "#546e7a",
      ses: "#455a64",
      "x-comm": "#7c4dff",
      geodetic: "#a1887f",
      dmc: "#f06292",
      argos: "#4db6ac",
      "last-30-days": "#ff1744",
    }
  }

  _getSatIcon(color) {
    if (!this._satIcons[color]) {
      this._satIcons[color] = createSatelliteIcon(color)
    }
    return this._satIcons[color]
  }

  // Compute target positions for satellites (called every ~2s)
  // Stores current + next position for smooth lerping in animate()
  updateSatellitePositions() {
    const Cesium = window.Cesium
    const sat = window.satellite
    if (!sat) return

    const dataSource = this.getSatellitesDataSource()
    const now = new Date()
    const future = new Date(now.getTime() + 2000) // 2s ahead for lerp target
    const gmst = sat.gstime(now)
    const gmstF = sat.gstime(future)
    const currentIds = new Set()

    this.satelliteData.forEach(s => {
      if (!this.satCategoryVisible[s.category]) return

      try {
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) return

        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        const lng = sat.degreesLong(posGd.longitude)
        const lat = sat.degreesLat(posGd.latitude)
        const alt = posGd.height * 1000

        if (isNaN(lng) || isNaN(lat) || isNaN(alt)) return

        // Propagate future position for smooth lerping
        const posVelF = sat.propagate(satrec, future)
        let fLng = lng, fLat = lat, fAlt = alt
        if (posVelF.position) {
          const fGd = sat.eciToGeodetic(posVelF.position, gmstF)
          fLng = sat.degreesLong(fGd.longitude)
          fLat = sat.degreesLat(fGd.latitude)
          fAlt = fGd.height * 1000
          if (isNaN(fLng) || isNaN(fLat) || isNaN(fAlt)) { fLng = lng; fLat = lat; fAlt = alt }
        }

        // Apply country/circle filter if active
        if (this.hasActiveFilter() && !this.pointPassesFilter(lat, lng)) return

        const id = `sat-${s.norad_id}`
        currentIds.add(id)
        const color = this.satCategoryColors[s.category] || "#ab47bc"

        // Update selected satellite footprint (hex grid + beam) — store lerp targets for smooth footprint
        if (this.selectedSatNoradId === s.norad_id) {
          this._selectedSatPosition = { lat, lng, alt, altKm: posGd.height, color }
          this._selectedSatGeoLerp = {
            fromLat: lat, fromLng: lng, fromAlt: alt, fromAltKm: posGd.height,
            toLat: fLat, toLng: fLng, toAlt: fAlt, toAltKm: fAlt / 1000,
            startTime: performance.now(), duration: 2000, color,
          }
        }

        // Store lerp data with per-satellite scratch for interpolation
        const posNow = Cesium.Cartesian3.fromDegrees(lng, lat, alt)
        const posNext = Cesium.Cartesian3.fromDegrees(fLng, fLat, fAlt)
        const prev = this._satPrevPositions.get(s.norad_id)
        this._satPrevPositions.set(s.norad_id, {
          from: posNow, to: posNext, startTime: performance.now(), duration: 2000,
          scratch: prev?.scratch || new Cesium.Cartesian3(),
        })

        const existing = this.satelliteEntities.get(id)
        if (existing) {
          // Position updates via CallbackProperty reading _satPrevPositions — no direct assignment needed
        } else {
          const isStation = s.category === "stations"
          const icon = this._getSatIcon(color)
          const noradIdRef = s.norad_id
          const positionCallback = new Cesium.CallbackProperty(() => {
            const ld = this._satPrevPositions.get(noradIdRef)
            if (!ld) return posNow
            const t = Math.min((performance.now() - ld.startTime) / ld.duration, 1.0)
            return Cesium.Cartesian3.lerp(ld.from, ld.to, t, ld.scratch)
          }, false)
          const entity = dataSource.entities.add({
            id,
            position: positionCallback,
            billboard: {
              image: icon,
              scale: isStation ? 1.2 : 0.8,
              scaleByDistance: new Cesium.NearFarScalar(1e6, 1.5, 5e7, 0.6),
              alignedAxis: Cesium.Cartesian3.UNIT_Z,
              disableDepthTestDistance: Number.POSITIVE_INFINITY,
            },
            label: {
              text: s.category === "analyst" && s.purpose ? `${s.norad_id} [${s.purpose}]` : s.name,
              font: isStation ? "bold 15px JetBrains Mono, monospace" : "14px JetBrains Mono, monospace",
              fillColor: Cesium.Color.fromCssColorString(color).withAlpha(isStation ? 1.0 : 0.9),
              outlineColor: Cesium.Color.BLACK,
              outlineWidth: 3,
              style: Cesium.LabelStyle.FILL_AND_OUTLINE,
              verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
              horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
              pixelOffset: new Cesium.Cartesian2(0, isStation ? -16 : -12),
              scaleByDistance: new Cesium.NearFarScalar(5e5, 1, 1e7, 0),
              translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, 8e6, 0),
              disableDepthTestDistance: Number.POSITIVE_INFINITY,
            },
          })
          this.satelliteEntities.set(id, entity)
        }
      } catch {
        // skip invalid TLEs
      }
    })

    // Remove hidden or stale
    for (const [id, entity] of this.satelliteEntities) {
      if (!currentIds.has(id)) {
        dataSource.entities.remove(entity)
        this.satelliteEntities.delete(id)
        // Clean up lerp data
        const noradId = parseInt(id.replace("sat-", ""))
        if (!isNaN(noradId)) this._satPrevPositions.delete(noradId)
      }
    }

    // Remove footprint if selected satellite is gone
    if (this.selectedSatNoradId && !currentIds.has(`sat-${this.selectedSatNoradId}`)) {
      this.clearSatFootprint()
    }

    // Render hex footprint for selected satellite (animation loop handles smooth updates between ticks)
    if (this._selectedSatPosition) {
      this.renderSatHexFootprint(this._selectedSatPosition)
    }

    // Update orbit trails if visible
    if (this.satOrbitsVisible) this.renderSatOrbits()

    // Update coverage heatmap if visible (throttled internally)
    if (this.satHeatmapVisible && (Date.now() - this._heatmapLastUpdate) > 10000) {
      this.renderSatHeatmap()
    }

    // Update build heatmap (uses _lastSatPositions computed by renderSatHeatmap or standalone)
    if (this._buildHeatmapActive && this._buildHeatmapGrid.size > 0) {
      // Compute sat positions if heatmap isn't doing it
      if (!this.satHeatmapVisible && (Date.now() - this._heatmapLastUpdate) > 10000) {
        this._computeSatPositions()
      }
      this._updateBuildHeatmap()
    }

    this._updateStats()
  }

  renderSatOrbits() {
    const Cesium = window.Cesium
    const sat = window.satellite
    if (!sat) return

    const orbitSource = this.getSatOrbitsDataSource()
    const now = new Date()
    const activeIds = new Set()

    // Only render orbits for stations and a subset of others (too many = slow)
    const orbitSats = this.satelliteData.filter(s =>
      this.satCategoryVisible[s.category] &&
      (s.category === "stations" || s.category === "gps-ops" || s.category === "glonass" || s.category === "galileo" || s.category === "weather" || s.category === "military" || s.category === "analyst" || s.category === "gnss" || s.category === "sbas" || s.category === "tdrss")
    )

    orbitSats.forEach(s => {
      const id = `orbit-${s.norad_id}`
      activeIds.add(id)

      if (this.satOrbitEntities.has(id)) return // already created

      try {
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        // Compute one full orbit (~90min for LEO, longer for higher orbits)
        const meanMotion = parseFloat(s.tle_line2.substring(52, 63))
        const periodMin = meanMotion > 0 ? 1440 / meanMotion : 90
        const steps = 120
        const stepMs = (periodMin * 60 * 1000) / steps
        const positions = []

        for (let i = 0; i <= steps; i++) {
          const t = new Date(now.getTime() + i * stepMs)
          const gmst = sat.gstime(t)
          const posVel = sat.propagate(satrec, t)
          if (!posVel.position) continue
          const posGd = sat.eciToGeodetic(posVel.position, gmst)
          const lng = sat.degreesLong(posGd.longitude)
          const lat = sat.degreesLat(posGd.latitude)
          const alt = posGd.height * 1000
          if (!isNaN(lng) && !isNaN(lat) && !isNaN(alt)) {
            positions.push(Cesium.Cartesian3.fromDegrees(lng, lat, alt))
          }
        }

        if (positions.length < 2) return

        const color = this.satCategoryColors[s.category] || "#ab47bc"
        const entity = orbitSource.entities.add({
          id,
          polyline: {
            positions,
            width: 1,
            material: Cesium.Color.fromCssColorString(color).withAlpha(0.25),
            clampToGround: false,
          },
        })
        this.satOrbitEntities.set(id, entity)
      } catch {
        // skip
      }
    })

    // Remove stale orbits
    for (const [id, entity] of this.satOrbitEntities) {
      if (!activeIds.has(id)) {
        orbitSource.entities.remove(entity)
        this.satOrbitEntities.delete(id)
      }
    }
  }

  getSatellitesDataSource() { return getDataSource(this.viewer, this._ds, "satellites") }
  getSatOrbitsDataSource() { return getDataSource(this.viewer, this._ds, "sat-orbits") }

  toggleSatCategory(event) {
    const cat = event.target.dataset.category
    this.satCategoryVisible[cat] = event.target.checked

    // Fetch this category if not loaded yet
    if (event.target.checked && !this._loadedSatCategories.has(cat)) {
      this.fetchSatCategory(cat)
    }

    // Remove entities for this category immediately if unchecked
    if (!event.target.checked) {
      const dataSource = this.getSatellitesDataSource()
      for (const [id, entity] of this.satelliteEntities) {
        const noradId = parseInt(id.replace("sat-", ""))
        const satData = this.satelliteData.find(s => s.norad_id === noradId)
        if (satData && satData.category === cat) {
          dataSource.entities.remove(entity)
          this.satelliteEntities.delete(id)
        }
      }
      // Also remove orbit trails for this category
      const orbitSource = this.getSatOrbitsDataSource()
      for (const [id, entity] of this.satOrbitEntities) {
        const noradId = parseInt(id.replace("orbit-", ""))
        const satData = this.satelliteData.find(s => s.norad_id === noradId)
        if (satData && satData.category === cat) {
          orbitSource.entities.remove(entity)
          this.satOrbitEntities.delete(id)
        }
      }
    } else {
      this.updateSatellitePositions()
    }
    this._savePrefs()
  }

  toggleSatOrbits() {
    this.satOrbitsVisible = this.satOrbitsToggleTarget.checked
    if (this._ds["sat-orbits"]) {
      this._ds["sat-orbits"].show = this.satOrbitsVisible
    }
    if (this.satOrbitsVisible) {
      // Clear cached orbits so they recompute
      this.satOrbitEntities.clear()
      if (this._ds["sat-orbits"]) this._ds["sat-orbits"].entities.removeAll()
      this.renderSatOrbits()
    }
  }

  selectSatFootprint(noradId) {
    this.clearSatFootprint()
    this.selectedSatNoradId = noradId
    this.updateSatellitePositions()
  }

  _clearNadirFootprint() {
    if (this._satFootprintEntities.length > 0 && this._ds["satellites"]) {
      this._satFootprintEntities.forEach(e => this._ds["satellites"].entities.remove(e))
      this._satFootprintEntities = []
    }
    this._nadirLinePositions = null
    this._nadirDotPosition = null
  }

  clearSatFootprint() {
    this.selectedSatNoradId = null
    this._selectedSatPosition = null
    this._selectedSatGeoLerp = null
    this._clearNadirFootprint()
  }

  // ── Satellite Coverage Heatmap ───────────────────────────

  toggleSatHeatmap() {
    this.satHeatmapVisible = this.hasSatHeatmapToggleTarget && this.satHeatmapToggleTarget.checked
    if (!this.satHeatmapVisible) {
      this.clearHeatmap()
      this._heatmapGrid.clear()
      this._heatmapLastUpdate = 0
    } else {
      // Start fresh — heatmap builds from scratch via live sweep
      this._heatmapGrid.clear()
      this._heatmapLastUpdate = 0
      if (this.satelliteData.length > 0) {
        this.renderSatHeatmap()
      }
    }
  }

  clearHeatmap() {
    const ds = this._ds["satellites"]
    if (ds && this._heatmapEntities.length > 0) {
      this._heatmapEntities.forEach(e => ds.entities.remove(e))
    }
    this._heatmapEntities = []
    // Also clear live sweep entities
    if (ds && this._sweepEntities && this._sweepEntities.length > 0) {
      this._sweepEntities.forEach(e => ds.entities.remove(e))
    }
    this._sweepEntities = []
  }

  _computeSatPositions() {
    const sat = window.satellite
    if (!sat || this.satelliteData.length === 0) return

    const nowMs = Date.now()
    this._heatmapLastUpdate = nowMs
    const now = new Date(nowMs)
    const gmst = sat.gstime(now)

    const positions = []
    for (const s of this.satelliteData) {
      if (!this.satCategoryVisible[s.category]) continue
      if (positions.length >= 200) break
      try {
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) continue
        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        const sLng = sat.degreesLong(posGd.longitude)
        const sLat = sat.degreesLat(posGd.latitude)
        const altKm = posGd.height
        if (isNaN(sLng) || isNaN(sLat) || isNaN(altKm)) continue
        const R = 6371
        const scanRadiusKm = R * Math.acos(R / (R + altKm))
        const color = this.satCategoryColors[s.category] || "#ab47bc"
        positions.push({ lat: sLat, lng: sLng, radiusKm: scanRadiusKm, color })
      } catch { /* skip */ }
    }

    this._lastSatPositions = positions
    return positions
  }

  // ── Build Heatmap ─────────────────────────────────────────
  // Projects a full hex grid onto selected countries, then accumulates
  // satellite sweep hits onto those hexes over time.

  toggleBuildHeatmap() {
    this._buildHeatmapActive = this.hasBuildHeatmapToggleTarget && this.buildHeatmapToggleTarget.checked
    if (!this._buildHeatmapActive) {
      this._clearBuildHeatmap()
    } else {
      this._initBuildHeatmap()
    }
    this._savePrefs()
  }

  _initBuildHeatmap() {
    this._clearBuildHeatmap()
    if (this.selectedCountries.size === 0 || !this._selectedCountriesBbox) return

    const Cesium = window.Cesium
    const dataSource = this.getSatellitesDataSource()
    const bb = this._selectedCountriesBbox

    const S = 0.12
    const rowStep = S * 1.5
    const colStep = S * Math.sqrt(3)
    let rendered = 0

    for (let la = bb.minLat; la <= bb.maxLat; la += rowStep) {
      for (let ln = bb.minLng; ln <= bb.maxLng; ln += colStep) {
        if (rendered >= 8000) break
        const cell = this._snapToHexGrid(la, ln)
        if (this._buildHeatmapGrid.has(cell.key)) continue
        if (!this._pointInSelectedCountries(cell.lat, cell.lng)) continue

        const verts = this._buildHexVerts(cell.lat, cell.lng, S)
        const entity = dataSource.entities.add({
          polygon: {
            hierarchy: verts,
            material: Cesium.Color.fromCssColorString("#0d47a1").withAlpha(0.06),
            outline: true,
            outlineColor: Cesium.Color.fromCssColorString("#0d47a1").withAlpha(0.15),
            outlineWidth: 1,
            height: 0,
          },
        })
        this._buildHeatmapGrid.set(cell.key, { lat: cell.lat, lng: cell.lng, hits: 0, entity })
        this._buildHeatmapBaseEntities.push(entity)
        rendered++
      }
    }
  }

  _clearBuildHeatmap() {
    const ds = this._ds["satellites"]
    if (ds) {
      this._buildHeatmapBaseEntities.forEach(e => ds.entities.remove(e))
    }
    this._buildHeatmapBaseEntities = []
    this._buildHeatmapGrid.clear()
  }

  _updateBuildHeatmap() {
    if (!this._buildHeatmapActive || this._buildHeatmapGrid.size === 0) return

    const Cesium = window.Cesium
    const positions = this._lastSatPositions || []
    if (positions.length === 0) return

    const S = 0.12
    const rowStep = S * 1.5
    const colStep = S * Math.sqrt(3)

    // For each satellite, stamp hits on base grid cells within its scan radius
    for (const sp of positions) {
      const radiusDeg = sp.radiusKm / 111.32
      const cosCenter = Math.cos(sp.lat * Math.PI / 180) || 0.01

      for (let la = sp.lat - radiusDeg; la <= sp.lat + radiusDeg; la += rowStep) {
        for (let ln = sp.lng - radiusDeg; ln <= sp.lng + radiusDeg; ln += colStep) {
          const cell = this._snapToHexGrid(la, ln)
          const gridCell = this._buildHeatmapGrid.get(cell.key)
          if (!gridCell) continue

          const dLat = (gridCell.lat - sp.lat) * 111.32
          const dLng = (gridCell.lng - sp.lng) * 111.32 * cosCenter
          const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
          if (distKm > sp.radiusKm) continue

          gridCell.hits++
        }
      }
    }

    // Update visuals based on hit count
    let maxHits = 1
    for (const cell of this._buildHeatmapGrid.values()) {
      if (cell.hits > maxHits) maxHits = cell.hits
    }

    for (const cell of this._buildHeatmapGrid.values()) {
      if (cell.hits === 0) continue
      const t = Math.min(cell.hits / Math.max(maxHits, 1), 1)

      let color
      if (t < 0.2) color = Cesium.Color.fromCssColorString("#0d47a1")
      else if (t < 0.4) color = Cesium.Color.fromCssColorString("#00838f")
      else if (t < 0.6) color = Cesium.Color.fromCssColorString("#2e7d32")
      else if (t < 0.8) color = Cesium.Color.fromCssColorString("#f9a825")
      else color = Cesium.Color.fromCssColorString("#e65100")

      const alpha = 0.15 + t * 0.45
      const extHeight = 100 + cell.hits * 1500

      if (cell.entity && cell.entity.polygon) {
        cell.entity.polygon.material = color.withAlpha(alpha)
        cell.entity.polygon.outlineColor = color.withAlpha(Math.min(alpha + 0.15, 0.8))
        cell.entity.polygon.extrudedHeight = extHeight
      }
    }
  }

  // Snap lat/lng to nearest hex cell on a fixed global grid
  // Pointy-top hex: size S = 0.12° (center-to-vertex)
  // Row spacing = S * 1.5, Col spacing = S * sqrt(3)
  _snapToHexGrid(lat, lng) {
    const S = 0.12
    const sqrt3 = Math.sqrt(3)
    const rowSpacing = S * 1.5
    const colSpacing = S * sqrt3

    const row = Math.round(lat / rowSpacing)
    const offset = (((row % 2) + 2) % 2) * colSpacing * 0.5
    const col = Math.round((lng - offset) / colSpacing)

    return {
      lat: row * rowSpacing,
      lng: col * colSpacing + offset,
      key: `${row},${col}`
    }
  }

  _buildHexVerts(cellLat, cellLng, S) {
    const Cesium = window.Cesium
    const cosLat = Math.cos(cellLat * Math.PI / 180) || 0.01
    const verts = []
    for (let i = 0; i < 6; i++) {
      const angle = (Math.PI / 3) * i + (Math.PI / 6) // pointy-top
      verts.push(Cesium.Cartesian3.fromDegrees(
        cellLng + (S * Math.cos(angle)) / cosLat,
        cellLat + S * Math.sin(angle)
      ))
    }
    return verts
  }

  renderSatHeatmap() {
    const Cesium = window.Cesium
    const sat = window.satellite
    if (!sat || this.satelliteData.length === 0) return

    const nowMs = Date.now()
    const hitLifeMs = this._heatmapHitLifeSec * 1000
    const hasFilter = this.hasActiveFilter()
    const hasCountries = this.selectedCountries.size > 0 && this._selectedCountriesBbox

    // Throttle: only recompute every 10 seconds
    const shouldRecompute = (nowMs - this._heatmapLastUpdate) > 10000

    // Compute satellite positions (needed for both stamping and sweep rendering)
    let satPositions = null
    if (shouldRecompute) {
      this._heatmapLastUpdate = nowMs
      const now = new Date(nowMs)
      const gmst = sat.gstime(now)

      satPositions = []
      for (const s of this.satelliteData) {
        if (!this.satCategoryVisible[s.category]) continue
        if (satPositions.length >= 200) break
        try {
          const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
          const posVel = sat.propagate(satrec, now)
          if (!posVel.position) continue
          const posGd = sat.eciToGeodetic(posVel.position, gmst)
          const sLng = sat.degreesLong(posGd.longitude)
          const sLat = sat.degreesLat(posGd.latitude)
          const altKm = posGd.height
          if (isNaN(sLng) || isNaN(sLat) || isNaN(altKm)) continue
          const R = 6371
          const scanRadiusKm = R * Math.acos(R / (R + altKm))
          const color = this.satCategoryColors[s.category] || "#ab47bc"
          satPositions.push({ lat: sLat, lng: sLng, radiusKm: scanRadiusKm, color })
        } catch { /* skip */ }
      }

      // Cache for sweep rendering
      this._lastSatPositions = satPositions

      // Stamp hex cells — only cells inside selected countries (if any)
      const S = 0.12
      const rowStep = S * 1.5
      const colStep = S * Math.sqrt(3)

      satPositions.forEach(sp => {
        const radiusDeg = sp.radiusKm / 111.32
        const cosCenter = Math.cos(sp.lat * Math.PI / 180) || 0.01

        for (let la = sp.lat - radiusDeg; la <= sp.lat + radiusDeg; la += rowStep) {
          for (let ln = sp.lng - radiusDeg; ln <= sp.lng + radiusDeg; ln += colStep) {
            const cell = this._snapToHexGrid(la, ln)
            const dLat = (cell.lat - sp.lat) * 111.32
            const dLng = (cell.lng - sp.lng) * 111.32 * cosCenter
            const dist = Math.sqrt(dLat * dLat + dLng * dLng)
            if (dist > sp.radiusKm) continue

            if (hasFilter && !this.pointPassesFilter(cell.lat, cell.lng)) continue

            const existing = this._heatmapGrid.get(cell.key)
            if (existing) {
              existing.hits.push(nowMs)
            } else {
              this._heatmapGrid.set(cell.key, { lat: cell.lat, lng: cell.lng, hits: [nowMs] })
            }
          }
        }
      })
    }

    // Prune expired hits
    for (const [key, cell] of this._heatmapGrid) {
      cell.hits = cell.hits.filter(t => (nowMs - t) < hitLifeMs)
      if (cell.hits.length === 0) this._heatmapGrid.delete(key)
    }

    // ── Render ──
    this.clearHeatmap()
    const dataSource = this.getSatellitesDataSource()
    const bounds = hasFilter ? this.getFilterBounds() : this.getViewportBounds()

    // ── 1. Live sweep: render each satellite's current footprint on the country ──
    if (hasCountries) {
      const positions = this._lastSatPositions || []
      const bb = this._selectedCountriesBbox
      const S = 0.12
      const rowStep = S * 1.5
      const colStep = S * Math.sqrt(3)
      let sweepCount = 0

      for (const sp of positions) {
        if (sweepCount >= 2000) break
        const radiusDeg = sp.radiusKm / 111.32
        const cosCenter = Math.cos(sp.lat * Math.PI / 180) || 0.01
        const sweepColor = Cesium.Color.fromCssColorString(sp.color)

        // Intersection of satellite circle with country bbox
        const minLat = Math.max(bb.minLat, sp.lat - radiusDeg)
        const maxLat = Math.min(bb.maxLat, sp.lat + radiusDeg)
        const lngSpread = radiusDeg / cosCenter
        const minLng = Math.max(bb.minLng, sp.lng - lngSpread)
        const maxLng = Math.min(bb.maxLng, sp.lng + lngSpread)
        if (minLat >= maxLat || minLng >= maxLng) continue

        for (let la = minLat; la <= maxLat; la += rowStep) {
          for (let ln = minLng; ln <= maxLng; ln += colStep) {
            if (sweepCount >= 2000) break
            const cell = this._snapToHexGrid(la, ln)
            const dLat = (cell.lat - sp.lat) * 111.32
            const dLng = (cell.lng - sp.lng) * 111.32 * cosCenter
            const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
            if (distKm > sp.radiusKm) continue
            if (!this._pointInSelectedCountries(cell.lat, cell.lng)) continue

            // Don't render sweep hex if there's already a heatmap hex (heatmap takes priority)
            if (this._heatmapGrid.has(cell.key)) continue

            const falloff = Math.max(0, 1 - distKm / sp.radiusKm)
            const verts = this._buildHexVerts(cell.lat, cell.lng, S)
            const entity = dataSource.entities.add({
              polygon: {
                hierarchy: verts,
                material: sweepColor.withAlpha(0.04 + falloff * 0.12),
                outline: true,
                outlineColor: sweepColor.withAlpha(0.12 + falloff * 0.25),
                outlineWidth: 1,
                height: 0,
              },
            })
            this._sweepEntities.push(entity)
            sweepCount++
          }
        }
      }
    }

    // ── 2. Accumulated heatmap hexes ──
    let maxHits = 1
    for (const cell of this._heatmapGrid.values()) {
      if (cell.hits.length > maxHits) maxHits = cell.hits.length
    }

    const S = 0.12
    const heightPerHit = 2000
    let rendered = 0

    for (const cell of this._heatmapGrid.values()) {
      if (rendered >= 4000) break

      if (bounds) {
        if (cell.lat < bounds.lamin - 2 || cell.lat > bounds.lamax + 2 ||
            cell.lng < bounds.lomin - 2 || cell.lng > bounds.lomax + 2) continue
      }

      const count = cell.hits.length
      const t = Math.min(count / Math.max(maxHits, 1), 1)

      let color
      if (t < 0.2) color = Cesium.Color.fromCssColorString("#0d47a1")
      else if (t < 0.4) color = Cesium.Color.fromCssColorString("#00838f")
      else if (t < 0.6) color = Cesium.Color.fromCssColorString("#2e7d32")
      else if (t < 0.8) color = Cesium.Color.fromCssColorString("#f9a825")
      else color = Cesium.Color.fromCssColorString("#e65100")

      const alpha = 0.3 + t * 0.35
      const fillColor = color.withAlpha(alpha)
      const verts = this._buildHexVerts(cell.lat, cell.lng, S)
      const extrudedHeight = 100 + count * heightPerHit

      const entity = dataSource.entities.add({
        polygon: {
          hierarchy: verts,
          material: fillColor,
          outline: true,
          outlineColor: fillColor.withAlpha(Math.min(alpha + 0.1, 0.7)),
          outlineWidth: 1,
          extrudedHeight: extrudedHeight,
          height: 0,
        },
      })
      this._heatmapEntities.push(entity)
      rendered++
    }
  }

  renderSatHexFootprint({ lat, lng, alt, altKm, color }) {
    const Cesium = window.Cesium
    const dataSource = this.getSatellitesDataSource()

    const baseColor = Cesium.Color.fromCssColorString(color)
    const satPos = Cesium.Cartesian3.fromDegrees(lng, lat, alt)

    const R = 6371
    const scanRadiusKm = R * Math.acos(R / (R + altKm))
    const scanRadiusDeg = scanRadiusKm / 111.32
    const cosLat = Math.cos(lat * Math.PI / 180) || 0.01

    // Country-constrained mode: destroy & rebuild (infrequent, complex geometry)
    if (this._satFootprintCountryMode && this.selectedCountries.size > 0 && this._selectedCountriesBbox) {
      this._clearNadirFootprint()
      this._renderCountryConstrainedHexes(baseColor, lat, lng, scanRadiusKm, scanRadiusDeg, satPos)
      return
    }

    const S = 0.12
    const rowH = S * 1.5
    const colW = S * Math.sqrt(3)
    const cosCenter = Math.cos(lat * Math.PI / 180) || 0.01

    const hexOffsets = [
      [-1, -0.5], [-1, 0.5],
      [ 0, -1],   [ 0, 0], [ 0, 1],
      [ 1, -0.5], [ 1, 0.5],
    ]

    // Reuse existing entities if count matches (7 hexes + 1 line + 1 dot = 9)
    const needsCreate = !this._satFootprintEntities || this._satFootprintEntities.length !== 9

    if (needsCreate) {
      // Clear old entities
      this._clearNadirFootprint()

      // Create 7 hex polygons
      hexOffsets.forEach(([dr, dc]) => {
        const hexLat = lat + dr * rowH
        const hexLng = lng + dc * colW / cosCenter
        const dLat = dr * rowH * 111.32
        const dLng = dc * colW * 111.32
        const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
        const falloff = Math.max(0, 1 - distKm / (scanRadiusKm * 0.05))

        const entity = dataSource.entities.add({
          polygon: {
            hierarchy: new Cesium.PolygonHierarchy(this._buildHexVerts(hexLat, hexLng, S)),
            material: baseColor.withAlpha(0.12 + falloff * 0.25),
            outline: true,
            outlineColor: baseColor.withAlpha(0.35 + falloff * 0.5),
            outlineWidth: 1.5,
            height: 0,
          },
        })
        this._satFootprintEntities.push(entity)
      })

      // Nadir line — use CallbackProperty so Cesium doesn't rebuild geometry each frame
      this._nadirLinePositions = [satPos, Cesium.Cartesian3.fromDegrees(lng, lat, 0)]
      this._satFootprintEntities.push(dataSource.entities.add({
        polyline: {
          positions: new Cesium.CallbackProperty(() => this._nadirLinePositions, false),
          width: 3,
          material: baseColor.withAlpha(0.6),
        },
      }))

      // Nadir dot — use CallbackProperty for position
      this._nadirDotPosition = Cesium.Cartesian3.fromDegrees(lng, lat, 0)
      this._satFootprintEntities.push(dataSource.entities.add({
        position: new Cesium.CallbackProperty(() => this._nadirDotPosition, false),
        point: {
          pixelSize: 7,
          color: baseColor.withAlpha(0.9),
          outlineColor: baseColor.withAlpha(0.3),
          outlineWidth: 8,
        },
      }))
    } else {
      // Update existing entities in-place — no destroy/recreate
      hexOffsets.forEach(([dr, dc], i) => {
        const hexLat = lat + dr * rowH
        const hexLng = lng + dc * colW / cosCenter
        this._satFootprintEntities[i].polygon.hierarchy = new Cesium.PolygonHierarchy(this._buildHexVerts(hexLat, hexLng, S))
      })

      // Update nadir line + dot via their backing references (CallbackProperty reads these)
      this._nadirLinePositions = [satPos, Cesium.Cartesian3.fromDegrees(lng, lat, 0)]
      this._nadirDotPosition = Cesium.Cartesian3.fromDegrees(lng, lat, 0)
    }
  }

  _renderCountryConstrainedHexes(baseColor, satLat, satLng, scanRadiusKm, scanRadiusDeg, satPos) {
    const Cesium = window.Cesium
    const dataSource = this.getSatellitesDataSource()
    const bb = this._selectedCountriesBbox

    // Hex grid params — use the heatmap grid size for consistency
    const S = 0.12
    const sqrt3 = Math.sqrt(3)
    const rowStep = S * 1.5
    const colStep = S * sqrt3

    // Scan area: intersection of country bbox and satellite scan circle
    const minLat = Math.max(bb.minLat, satLat - scanRadiusDeg)
    const maxLat = Math.min(bb.maxLat, satLat + scanRadiusDeg)
    const cosCenter = Math.cos(satLat * Math.PI / 180) || 0.01
    const lngSpread = scanRadiusDeg / cosCenter
    const minLng = Math.max(bb.minLng, satLng - lngSpread)
    const maxLng = Math.min(bb.maxLng, satLng + lngSpread)

    if (minLat >= maxLat || minLng >= maxLng) return

    let rendered = 0

    for (let la = minLat; la <= maxLat; la += rowStep) {
      for (let ln = minLng; ln <= maxLng; ln += colStep) {
        if (rendered >= 3000) break

        const cell = this._snapToHexGrid(la, ln)

        // Must be inside satellite scan radius
        const dLat = (cell.lat - satLat) * 111.32
        const dLng = (cell.lng - satLng) * 111.32 * cosCenter
        const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
        if (distKm > scanRadiusKm) continue

        // Must be inside selected countries
        if (!this._pointInSelectedCountries(cell.lat, cell.lng)) continue

        const cosHex = Math.cos(cell.lat * Math.PI / 180) || 0.01
        const verts = []
        for (let i = 0; i < 6; i++) {
          const angle = (Math.PI / 3) * i + (Math.PI / 6) // pointy-top
          const vLat = cell.lat + S * Math.sin(angle)
          const vLng = cell.lng + (S * Math.cos(angle)) / cosHex
          verts.push(Cesium.Cartesian3.fromDegrees(vLng, vLat))
        }

        const falloff = Math.max(0, 1 - distKm / scanRadiusKm)
        const fillAlpha = 0.1 + falloff * 0.3
        const outlineAlpha = 0.3 + falloff * 0.5
        const extHeight = falloff * 1200

        const entity = dataSource.entities.add({
          polygon: {
            hierarchy: verts,
            material: baseColor.withAlpha(fillAlpha),
            outline: true,
            outlineColor: baseColor.withAlpha(outlineAlpha),
            outlineWidth: 1.5,
            height: 0,
            extrudedHeight: extHeight,
          },
        })
        this._satFootprintEntities.push(entity)
        rendered++
      }
    }

    // Nadir line
    this._satFootprintEntities.push(dataSource.entities.add({
      polyline: {
        positions: [satPos, Cesium.Cartesian3.fromDegrees(satLng, satLat, 0)],
        width: 2,
        material: baseColor.withAlpha(0.6),
      },
    }))

    // Nadir dot
    this._satFootprintEntities.push(dataSource.entities.add({
      position: Cesium.Cartesian3.fromDegrees(satLng, satLat, 0),
      point: {
        pixelSize: 7,
        color: baseColor.withAlpha(0.9),
        outlineColor: baseColor.withAlpha(0.3),
        outlineWidth: 8,
      },
    }))
  }

  toggleSatFootprintCountryMode() {
    this._satFootprintCountryMode = !this._satFootprintCountryMode
    // Force re-render if a satellite is selected
    if (this._selectedSatPosition) {
      this.renderSatHexFootprint(this._selectedSatPosition)
    }
    // Refresh the detail panel to update button state
    if (this.selectedSatNoradId) {
      const satData = this.satelliteData.find(s => s.norad_id === this.selectedSatNoradId)
      if (satData) this.showSatelliteDetail(satData)
    }
  }

  // ── Airports ────────────────────────────────────────────

  getAirportsDataSource() { return getDataSource(this.viewer, this._ds, "airports") }

  async toggleAirports() {
    this.airportsVisible = this.hasAirportsToggleTarget && this.airportsToggleTarget.checked
    if (this.airportsVisible) {
      await this._fetchAirportData()
      this.renderAirports()
    } else {
      this._clearAirportEntities()
    }
    this._savePrefs()
  }

  renderAirports() {
    const Cesium = window.Cesium
    this._clearAirportEntities()
    if (!this.airportsVisible) return

    const dataSource = this.getAirportsDataSource()
    dataSource.show = true
    const hasFilter = this.hasActiveFilter()

    let entries = Object.entries(this._airportDb)

    if (hasFilter) {
      entries = entries.filter(([, ap]) => this.pointPassesFilter(ap.lat, ap.lng))
    }

    const civilColor = Cesium.Color.fromCssColorString("#ffd54f")
    const milColor = Cesium.Color.fromCssColorString("#ef5350")

    for (const [icao, ap] of entries) {
      const isMil = ap.military
      const color = isMil ? milColor : civilColor

      const entity = dataSource.entities.add({
        id: `airport-${icao}`,
        position: Cesium.Cartesian3.fromDegrees(ap.lng, ap.lat, 100),
        point: {
          pixelSize: isMil ? 5 : 6,
          color: color.withAlpha(0.9),
          outlineColor: color.withAlpha(0.35),
          outlineWidth: 4,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.2, 1e7, 0.4),
        },
        label: {
          text: icao,
          font: "12px JetBrains Mono, monospace",
          fillColor: color.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.8),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          pixelOffset: new Cesium.Cartesian2(0, 10),
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1, 5e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0),
        },
      })
      this._airportEntities.push(entity)
    }
  }

  _clearAirportEntities() {
    const ds = this._ds["airports"]
    if (ds) this._airportEntities.forEach(e => ds.entities.remove(e))
    this._airportEntities = []
  }

  showAirportDetail(icao) {
    const ap = this._getAirport(icao)
    if (!ap) return

    const color = ap.military ? "#ef5350" : "#ffd54f"
    const typeLabel = ap.military ? "Military" : (ap.type || "").replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase())
    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign"><i class="fa-solid fa-plane-departure" style="color: ${color};"></i> ${ap.name}</div>
      <div class="detail-country">${ap.municipality ? ap.municipality + ", " : ""}${ap.country || ""}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">ICAO</span>
          <span class="detail-value">${icao}</span>
        </div>
        ${ap.iata ? `<div class="detail-field"><span class="detail-label">IATA</span><span class="detail-value">${ap.iata}</span></div>` : ""}
        <div class="detail-field">
          <span class="detail-label">Type</span>
          <span class="detail-value">${typeLabel}</span>
        </div>
        ${ap.elevation ? `<div class="detail-field"><span class="detail-label">Elevation</span><span class="detail-value">${ap.elevation.toLocaleString()} ft</span></div>` : ""}
        <div class="detail-field">
          <span class="detail-label">Coordinates</span>
          <span class="detail-value">${ap.lat.toFixed(4)}°, ${ap.lng.toFixed(4)}°</span>
        </div>
      </div>
    `
    this.detailPanelTarget.style.display = ""

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ap.lng, ap.lat, 200000),
      duration: 1.5,
    })
  }

  // ── Events (Earthquakes + NASA EONET) ────────────────────

  getEventsDataSource() { return getDataSource(this.viewer, this._ds, "events") }

  toggleEarthquakes() {
    this.earthquakesVisible = this.hasEarthquakesToggleTarget && this.earthquakesToggleTarget.checked
    if (this.earthquakesVisible) {
      this.fetchEarthquakes()
    } else {
      this._clearEarthquakeEntities()
      this._earthquakeData = []
    }
    this._startEventsRefresh()
    this._updateStats()
    this._savePrefs()
  }

  toggleNaturalEvents() {
    this.naturalEventsVisible = this.hasNaturalEventsToggleTarget && this.naturalEventsToggleTarget.checked
    if (this.naturalEventsVisible) {
      this.fetchNaturalEvents()
    } else {
      this._clearNaturalEventEntities()
      this._naturalEventData = []
    }
    this._startEventsRefresh()
    this._updateStats()
    this._savePrefs()
  }

  _startEventsRefresh() {
    if (this._eventsInterval) clearInterval(this._eventsInterval)
    if (this.earthquakesVisible || this.naturalEventsVisible) {
      this._eventsInterval = setInterval(() => {
        if (this.earthquakesVisible) this.fetchEarthquakes()
        if (this.naturalEventsVisible) this.fetchNaturalEvents()
      }, 300000) // refresh every 5 min
    }
  }

  async fetchEarthquakes() {
    if (this._timelineActive) return
    this._toast("Loading earthquakes...")
    try {
      const resp = await fetch("/api/earthquakes")
      if (!resp.ok) return
      this._earthquakeData = await resp.json()
      this._handleBackgroundRefresh(resp, "earthquakes", this._earthquakeData.length > 0, () => {
        if (this.earthquakesVisible && !this._timelineActive) this.fetchEarthquakes()
      })
      this.renderEarthquakes()
      this._updateStats()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch earthquakes:", e)
    }
  }

  renderEarthquakes() {
    const Cesium = window.Cesium
    this._clearEarthquakeEntities()
    const dataSource = this.getEventsDataSource()

    this._earthquakeData.forEach(eq => {
      if (this.hasActiveFilter() && !this.pointPassesFilter(eq.lat, eq.lng)) return

      const mag = eq.mag || 0
      // Size and color by magnitude
      const t = Math.min(Math.max((mag - 2.5) / 5.5, 0), 1) // 2.5–8.0 range
      const pixelSize = 6 + t * 14
      const pulseScale = 2 + t * 4

      let color
      if (mag < 3) color = Cesium.Color.fromCssColorString("#66bb6a")
      else if (mag < 4) color = Cesium.Color.fromCssColorString("#ffa726")
      else if (mag < 5) color = Cesium.Color.fromCssColorString("#ff7043")
      else if (mag < 6) color = Cesium.Color.fromCssColorString("#ef5350")
      else color = Cesium.Color.fromCssColorString("#d50000")

      // Outer pulse ring
      const ring = dataSource.entities.add({
        id: `eq-ring-${eq.id}`,
        position: Cesium.Cartesian3.fromDegrees(eq.lng, eq.lat, 0),
        ellipse: {
          semiMinorAxis: mag * 15000,
          semiMajorAxis: mag * 15000,
          material: color.withAlpha(0.08),
          outline: true,
          outlineColor: color.withAlpha(0.25),
          outlineWidth: 1,
          height: 0,
        },
      })
      this._earthquakeEntities.push(ring)

      // Center point
      const entity = dataSource.entities.add({
        id: `eq-${eq.id}`,
        position: Cesium.Cartesian3.fromDegrees(eq.lng, eq.lat, 0),
        point: {
          pixelSize,
          color: color.withAlpha(0.85),
          outlineColor: color.withAlpha(0.4),
          outlineWidth: pulseScale,
        },
        label: {
          text: `M${mag.toFixed(1)}`,
          font: "13px JetBrains Mono, monospace",
          fillColor: Cesium.Color.WHITE.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.7),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, -pixelSize - 4),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 5e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0),
        },
      })
      this._earthquakeEntities.push(entity)
    })
  }

  _clearEarthquakeEntities() {
    const ds = this._ds["events"]
    if (ds) this._earthquakeEntities.forEach(e => ds.entities.remove(e))
    this._earthquakeEntities = []
  }

  showEarthquakeDetail(eq) {
    const date = new Date(eq.time)
    const ago = this._timeAgo(date)
    const alertBadge = eq.alert ? `<span class="event-alert event-alert-${eq.alert}">${eq.alert.toUpperCase()}</span>` : ""
    const tsunamiBadge = eq.tsunami ? `<span class="event-alert event-alert-tsunami">TSUNAMI</span>` : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign">M${eq.mag.toFixed(1)} Earthquake</div>
      <div class="detail-country">${eq.title}</div>
      <div class="event-badges">${alertBadge}${tsunamiBadge}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Magnitude</span>
          <span class="detail-value">${eq.mag.toFixed(1)} ${eq.magType}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Depth</span>
          <span class="detail-value">${eq.depth.toFixed(1)} km</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Time</span>
          <span class="detail-value">${ago}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Coordinates</span>
          <span class="detail-value">${eq.lat.toFixed(2)}°, ${eq.lng.toFixed(2)}°</span>
        </div>
      </div>
      ${typeof eq.url === "string" && eq.url.startsWith("http") ? `<a href="${eq.url}" target="_blank" rel="noopener" class="detail-track-btn">View on USGS</a>` : ""}
      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${eq.lat}" data-lng="${eq.lng}">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
      </button>
    `
    this.detailPanelTarget.style.display = ""

    // Fly to earthquake
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(eq.lng, eq.lat, 500000),
      duration: 1.5,
    })
  }

  // ── NASA EONET Natural Events ──

  get eonetCategoryIcons() {
    return {
      "wildfires": { icon: "fire", color: "#ff5722" },
      "volcanoes": { icon: "volcano", color: "#e53935" },
      "severeStorms": { icon: "hurricane", color: "#5c6bc0" },
      "seaLakeIce": { icon: "snowflake", color: "#4fc3f7" },
      "floods": { icon: "water", color: "#29b6f6" },
      "drought": { icon: "sun", color: "#ffb300" },
      "dustHaze": { icon: "smog", color: "#8d6e63" },
      "earthquakes": { icon: "house-crack", color: "#ff7043" },
      "landslides": { icon: "hill-rockslide", color: "#795548" },
      "snow": { icon: "snowflake", color: "#e0e0e0" },
      "tempExtremes": { icon: "temperature-high", color: "#ff8f00" },
      "waterColor": { icon: "droplet", color: "#26c6da" },
      "manmade": { icon: "industry", color: "#78909c" },
    }
  }

  async fetchNaturalEvents() {
    if (this._timelineActive) return
    this._toast("Loading natural events...")
    try {
      const resp = await fetch("/api/natural_events")
      if (!resp.ok) return
      this._naturalEventData = await resp.json()
      this._handleBackgroundRefresh(resp, "natural-events", this._naturalEventData.length > 0, () => {
        if (this.naturalEventsVisible && !this._timelineActive) this.fetchNaturalEvents()
      })
      this.renderNaturalEvents()
      this._updateStats()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch EONET events:", e)
    }
  }

  renderNaturalEvents() {
    const Cesium = window.Cesium
    this._clearNaturalEventEntities()
    const dataSource = this.getEventsDataSource()

    this._naturalEventData.forEach(ev => {
      if (this.hasActiveFilter() && !this.pointPassesFilter(ev.lat, ev.lng)) return

      const catInfo = this.eonetCategoryIcons[ev.categoryId] || { icon: "circle-exclamation", color: "#78909c" }
      const color = Cesium.Color.fromCssColorString(catInfo.color)

      // Render event trail if multiple geometry points
      if (ev.geometryPoints.length > 1) {
        const trailPositions = ev.geometryPoints
          .filter(g => g.coordinates && g.coordinates.length >= 2)
          .map(g => Cesium.Cartesian3.fromDegrees(g.coordinates[0], g.coordinates[1], 0))
        if (trailPositions.length > 1) {
          const trail = dataSource.entities.add({
            polyline: {
              positions: trailPositions,
              width: 2,
              material: color.withAlpha(0.4),
              clampToGround: true,
            },
          })
          this._naturalEventEntities.push(trail)
        }
      }

      // Impact area ring
      const ringRadius = ev.magnitudeValue ? Math.min(ev.magnitudeValue * 500, 100000) : 30000
      const ring = dataSource.entities.add({
        id: `eonet-ring-${ev.id}`,
        position: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 0),
        ellipse: {
          semiMinorAxis: ringRadius,
          semiMajorAxis: ringRadius,
          material: color.withAlpha(0.06),
          outline: true,
          outlineColor: color.withAlpha(0.2),
          outlineWidth: 1,
          height: 0,
        },
      })
      this._naturalEventEntities.push(ring)

      // Center point
      const entity = dataSource.entities.add({
        id: `eonet-${ev.id}`,
        position: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 0),
        point: {
          pixelSize: 8,
          color: color.withAlpha(0.9),
          outlineColor: color.withAlpha(0.35),
          outlineWidth: 3,
        },
        label: {
          text: ev.title.length > 30 ? ev.title.substring(0, 28) + "…" : ev.title,
          font: "12px JetBrains Mono, monospace",
          fillColor: Cesium.Color.WHITE.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.7),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, -14),
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1, 5e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(5e4, 1, 8e6, 0),
        },
      })
      this._naturalEventEntities.push(entity)
    })
  }

  _clearNaturalEventEntities() {
    const ds = this._ds["events"]
    if (ds) this._naturalEventEntities.forEach(e => ds.entities.remove(e))
    this._naturalEventEntities = []
  }

  showNaturalEventDetail(ev) {
    const catInfo = this.eonetCategoryIcons[ev.categoryId] || { icon: "circle-exclamation", color: "#78909c" }
    const date = ev.date ? new Date(ev.date) : null
    const ago = date ? this._timeAgo(date) : "—"
    const magStr = ev.magnitudeValue ? `${ev.magnitudeValue} ${ev.magnitudeUnit || ""}` : "—"
    const sourceLinks = (ev.sources || [])
      .filter(s => typeof s.url === "string" && s.url.startsWith("http"))
      .map(s => `<a href="${s.url}" target="_blank" rel="noopener" class="event-source-link">${s.id}</a>`)
      .join(" ")

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign"><i class="fa-solid fa-${catInfo.icon}" style="color: ${catInfo.color};"></i> ${ev.categoryTitle}</div>
      <div class="detail-country">${ev.title}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Category</span>
          <span class="detail-value">${ev.categoryTitle}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Magnitude</span>
          <span class="detail-value">${magStr}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Time</span>
          <span class="detail-value">${ago}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Coordinates</span>
          <span class="detail-value">${ev.lat.toFixed(2)}°, ${ev.lng.toFixed(2)}°</span>
        </div>
        ${ev.geometryPoints.length > 1 ? `
        <div class="detail-field">
          <span class="detail-label">Track Points</span>
          <span class="detail-value">${ev.geometryPoints.length}</span>
        </div>` : ""}
      </div>
      ${sourceLinks ? `<div class="event-sources">Sources: ${sourceLinks}</div>` : ""}
      ${typeof ev.link === "string" && ev.link.startsWith("http") ? `<a href="${ev.link}" target="_blank" rel="noopener" class="detail-track-btn">View on NASA EONET</a>` : ""}
      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${ev.lat}" data-lng="${ev.lng}">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
      </button>
    `
    this.detailPanelTarget.style.display = ""

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 500000),
      duration: 1.5,
    })
  }

  _timeAgo(date) {
    const seconds = Math.floor((Date.now() - date.getTime()) / 1000)
    if (seconds < 60) return "just now"
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
    return `${Math.floor(seconds / 86400)}d ago`
  }

  _escapeHtml(str) {
    if (!str) return ""
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }

  // Extract a URL from a Windy player field, which can be:
  //   - a string URL directly
  //   - an object with { link, embed } properties
  //   - undefined/null
  _extractWindyUrl(field, prop = "link") {
    if (!field) return null
    if (typeof field === "string" && field.startsWith("http")) return field
    if (typeof field === "object") {
      const val = field[prop]
      if (typeof val === "string" && val.startsWith("http")) return val
      // Fallback: try the other prop
      const other = prop === "link" ? "embed" : "link"
      const val2 = field[other]
      if (typeof val2 === "string" && val2.startsWith("http")) return val2
    }
    return null
  }

  // ── Live Cameras (Windy Webcams) ──────────────────────────

  toggleCameras() {
    this.camerasVisible = this.hasCamerasToggleTarget && this.camerasToggleTarget.checked
    if (this.camerasVisible) {
      this.fetchWebcams()
      // Re-fetch when camera moves significantly
      if (!this._webcamMoveHandler) {
        this._webcamMoveHandler = () => {
          if (this.camerasVisible) this._maybeRefetchWebcams()
        }
        this.viewer.camera.moveEnd.addEventListener(this._webcamMoveHandler)
      }
    } else {
      this._clearWebcamEntities()
      this._webcamData = []
    }
    this._updateStats()
    this._savePrefs()
  }

  _maybeRefetchWebcams() {
    const center = this._getViewCenter()
    if (!center) return
    if (this._webcamLastFetchCenter) {
      const dLat = Math.abs(center.lat - this._webcamLastFetchCenter.lat)
      const dLng = Math.abs(center.lng - this._webcamLastFetchCenter.lng)
      const dHeight = Math.abs(center.height - (this._webcamLastFetchCenter.height || 0))
      // Refetch if moved significantly or zoomed a lot
      if (dLat < 0.5 && dLng < 0.5 && dHeight < center.height * 0.3) return
    }
    this.fetchWebcams()
  }

  _getViewCenter() {
    const Cesium = window.Cesium
    if (!this.viewer) return null

    // Ray-pick the center of the screen to find what the user is actually looking at
    const canvas = this.viewer.scene.canvas
    const center = new Cesium.Cartesian2(canvas.clientWidth / 2, canvas.clientHeight / 2)
    const ray = this.viewer.camera.getPickRay(center)
    const intersection = ray ? this.viewer.scene.globe.pick(ray, this.viewer.scene) : null

    if (intersection) {
      const carto = Cesium.Cartographic.fromCartesian(intersection)
      return {
        lat: Cesium.Math.toDegrees(carto.latitude),
        lng: Cesium.Math.toDegrees(carto.longitude),
        height: this.viewer.camera.positionCartographic.height,
      }
    }

    // Fallback: camera's own position (e.g. looking at space)
    const carto = this.viewer.camera.positionCartographic
    return {
      lat: Cesium.Math.toDegrees(carto.latitude),
      lng: Cesium.Math.toDegrees(carto.longitude),
      height: carto.height,
    }
  }

  _getViewportBbox() {
    const Cesium = window.Cesium
    if (!this.viewer) return null
    const canvas = this.viewer.scene.canvas
    const corners = [
      new Cesium.Cartesian2(0, 0),
      new Cesium.Cartesian2(canvas.clientWidth, 0),
      new Cesium.Cartesian2(canvas.clientWidth, canvas.clientHeight),
      new Cesium.Cartesian2(0, canvas.clientHeight),
    ]
    let minLat = 90, maxLat = -90, minLng = 180, maxLng = -180
    let hits = 0
    for (const corner of corners) {
      const ray = this.viewer.camera.getPickRay(corner)
      const pos = ray ? this.viewer.scene.globe.pick(ray, this.viewer.scene) : null
      if (pos) {
        const carto = Cesium.Cartographic.fromCartesian(pos)
        const lat = Cesium.Math.toDegrees(carto.latitude)
        const lng = Cesium.Math.toDegrees(carto.longitude)
        minLat = Math.min(minLat, lat)
        maxLat = Math.max(maxLat, lat)
        minLng = Math.min(minLng, lng)
        maxLng = Math.max(maxLng, lng)
        hits++
      }
    }
    if (hits < 2) return null // Too zoomed out or looking at space
    return { north: maxLat, south: minLat, east: maxLng, west: minLng }
  }

  async fetchWebcams() {
    const bbox = this._getViewportBbox()
    const center = this._getViewCenter()
    if (!center && !bbox) return

    let url
    if (bbox) {
      url = `/api/webcams?north=${bbox.north.toFixed(4)}&south=${bbox.south.toFixed(4)}&east=${bbox.east.toFixed(4)}&west=${bbox.west.toFixed(4)}&limit=50`
    } else {
      // Fallback: nearby search
      const radiusKm = Math.min(Math.max(Math.round(center.height / 5000), 10), 250)
      url = `/api/webcams?lat=${center.lat.toFixed(4)}&lng=${center.lng.toFixed(4)}&radius=${radiusKm}&limit=50`
    }

    this._toast("Loading webcams...")
    try {
      const resp = await fetch(url)
      if (!resp.ok) {
        if (resp.status === 503) console.warn("Windy API key not configured")
        return
      }
      const data = await resp.json()
      this._webcamData = (data.webcams || []).map(w => ({
        id: w.webcamId || w.id,
        title: w.title,
        lat: w.location?.latitude,
        lng: w.location?.longitude,
        city: w.location?.city,
        region: w.location?.region,
        country: w.location?.country,
        thumbnail: w.images?.current?.preview || w.images?.daylight?.preview,
        thumbnailIcon: w.images?.current?.icon || w.images?.daylight?.icon,
        playerUrl: this._extractWindyUrl(w.player?.day, "embed") || this._extractWindyUrl(w.player?.live, "embed"),
        playerLink: this._extractWindyUrl(w.player?.day) || this._extractWindyUrl(w.player?.live) || (typeof w.url === "string" ? w.url : null),
        lastUpdated: w.lastUpdatedOn,
        viewCount: w.viewCount,
      })).filter(w => w.lat != null && w.lng != null)

      this._webcamLastFetchCenter = center
      this.renderWebcams()
      this._updateStats()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch webcams:", e)
    }
  }

  renderWebcams() {
    const Cesium = window.Cesium
    this._clearWebcamEntities()
    const dataSource = this.getEventsDataSource()

    this._webcamData.forEach(w => {
      if (this.hasActiveFilter() && !this.pointPassesFilter(w.lat, w.lng)) return

      const entity = dataSource.entities.add({
        id: `cam-${w.id}`,
        position: Cesium.Cartesian3.fromDegrees(w.lng, w.lat, 0),
        point: {
          pixelSize: 7,
          color: Cesium.Color.fromCssColorString("#29b6f6").withAlpha(0.9),
          outlineColor: Cesium.Color.fromCssColorString("#29b6f6").withAlpha(0.35),
          outlineWidth: 3,
          scaleByDistance: new Cesium.NearFarScalar(1e4, 1.2, 5e6, 0.5),
        },
        label: {
          text: w.title.length > 25 ? w.title.substring(0, 23) + "…" : w.title,
          font: "12px JetBrains Mono, monospace",
          fillColor: Cesium.Color.WHITE.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.6),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, -12),
          scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 3e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(5e4, 1, 5e6, 0),
        },
      })
      this._webcamEntities.push(entity)
    })
  }

  _clearWebcamEntities() {
    const ds = this._ds["events"]
    if (ds) this._webcamEntities.forEach(e => ds.entities.remove(e))
    this._webcamEntities = []
  }

  showWebcamDetail(cam) {
    const updated = cam.lastUpdated ? this._timeAgo(new Date(cam.lastUpdated)) : "—"
    const location = [cam.city, cam.region, cam.country].filter(Boolean).join(", ")
    const thumbHtml = cam.thumbnail
      ? `<div class="webcam-thumb"><img src="${cam.thumbnail}" alt="${cam.title}" loading="lazy"></div>`
      : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign"><i class="fa-solid fa-video" style="color: #29b6f6;"></i> Webcam</div>
      <div class="detail-country">${cam.title}</div>
      ${thumbHtml}
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Location</span>
          <span class="detail-value">${location || "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Updated</span>
          <span class="detail-value">${updated}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Views</span>
          <span class="detail-value">${(cam.viewCount || 0).toLocaleString()}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Coordinates</span>
          <span class="detail-value">${cam.lat.toFixed(3)}°, ${cam.lng.toFixed(3)}°</span>
        </div>
      </div>
      <a href="${typeof cam.playerLink === "string" && cam.playerLink.startsWith("http") ? cam.playerLink : `https://www.windy.com/webcams/${cam.id}`}" target="_blank" rel="noopener" class="detail-track-btn"><i class="fa-solid fa-play"></i> Watch Live</a>
    `
    this.detailPanelTarget.style.display = ""

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(cam.lng, cam.lat, 50000),
      duration: 1.5,
    })
  }

  // ── Ships ────────────────────────────────────────────────

  async fetchShips() {
    if (!this.shipsVisible || this._timelineActive) return

    this._toast("Loading ships...")
    try {
      let url = "/api/ships"
      const bounds = this.getFilterBounds()
      if (bounds) {
        const params = new URLSearchParams(bounds).toString()
        url += `?${params}`
      }

      const response = await fetch(url)
      if (!response.ok) return

      let ships = await response.json()

      if (this.hasActiveFilter()) {
        ships = ships.filter(s => s.latitude && s.longitude && this.pointPassesFilter(s.latitude, s.longitude))
      }

      this.renderShips(ships)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch ships:", e)
    }
  }

  createShipIcon(color) {
    const size = 24
    const canvas = document.createElement("canvas")
    canvas.width = size
    canvas.height = size
    const ctx = canvas.getContext("2d")

    ctx.translate(size / 2, size / 2)

    ctx.fillStyle = color
    ctx.beginPath()
    // Ship shape pointing up (bow at top)
    ctx.moveTo(0, -10)    // bow
    ctx.lineTo(5, -2)     // starboard bow
    ctx.lineTo(5, 7)      // starboard stern
    ctx.lineTo(3, 10)     // stern corner
    ctx.lineTo(-3, 10)
    ctx.lineTo(-5, 7)
    ctx.lineTo(-5, -2)
    ctx.closePath()
    ctx.fill()

    // Bridge/superstructure
    ctx.fillStyle = "rgba(255,255,255,0.3)"
    ctx.fillRect(-3, 0, 6, 4)

    return canvas.toDataURL()
  }

  renderShips(ships) {
    const Cesium = window.Cesium
    const dataSource = this.getShipsDataSource()
    const currentIds = new Set()

    if (!this._shipIcon) {
      this._shipIcon = this.createShipIcon("#26c6da")
    }

    ships.forEach(ship => {
      if (!ship.latitude || !ship.longitude) return

      const mmsi = ship.mmsi
      currentIds.add(mmsi)

      const heading = ship.heading || ship.course || 0
      const speed = ship.speed || 0
      const name = (ship.name || mmsi).trim()

      const existing = this.shipData.get(mmsi)

      if (existing) {
        existing.heading = heading
        existing.speed = speed
        existing.course = ship.course
        existing.destination = ship.destination
        existing.flag = ship.flag
        existing.shipType = ship.ship_type
        existing.name = name
        existing.latitude = ship.latitude
        existing.longitude = ship.longitude
        existing.currentLat = ship.latitude
        existing.currentLng = ship.longitude

        existing.entity.position = Cesium.Cartesian3.fromDegrees(ship.longitude, ship.latitude, 0)
        existing.entity.billboard.rotation = -Cesium.Math.toRadians(heading)
        existing.entity.label.text = name
      } else {
        const entity = dataSource.entities.add({
          id: `ship-${mmsi}`,
          position: Cesium.Cartesian3.fromDegrees(ship.longitude, ship.latitude, 0),
          billboard: {
            image: this._shipIcon,
            scale: 0.8,
            rotation: -Cesium.Math.toRadians(heading),
            alignedAxis: Cesium.Cartesian3.UNIT_Z,
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            scaleByDistance: new Cesium.NearFarScalar(1e4, 1.2, 5e6, 0.3),
          },
          label: {
            text: name,
            font: "14px JetBrains Mono, monospace",
            fillColor: Cesium.Color.fromCssColorString("#26c6da").withAlpha(0.95),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            pixelOffset: new Cesium.Cartesian2(0, -16),
            scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 2e6, 0),
            translucencyByDistance: new Cesium.NearFarScalar(1e4, 1, 5e6, 0),
          },
        })

        this.shipData.set(mmsi, {
          entity,
          mmsi,
          latitude: ship.latitude,
          longitude: ship.longitude,
          currentLat: ship.latitude,
          currentLng: ship.longitude,
          heading,
          speed,
          course: ship.course,
          destination: ship.destination,
          flag: ship.flag,
          shipType: ship.ship_type,
          name,
        })
      }
    })

    // Remove ships no longer in view
    for (const [mmsi, data] of this.shipData) {
      if (!currentIds.has(mmsi)) {
        dataSource.entities.remove(data.entity)
        this.shipData.delete(mmsi)
        if (this.selectedShips.has(mmsi)) {
          this.selectedShips.delete(mmsi)
          this._removeSelectionBox("ship", mmsi)
          this._renderSelectionTray()
        }
      }
    }

    this._updateStats()
  }

  getShipsDataSource() { return getDataSource(this.viewer, this._ds, "ships") }

  _isMilitaryFlight(f) {
    // Server-side classification (preferred — covers expanded ICAO hex ranges + callsign DB)
    if (f.military === true) return true
    if (f.military === false) return false

    // Fallback for playback/cached data without the flag
    const cs = (f.callsign || "").toUpperCase()
    const hex = (f.id || "").toLowerCase()

    if (cs) {
      const milPrefixes = [
        "RCH","RRR","DUKE","EVAC","KING","FORTE","JAKE","HOMER","IRON","DOOM",
        "VIPER","RAGE","REAPER","TOPCAT","NAVY","ARMY","CNV","PAT","NATO","MMF",
        "GAF","BAF","RFR","IAM","ASCOT","RRF","SPAR","SAM","EXEC","CFC","SHF",
        "PLF","HAF","HRZ","TUAF","FAB","RFAF","IAF","ISF","IQF","JOF","KEF",
        "KAF","KUF","LBF","OMF","PAF","QAF","RSF","YAF",
      ]
      for (const p of milPrefixes) {
        if (cs.startsWith(p)) return true
      }
      // Regex patterns for specific military callsigns
      if (/^UAEAF/i.test(cs)) return true
      if (/^RSAF\d/i.test(cs)) return true
      if (/^RJAF/i.test(cs)) return true
      if (/^EAF\d/i.test(cs)) return true
      if (/^TAF\d/i.test(cs)) return true
    }

    // Only dedicated military hex sub-blocks (NOT country-wide allocations)
    if (hex) {
      if (hex >= "ae0000" && hex <= "afffff") return true // US mil block
      if (hex.startsWith("43c")) return true              // UK mil block
      if (hex >= "3a8000" && hex <= "3affff") return true  // France mil block
      if (hex >= "3f4000" && hex <= "3f7fff") return true  // Germany mil block
      if (hex >= "4b8000" && hex <= "4b8fff") return true  // Turkey mil block
    }

    return false
  }

  // ── Airline Lookup & Filter ─────────────────────────────────

  get airlineNames() {
    return {
      AAL: "American", AAR: "Asiana", ACA: "Air Canada", AFR: "Air France",
      AIC: "Air India", ALK: "SriLankan", ANA: "All Nippon", ANZ: "Air NZ",
      AUA: "Austrian", AZA: "Alitalia/ITA", BAW: "British Airways",
      BEL: "Brussels", CAL: "China Airlines", CCA: "Air China",
      CES: "China Eastern", CPA: "Cathay Pacific", CSN: "China Southern",
      DAL: "Delta", DLH: "Lufthansa", EIN: "Aer Lingus", ELY: "El Al",
      ETD: "Etihad", ETH: "Ethiopian", EVA: "EVA Air", EWG: "Eurowings",
      EZY: "easyJet", FDX: "FedEx", FIN: "Finnair", GAF: "German AF",
      GIA: "Garuda", HAL: "Hawaiian", IBE: "Iberia", ICE: "Icelandair",
      JAL: "Japan Airlines", JBU: "JetBlue", KAL: "Korean Air",
      KLM: "KLM", LAN: "LATAM", LOT: "LOT Polish", MAS: "Malaysia",
      MEA: "Middle East", MSR: "EgyptAir", NAX: "Norwegian", OMA: "Oman Air",
      PAL: "Philippine", PIA: "PIA", QFA: "Qantas", QTR: "Qatar",
      RAM: "Royal Air Maroc", RJA: "Royal Jordanian", ROT: "TAROM",
      RYR: "Ryanair", SAS: "SAS", SAA: "South African", SIA: "Singapore",
      SKW: "SkyWest", SLK: "Silk Air", SQC: "SQ Cargo", SVA: "Saudia",
      SWA: "Southwest", SWR: "Swiss", TAP: "TAP Portugal", THA: "Thai",
      THY: "Turkish", TUI: "TUI", UAE: "Emirates", UAL: "United",
      UPS: "UPS", VIR: "Virgin Atlantic", VOZ: "Virgin Aus",
      VJC: "VietJet", WZZ: "Wizz Air", AEE: "Aegean",
      ENY: "Envoy Air", RPA: "Republic", ASA: "Alaska",
      NKS: "Spirit", AAY: "Allegiant", FFT: "Frontier",
      AXM: "AirAsia", SBI: "S7 Airlines", AFL: "Aeroflot",
      CSZ: "Shenzhen", CQH: "Spring Airlines", HVN: "Vietnam Airlines",
      AMX: "Aeromexico", AVA: "Avianca", GOL: "Gol", AZU: "Azul",
      CMP: "Copa", TOM: "TUI Airways", SXS: "SunExpress",
      PGT: "Pegasus", OAL: "Olympic", TAR: "Tunisair",
    }
  }

  _extractAirlineCode(callsign) {
    if (!callsign || callsign.length < 3) return null
    const code = callsign.substring(0, 3).toUpperCase()
    // Must be all letters (ICAO airline codes are 3 alpha chars)
    if (/^[A-Z]{3}$/.test(code)) return code
    return null
  }

  _getAirlineName(code) {
    return this.airlineNames[code] || code
  }

  _detectAirlines() {
    const counts = new Map()
    for (const [, f] of this.flightData) {
      const code = this._extractAirlineCode(f.callsign)
      if (code) {
        counts.set(code, (counts.get(code) || 0) + 1)
      }
    }
    this._detectedAirlines = counts
    this._updateAirlineChips()
  }

  _updateAirlineChips() {
    // Sort by count descending, show top 20
    const sorted = [...this._detectedAirlines.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 20)

    if (sorted.length === 0) {
      if (this.hasAirlineFilterTarget) this.airlineFilterTarget.style.display = "none"
      if (this.hasEntityAirlineBarTarget) this.entityAirlineBarTarget.style.display = "none"
      return
    }

    const html = sorted.map(([code, count]) => {
      const active = this._airlineFilter.has(code) ? " active" : ""
      const name = this._getAirlineName(code)
      return `<span class="airline-chip${active}" data-action="click->globe#toggleAirlineFilter" data-code="${code}" title="${name}">
        ${code}<span class="airline-chip-count">${count}</span>
      </span>`
    }).join("")

    // Update sidebar chips
    if (this.hasAirlineFilterTarget && this.hasAirlineChipsTarget) {
      this.airlineFilterTarget.style.display = this.flightsVisible ? "" : "none"
      this.airlineChipsTarget.innerHTML = html
    }

    // Update entity list chips
    if (this.hasEntityAirlineBarTarget && this.hasEntityAirlineChipsTarget) {
      const entityListVisible = this.entityListPanelTarget.style.display !== "none"
      const activeTab = this.entityListPanelTarget.querySelector(".entity-tab.active")?.dataset.tab
      this.entityAirlineBarTarget.style.display = (entityListVisible && activeTab === "flights") ? "" : "none"
      this.entityAirlineChipsTarget.innerHTML = html
    }
  }

  toggleAirlineFilter(event) {
    const code = event.currentTarget.dataset.code
    if (this._airlineFilter.has(code)) {
      this._airlineFilter.delete(code)
    } else {
      this._airlineFilter.add(code)
    }
    this._updateAirlineChips()
    // Refresh entity list flights tab if visible
    if (this.entityListPanelTarget.style.display !== "none") {
      this.renderEntityTab("flights")
    }
    this._savePrefs()
  }

  _flightPassesAirlineFilter(f) {
    if (this._airlineFilter.size === 0) return true
    const code = this._extractAirlineCode(f.callsign)
    return code && this._airlineFilter.has(code)
  }

  // ── Sidebar & Section Controls ──────────────────────────────

  toggleSidebar() {
    if (this.hasSidebarTarget) {
      this.sidebarTarget.classList.toggle("collapsed")
    }
    this._savePrefs()
  }

  toggleSection(event) {
    const head = event.currentTarget
    head.classList.toggle("open")
    this._savePrefs()
  }

  // ── Quick Layer Bar ─────────────────────────────────────────
  quickToggle(event) {
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
      outages:     { target: "outagesToggle",       method: "toggleOutages" },
      powerPlants: { target: "powerPlantsToggle",  method: "togglePowerPlants" },
      conflicts:   { target: "conflictsToggle",    method: "toggleConflicts" },
      traffic:     { target: "trafficToggle",      method: "toggleTraffic" },
      notams:      { target: "notamsToggle",        method: "toggleNotams" },
    }

    if (layer === "satellites") {
      // Open the satellite section so user can pick categories
      const satSection = this.element.querySelector('[data-section="satellites"] .sb-section-head')
      if (satSection && !satSection.classList.contains("open")) {
        satSection.classList.add("open")
      }
      // Scroll it into view
      satSection?.scrollIntoView({ behavior: "smooth", block: "nearest" })
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

  toggleSatChip(event) {
    const btn = event.currentTarget
    const category = btn.dataset.category
    // Fire the existing toggleSatCategory with a synthetic event
    const syntheticEvent = { target: { dataset: { category }, checked: !this.satCategoryVisible[category] } }
    syntheticEvent.target.checked = !this.satCategoryVisible[category]
    this.toggleSatCategory(syntheticEvent)
    btn.classList.toggle("active", this.satCategoryVisible[category])
    this._syncQuickBar()
    this._updateSatBadge()
  }

  _syncQuickBar() {
    const sync = (targetName, active) => {
      const has = "has" + targetName.charAt(0).toUpperCase() + targetName.slice(1) + "Target"
      if (this[has]) this[targetName + "Target"].classList.toggle("active", active)
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
    sync("qlOutages", this.outagesVisible)
    sync("qlPowerPlants", this.powerPlantsVisible)
    sync("qlConflicts", this.conflictsVisible)
    sync("qlTraffic", this.trafficVisible)
    sync("qlNotams", this.notamsVisible)

    const anySat = Object.values(this.satCategoryVisible).some(v => v)
    sync("qlSatellites", anySat)
  }

  _updateSatBadge() {
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

  _updateStats() {
    if (this.hasStatFlightsTarget) {
      this.statFlightsTarget.textContent = this.flightData.size.toLocaleString()
    }
    if (this.hasStatSatsTarget) {
      const visibleSats = this.satelliteEntities.size
      this.statSatsTarget.textContent = visibleSats.toLocaleString()
    }
    if (this.hasStatShipsTarget) {
      this.statShipsTarget.textContent = this.shipData.size.toLocaleString()
    }
    if (this.hasStatEventsTarget) {
      const count = (this.earthquakesVisible ? this._earthquakeData.length : 0) +
                    (this.naturalEventsVisible ? this._naturalEventData.length : 0) +
                    (this.camerasVisible ? this._webcamData.length : 0) +
                    (this.powerPlantsVisible ? this._powerPlantData.length : 0) +
                    (this.conflictsVisible ? this._conflictData.length : 0)
      this.statEventsTarget.textContent = count.toLocaleString()
    }

    // Keep quick bar and badges in sync
    this._syncQuickBar()
    this._updateSatBadge()
  }

  _updateClock() {
    if (this.hasStatClockTarget) {
      const now = new Date()
      this.statClockTarget.textContent = now.toUTCString().slice(17, 22)
    }
  }

  // ── JS Tooltips ────────────────────────────────────────────

  _initTooltips() {
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

  _savePrefs() {
    if (!this.signedInValue || !this.viewer) return
    clearTimeout(this._savePrefsDebounce)
    this._savePrefsDebounce = setTimeout(() => this._doSavePrefs(), 2000)
  }

  _doSavePrefs() {
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
      outages: this.outagesVisible,
      powerPlants: this.powerPlantsVisible,
      conflicts: this.conflictsVisible,
      traffic: this.trafficVisible,
      notams: this.notamsVisible,
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

  _restorePrefs() {
    const prefs = this.savedPrefsValue
    if (!prefs || Object.keys(prefs).length === 0) return

    this._restoredPrefs = prefs
  }

  _applyRestoredPrefs() {
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
  }

  getShipTypeName(type) {
    const types = {
      0: "Not available",
      30: "Fishing", 31: "Towing", 32: "Towing (large)", 33: "Dredging",
      34: "Diving ops", 35: "Military ops", 36: "Sailing", 37: "Pleasure craft",
      40: "High-speed craft", 50: "Pilot vessel", 51: "SAR vessel",
      52: "Tug", 53: "Port tender", 55: "Law enforcement",
      60: "Passenger", 61: "Passenger (hazardous A)", 69: "Passenger (no info)",
      70: "Cargo", 71: "Cargo (hazardous A)", 79: "Cargo (no info)",
      80: "Tanker", 81: "Tanker (hazardous A)", 89: "Tanker (no info)",
      90: "Other",
    }
    if (!type) return "Unknown"
    // Check exact match first, then by tens (e.g., 71 → 70 range)
    return types[type] || types[Math.floor(type / 10) * 10] || `Type ${type}`
  }

  showShipDetail(data) {
    const mmsi = data.mmsi || data.entity?.id?.replace("ship-", "")
    this._focusedSelection = { type: "ship", id: mmsi }
    this._renderSelectionTray()
    const speedKnots = data.speed ? Math.round(data.speed * 10) / 10 + " kn" : "—"
    const courseDisplay = data.course ? Math.round(data.course) + "°" : "—"
    const headingDisplay = data.heading ? Math.round(data.heading) + "°" : "—"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign">${data.name}</div>
      <div class="detail-country">${data.flag || "Unknown flag"}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Type</span>
          <span class="detail-value">${this.getShipTypeName(data.shipType)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Speed</span>
          <span class="detail-value">${speedKnots}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Course</span>
          <span class="detail-value">${courseDisplay}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Heading</span>
          <span class="detail-value">${headingDisplay}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">MMSI</span>
          <span class="detail-value" style="font-size:12px; opacity:0.7;">${data.entity.id.replace("ship-", "")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Destination</span>
          <span class="detail-value">${data.destination || "—"}</span>
        </div>
      </div>
      <div class="detail-links">
        <a href="https://www.marinetraffic.com/en/ais/details/ships/mmsi:${data.entity.id.replace("ship-", "")}" target="_blank" rel="noopener">MarineTraffic</a>
        <a href="https://www.vesselfinder.com/vessels?mmsi=${data.entity.id.replace("ship-", "")}" target="_blank" rel="noopener">VesselFinder</a>
      </div>
    `
    this.detailPanelTarget.style.display = ""
  }

  toggleShips() {
    this.shipsVisible = this.hasShipsToggleTarget && this.shipsToggleTarget.checked
    if (this._ds["ships"]) {
      this._ds["ships"].show = this.shipsVisible
    }
    if (this.shipsVisible) {
      this.fetchShips()
      if (!this.shipInterval) {
        this.shipInterval = setInterval(() => this.fetchShips(), 15000)
        this._shipCameraCb = () => this.fetchShips()
        this.viewer.camera.moveEnd.addEventListener(this._shipCameraCb)
      }
    } else {
      if (this.shipInterval) { clearInterval(this.shipInterval); this.shipInterval = null }
      if (this._shipCameraCb) { this.viewer.camera.moveEnd.removeEventListener(this._shipCameraCb); this._shipCameraCb = null }
    }
    this._savePrefs()
  }

  // ── Country Borders, Selection & Draw Tool ───────────────

  screenToLatLng(screenPos) { return screenToLatLng(this.viewer, screenPos) }
  haversineDistance(a, b) { return haversineDistance(a, b) }
  pointInPolygon(lat, lng, ring) { return pointInPolygon(lat, lng, ring) }
  findCountryAtPoint(lat, lng) { return findCountryAtPoint(this._countryFeatures, lat, lng) }

  // ── Cities Layer ─────────────────────────────────────────

  toggleCities() {
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

  getCitiesDataSource() { return getDataSource(this.viewer, this._ds, "cities") }

  async loadCities() {
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

  clearCities() {
    const ds = this._ds["cities"]
    if (ds) {
      this._cityEntities.forEach(e => ds.entities.remove(e))
    }
    this._cityEntities = []
  }

  async renderCities() {
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

  toggleCountrySelect() {
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

  toggleTerrain() {
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

  setTerrainExaggeration() {
    const val = this.hasTerrainExaggerationTarget ? parseFloat(this.terrainExaggerationTarget.value) : 1
    this.viewer.scene.verticalExaggeration = val
    const label = this.terrainExaggerationTarget?.closest(".sb-slider-row")?.querySelector(".sb-slider-val")
    if (label) label.textContent = `${val}×`
    this._savePrefs()
  }

  async toggleBuildings() {
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

  toggleBorders() {
    this.bordersVisible = this.hasBordersToggleTarget && this.bordersToggleTarget.checked
    if (this.bordersVisible && !this.bordersLoaded) {
      this.loadBorders()
    }
    if (this._ds["borders"]) {
      this._ds["borders"].show = this.bordersVisible
    }
    this._savePrefs()
  }

  async loadBorders() {
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
        if (this.citiesVisible) this.renderCities()
        if (this.airportsVisible) this._fetchAirportData().then(() => this.renderAirports())
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

  toggleCountrySelection(countryName) {
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
    this.updateEntityList()
    if (this.citiesVisible) this.renderCities()
    if (this.airportsVisible) this._fetchAirportData().then(() => this.renderAirports())
    if (this._buildHeatmapActive) this._initBuildHeatmap()
    this._savePrefs()
  }

  clearCountrySelection() {
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
    this.updateEntityList()
  }

  _updateDeselectBtn() {
    if (this.hasDeselectAllBtnTarget) {
      this.deselectAllBtnTarget.style.display = this.selectedCountries.size > 0 ? "" : "none"
    }
  }

  updateBorderColors() {
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

  showBorderDetail() {
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
        <button class="detail-track-btn" id="clear-selection-btn">Clear Selection</button>
      </div>
    `

    document.getElementById("draw-circle-btn")?.addEventListener("click", () => this.enterDrawMode())
    document.getElementById("clear-selection-btn")?.addEventListener("click", () => this.clearCountrySelection())

    this.detailPanelTarget.style.display = ""
  }

  // ── Draw Circle Tool ────────────────────────────────────

  enterDrawMode() {
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

  exitDrawMode() {
    this.drawMode = false
    this._drawCenter = null
    this.viewer.scene.screenSpaceCameraController.enableRotate = true
    this.viewer.canvas.style.cursor = ""
    this.showBorderDetail()
  }

  showDrawPreview(center, radius) {
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

  removeDrawCircle() {
    if (this._drawCircleEntity && this._ds["borders"]) {
      this._ds["borders"].entities.remove(this._drawCircleEntity)
      this._drawCircleEntity = null
      this._drawRadius = 0
    }
  }

  selectCountriesInCircle(center, radius) {
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
    if (this.citiesVisible) this.renderCities()
    if (this.airportsVisible) this._fetchAirportData().then(() => this.renderAirports())
    this.updateEntityList()
    if (this._buildHeatmapActive) this._initBuildHeatmap()
  }

  getBordersDataSource() { return getDataSource(this.viewer, this._ds, "borders") }

  // ── Camera Controls ──────────────────────────────────────

  resetView() { resetView(this.viewer) }
  viewTopDown() { viewTopDown(this.viewer) }
  resetTilt() { resetTilt(this.viewer) }
  zoomIn() { zoomIn(this.viewer) }
  zoomOut() { zoomOut(this.viewer) }

  // ── Recording ──────────────────────────────────────────────
  toggleRecording() {
    if (this._mediaRecorder && this._mediaRecorder.state === "recording") {
      this._stopRecording()
    } else {
      this._startRecording()
    }
  }

  _startRecording() {
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

  _stopRecording() {
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

  _updateRecordingTimer() {
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

  takeScreenshot() {
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

  toggleTrains() {
    // Placeholder
  }

  // ── News Events ────────────────────────────────────────────

  getNewsDataSource() { return getDataSource(this.viewer, this._ds, "news") }

  static NEWS_REGIONS = {
    "north-america": { latMin: 10, latMax: 85, lngMin: -170, lngMax: -50 },
    "south-america": { latMin: -60, latMax: 15, lngMin: -90, lngMax: -30 },
    "europe":        { latMin: 35, latMax: 72, lngMin: -25, lngMax: 40 },
    "middle-east":   { latMin: 12, latMax: 45, lngMin: 25, lngMax: 65 },
    "africa":        { latMin: -35, latMax: 37, lngMin: -20, lngMax: 55 },
    "central-asia":  { latMin: 25, latMax: 55, lngMin: 40, lngMax: 90 },
    "east-asia":     { latMin: 18, latMax: 55, lngMin: 90, lngMax: 150 },
    "southeast-asia":{ latMin: -15, latMax: 25, lngMin: 90, lngMax: 155 },
    "oceania":       { latMin: -50, latMax: 0, lngMin: 110, lngMax: 180 },
  }

  _pointInRegion(lat, lng, regionKey) {
    if (regionKey === "all") return true
    const r = this.constructor.NEWS_REGIONS[regionKey]
    if (!r) return true
    return lat >= r.latMin && lat <= r.latMax && lng >= r.lngMin && lng <= r.lngMax
  }

  toggleNews() {
    this.newsVisible = this.hasNewsToggleTarget && this.newsToggleTarget.checked
    if (this.newsVisible) {
      this.fetchNews()
      this._newsInterval = setInterval(() => this.fetchNews(), 900000) // 15 min
      if (this.hasNewsArcControlsTarget) this.newsArcControlsTarget.style.display = ""
      if (this.hasNewsFeedPanelTarget) this.newsFeedPanelTarget.style.display = ""
    } else {
      if (this._newsInterval) { clearInterval(this._newsInterval); this._newsInterval = null }
      this._clearNewsEntities()
      this._newsData = []
      if (this.hasNewsArcControlsTarget) this.newsArcControlsTarget.style.display = "none"
      if (this.hasNewsFeedPanelTarget) this.newsFeedPanelTarget.style.display = "none"
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  toggleNewsArcs() {
    this.newsArcsVisible = this.hasNewsArcsToggleTarget && this.newsArcsToggleTarget.checked
    if (!this.newsArcsVisible) {
      this.newsBlobsVisible = false
      if (this.hasNewsBlobsToggleTarget) this.newsBlobsToggleTarget.checked = false
      this._clearNewsArcEntities()
    } else if (this._newsData?.length) {
      this._renderNewsArcs(this._newsData)
    }
  }

  toggleNewsBlobs() {
    this.newsBlobsVisible = this.hasNewsBlobsToggleTarget && this.newsBlobsToggleTarget.checked
    if (this.newsBlobsVisible && !this.newsArcsVisible) {
      this.newsBlobsVisible = false
      if (this.hasNewsBlobsToggleTarget) this.newsBlobsToggleTarget.checked = false
      return
    }
    if (!this.newsBlobsVisible) {
      this._stopNewsArcBlobAnim()
      this._removeNewsBlobEntities()
    } else if (this._newsData?.length) {
      this._clearNewsArcEntities()
      this._renderNewsArcs(this._newsData)
    }
  }

  applyNewsArcFilter() {
    if (!this._newsData?.length) return
    // Clear only arc entities, keep news point entities
    this._clearNewsArcEntities()
    this._renderNewsArcs(this._newsData)
  }

  async fetchNews() {
    if (this._timelineActive) return
    this._toast("Loading news...")
    try {
      const resp = await fetch("/api/news")
      if (!resp.ok) return
      const events = await resp.json()
      this._handleBackgroundRefresh(resp, "news", events.length > 0, () => {
        if (this.newsVisible && !this._timelineActive) this.fetchNews()
      })
      this._newsData = events
      this._renderNews(events)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch news:", e)
    }
  }

  _renderNews(events) {
    this._clearNewsEntities()
    const dataSource = this.getNewsDataSource()

    const categoryColors = {
      conflict: "#f44336",
      unrest: "#ff9800",
      disaster: "#ff5722",
      health: "#e91e63",
      economy: "#ffc107",
      diplomacy: "#4caf50",
      other: "#90a4ae",
    }

    const categoryIcons = {
      conflict: "fa-crosshairs",
      unrest: "fa-bullhorn",
      disaster: "fa-hurricane",
      health: "fa-heart-pulse",
      economy: "fa-chart-line",
      diplomacy: "fa-handshake",
      other: "fa-newspaper",
    }

    // Build coverage count per location (how many articles target each area)
    const coverageMap = new Map()
    events.forEach(ev => {
      const key = `${ev.lat.toFixed(0)},${ev.lng.toFixed(0)}`
      coverageMap.set(key, (coverageMap.get(key) || 0) + 1)
    })

    // Find top 3 most-covered locations
    const top3Counts = [...coverageMap.values()].sort((a, b) => b - a).slice(0, 3)
    const top3Set = new Set(top3Counts)

    events.forEach((ev, i) => {
      const color = categoryColors[ev.category] || "#90a4ae"
      const cesiumColor = Cesium.Color.fromCssColorString(color)

      // Size based on tone intensity + coverage (how many articles about this location)
      const locKey = `${ev.lat.toFixed(0)},${ev.lng.toFixed(0)}`
      const coverage = coverageMap.get(locKey) || 1
      const intensity = Math.min(Math.abs(ev.tone) / 10, 1)
      const coverageBoost = Math.min(Math.log2(coverage + 1) / 3, 1) // log scale, caps at ~8 articles
      let pixelSize = 6 + intensity * 6 + coverageBoost * 8

      // Top 3 most-covered destinations get extra large dots
      if (top3Counts.length >= 3 && coverage >= top3Counts[2]) {
        const rank = coverage >= top3Counts[0] ? 0 : coverage >= top3Counts[1] ? 1 : 2
        pixelSize = [48, 36, 28][rank]
      }

      const entity = dataSource.entities.add({
        id: `news-${i}`,
        position: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 0),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(0.85 + coverageBoost * 0.15),
          outlineColor: cesiumColor.withAlpha(0.3 + coverageBoost * 0.4),
          outlineWidth: 2 + Math.floor(coverageBoost * 4),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.5),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
        label: {
          text: this._truncateNewsLabel(ev.title || ev.name, pixelSize >= 28 ? 50 : 30),
          font: `${pixelSize >= 28 ? 15 : pixelSize >= 20 ? 14 : 13}px DM Sans, sans-serif`,
          fillColor: Cesium.Color.WHITE.withAlpha(pixelSize >= 28 ? 0.95 : 0.85),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: pixelSize >= 28 ? 4 : 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -(pixelSize + 12)),
          scaleByDistance: pixelSize >= 28
            ? new Cesium.NearFarScalar(1e5, 1.2, 1.5e7, 0.5)
            : new Cesium.NearFarScalar(1e5, 1, 5e6, 0),
          translucencyByDistance: pixelSize >= 28
            ? new Cesium.NearFarScalar(1e5, 1.0, 1.5e7, 0.6)
            : new Cesium.NearFarScalar(1e5, 1.0, 5e6, 0),
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: pixelSize >= 28 ? Number.POSITIVE_INFINITY : 0,
        },
        description: `<div style="font-family: 'DM Sans', sans-serif; max-width: 380px;">
          <div style="font-size: 11px; color: ${color}; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 4px;">${ev.category}${ev.source ? ' · ' + ev.source : ''}</div>
          <div style="font-size: 14px; font-weight: 600; margin-bottom: 6px; line-height: 1.3;">${ev.title || ev.name || "Unknown"}</div>
          ${ev.name && ev.title ? '<div style="font-size: 11px; color: #8892a4; margin-bottom: 6px;">' + ev.name + '</div>' : ''}
          <div style="font-size: 11px; color: #aaa; margin-bottom: 8px;">Tone: ${ev.tone} · ${ev.level}</div>
          <div style="font-size: 11px; margin-bottom: 8px;">${(ev.themes || []).map(t => '<span style="display:inline-block;background:rgba(255,255,255,0.1);padding:2px 6px;border-radius:3px;margin:2px;font-size:10px;">' + t.replace(/^.*_/, '') + '</span>').join("")}</div>
          <a href="${ev.url}" target="_blank" rel="noopener" style="color: ${color}; font-size: 11px;">Read article →</a>
          ${ev.time ? '<div style="font-size: 10px; color: #666; margin-top: 6px;">' + new Date(ev.time).toUTCString() + '</div>' : ''}
        </div>`,
      })
      this._newsEntities.push(entity)
    })

    // News attention arcs: source publication → event location
    this._renderNewsArcs(events)

    // Update article list if articles tab is active
    if (this._newsActiveTab === "articles") {
      this._renderNewsArticleList()
      this._setNewsDotOpacity(0.25)
    }
  }

  _getSourceLocation(url) {
    if (!url) return null
    let host
    try { host = new URL(url).hostname.replace(/^www\./, "") } catch { return null }

    // Major publications → city coordinates [lat, lng, name]
    const knownSources = {
      "nytimes.com": [40.76, -73.99, "New York"],
      "washingtonpost.com": [38.90, -77.04, "Washington DC"],
      "cnn.com": [33.75, -84.39, "Atlanta"],
      "foxnews.com": [40.76, -73.99, "New York"],
      "bbc.com": [51.52, -0.13, "London"],
      "bbc.co.uk": [51.52, -0.13, "London"],
      "dailymail.co.uk": [51.52, -0.13, "London"],
      "theguardian.com": [51.52, -0.13, "London"],
      "reuters.com": [51.52, -0.13, "London"],
      "aljazeera.com": [25.29, 51.53, "Doha"],
      "rt.com": [55.75, 37.62, "Moscow"],
      "russian.rt.com": [55.75, 37.62, "Moscow"],
      "lenta.ru": [55.75, 37.62, "Moscow"],
      "aif.ru": [55.75, 37.62, "Moscow"],
      "spiegel.de": [53.55, 9.99, "Hamburg"],
      "stern.de": [53.55, 9.99, "Hamburg"],
      "merkur.de": [48.14, 11.58, "Munich"],
      "lemonde.fr": [48.86, 2.35, "Paris"],
      "radiofrance.fr": [48.86, 2.35, "Paris"],
      "zonebourse.com": [48.86, 2.35, "Paris"],
      "ansa.it": [41.90, 12.50, "Rome"],
      "zazoom.it": [41.90, 12.50, "Rome"],
      "europapress.es": [40.42, -3.70, "Madrid"],
      "aa.com.tr": [39.93, 32.86, "Ankara"],
      "haberler.com": [41.01, 28.98, "Istanbul"],
      "malatyaguncel.com": [38.35, 38.31, "Malatya"],
      "birgun.net": [41.01, 28.98, "Istanbul"],
      "dunya.com": [41.01, 28.98, "Istanbul"],
      "inewsgr.com": [37.98, 23.73, "Athens"],
      "163.com": [30.27, 120.15, "Hangzhou"],
      "sina.com.cn": [31.23, 121.47, "Shanghai"],
      "baidu.com": [39.91, 116.40, "Beijing"],
      "baijiahao.baidu.com": [39.91, 116.40, "Beijing"],
      "china.com": [39.91, 116.40, "Beijing"],
      "81.cn": [39.91, 116.40, "Beijing"],
      "ltn.com.tw": [25.03, 121.57, "Taipei"],
      "yam.com": [25.03, 121.57, "Taipei"],
      "baomoi.com": [21.03, 105.85, "Hanoi"],
      "shorouknews.com": [30.04, 31.24, "Cairo"],
      "almasryalyoum.com": [30.04, 31.24, "Cairo"],
      "moneycontrol.com": [19.08, 72.88, "Mumbai"],
      "naslovi.net": [44.79, 20.47, "Belgrade"],
      "politika.rs": [44.79, 20.47, "Belgrade"],
      "24tv.ua": [50.45, 30.52, "Kyiv"],
      "mignews.com": [32.07, 34.77, "Tel Aviv"],
      "idnes.cz": [50.08, 14.44, "Prague"],
      "heraldcorp.com": [37.57, 126.98, "Seoul"],
      "etoday.co.kr": [37.57, 126.98, "Seoul"],
      "allafrica.com": [38.90, -77.04, "Washington DC"],
      "time.mk": [41.99, 21.43, "Skopje"],
      "lurer.com": [40.18, 44.51, "Yerevan"],
    }

    // Check known sources first
    for (const [domain, loc] of Object.entries(knownSources)) {
      if (host === domain || host.endsWith("." + domain)) {
        return { lat: loc[0], lng: loc[1], city: loc[2] }
      }
    }

    // Fallback: TLD → country centroid
    const tldCountry = {
      "de": [51.0, 9.0, "Germany"], "fr": [46.0, 2.0, "France"], "it": [42.8, 12.8, "Italy"],
      "es": [40.0, -4.0, "Spain"], "nl": [52.5, 5.8, "Netherlands"], "be": [50.8, 4.0, "Belgium"],
      "at": [47.5, 13.5, "Austria"], "ch": [47.0, 8.0, "Switzerland"], "se": [62.0, 15.0, "Sweden"],
      "no": [62.0, 10.0, "Norway"], "dk": [56.0, 10.0, "Denmark"], "fi": [64.0, 26.0, "Finland"],
      "pl": [52.0, 20.0, "Poland"], "cz": [49.8, 15.5, "Czechia"], "sk": [48.7, 19.5, "Slovakia"],
      "hu": [47.0, 20.0, "Hungary"], "ro": [46.0, 25.0, "Romania"], "bg": [43.0, 25.0, "Bulgaria"],
      "hr": [45.2, 15.5, "Croatia"], "rs": [44.0, 21.0, "Serbia"], "ua": [49.0, 32.0, "Ukraine"],
      "ru": [55.75, 37.62, "Russia"], "tr": [39.0, 35.0, "Turkey"], "gr": [39.0, 22.0, "Greece"],
      "pt": [39.5, -8.0, "Portugal"], "ie": [53.0, -8.0, "Ireland"], "gb": [51.52, -0.13, "UK"],
      "uk": [51.52, -0.13, "UK"], "in": [20.0, 77.0, "India"], "cn": [39.91, 116.40, "China"],
      "jp": [36.0, 138.0, "Japan"], "kr": [37.57, 126.98, "S. Korea"], "tw": [25.03, 121.57, "Taiwan"],
      "au": [-25.0, 135.0, "Australia"], "nz": [-42.0, 174.0, "NZ"], "br": [-10.0, -55.0, "Brazil"],
      "ar": [-34.0, -64.0, "Argentina"], "mx": [23.0, -102.0, "Mexico"], "za": [-29.0, 24.0, "S. Africa"],
      "il": [32.07, 34.77, "Israel"], "eg": [30.04, 31.24, "Egypt"], "sa": [25.0, 45.0, "Saudi Arabia"],
      "ae": [24.0, 54.0, "UAE"], "pk": [30.0, 70.0, "Pakistan"], "ir": [32.0, 53.0, "Iran"],
      "mk": [41.99, 21.43, "N. Macedonia"], "am": [40.18, 44.51, "Armenia"],
      "ge": [42.0, 43.5, "Georgia"], "az": [40.5, 47.5, "Azerbaijan"],
      "vn": [21.03, 105.85, "Vietnam"], "th": [15.0, 100.0, "Thailand"],
      "my": [2.5, 112.5, "Malaysia"], "sg": [1.4, 103.8, "Singapore"],
      "ph": [13.0, 122.0, "Philippines"], "id": [-5.0, 120.0, "Indonesia"],
      "ca": [60.0, -95.0, "Canada"], "co": [4.0, -72.0, "Colombia"],
    }

    // Extract TLD (handle co.uk, com.au etc)
    const parts = host.split(".")
    let tld = parts[parts.length - 1]
    if (parts.length >= 3 && ["co", "com", "org", "net"].includes(parts[parts.length - 2])) {
      tld = parts[parts.length - 1] // country part of co.uk etc
    }

    const loc = tldCountry[tld]
    if (loc) return { lat: loc[0], lng: loc[1], city: loc[2] }

    // .com with no known mapping — skip
    return null
  }

  _truncateNewsLabel(text, maxLen) {
    if (!text) return ""
    // Take first meaningful segment (before | or - or :)
    const clean = text.split(/\s*[|–—]\s*/)[0].trim()
    if (clean.length <= maxLen) return clean
    return clean.substring(0, maxLen - 1).trim() + "…"
  }

  _renderNewsArcs(events) {
    if (!this.newsArcsVisible) return
    const Cesium = window.Cesium
    const dataSource = this.getNewsDataSource()

    // Read filter values
    const fromRegion = this.hasNewsArcFromTarget ? this.newsArcFromTarget.value : "all"
    const toRegion = this.hasNewsArcToTarget ? this.newsArcToTarget.value : "all"
    const maxArcs = this.hasNewsArcMaxTarget ? parseInt(this.newsArcMaxTarget.value) : 120

    // Group by source→event pair, tracking individual articles
    const arcMap = new Map()
    this._newsArcData = [] // for click lookups

    events.forEach(ev => {
      const src = this._getSourceLocation(ev.url)
      if (!src) return

      // Skip if source and event are very close (same city/country reporting on itself)
      const dLat = Math.abs(src.lat - ev.lat)
      const dLng = Math.abs(src.lng - ev.lng)
      if (dLat < 2 && dLng < 2) return

      // Apply region filters
      if (!this._pointInRegion(src.lat, src.lng, fromRegion)) return
      if (!this._pointInRegion(ev.lat, ev.lng, toRegion)) return

      let host
      try { host = new URL(ev.url).hostname.replace(/^www\./, "") } catch { return }

      const key = `${src.lat.toFixed(0)},${src.lng.toFixed(0)}→${ev.lat.toFixed(0)},${ev.lng.toFixed(0)}`
      if (!arcMap.has(key)) {
        arcMap.set(key, {
          srcLat: src.lat, srcLng: src.lng, srcCity: src.city,
          evtLat: ev.lat, evtLng: ev.lng, evtName: ev.name?.split(",")[0] || "",
          count: 0, articles: [],
        })
      }
      const entry = arcMap.get(key)
      entry.count++
      if (entry.articles.length < 15) {
        entry.articles.push({ domain: host, url: ev.url, name: ev.name, category: ev.category, tone: ev.tone })
      }
    })

    // Render arcs up to user-selected max
    const arcs = [...arcMap.values()].sort((a, b) => b.count - a.count).slice(0, maxArcs)
    this._newsArcData = arcs

    arcs.forEach((arc, idx) => {
      const alpha = Math.min(0.2 + arc.count * 0.08, 0.6)
      const width = Math.min(1 + arc.count * 0.3, 3)
      const arcColor = Cesium.Color.fromCssColorString("#ffab40").withAlpha(alpha)

      // SLERP arc with lift
      const oLat = arc.srcLat * Math.PI / 180, oLng = arc.srcLng * Math.PI / 180
      const tLat = arc.evtLat * Math.PI / 180, tLng = arc.evtLng * Math.PI / 180
      const SEGS = 30
      const positions = []
      for (let i = 0; i <= SEGS; i++) {
        const f = i / SEGS
        const d = Math.acos(Math.min(1, Math.sin(oLat)*Math.sin(tLat) + Math.cos(oLat)*Math.cos(tLat)*Math.cos(tLng-oLng)))
        if (d < 0.001) break
        const A = Math.sin((1-f)*d)/Math.sin(d)
        const B = Math.sin(f*d)/Math.sin(d)
        const x = A*Math.cos(oLat)*Math.cos(oLng) + B*Math.cos(tLat)*Math.cos(tLng)
        const y = A*Math.cos(oLat)*Math.sin(oLng) + B*Math.cos(tLat)*Math.sin(tLng)
        const z = A*Math.sin(oLat) + B*Math.sin(tLat)
        const lat = Math.atan2(z, Math.sqrt(x*x+y*y)) * 180/Math.PI
        const lng = Math.atan2(y, x) * 180/Math.PI
        const lift = Math.sin(f * Math.PI) * (100000 + d * 800000)
        positions.push(Cesium.Cartesian3.fromDegrees(lng, lat, lift))
      }
      if (positions.length < 2) return

      const entity = dataSource.entities.add({
        id: `news-arc-${idx}`,
        polyline: {
          positions,
          width,
          material: new Cesium.PolylineGlowMaterialProperty({ glowPower: 0.15, color: arcColor }),
        },
      })
      this._newsArcEntities.push(entity)

      // Animated directional blob traveling source → event
      if (this.newsBlobsVisible) {
        const blobColor = Cesium.Color.fromCssColorString("#ffab40")
        const blobCount = Math.min(3, Math.max(1, Math.ceil(arc.count / 3)))
        const speed = 0.1 + (arc.count - 1) * 0.1
        const blobSize = Math.max(5, Math.min(10, 4 + arc.count * 0.5))
        // Per-arc random offset so arcs don't pulse in sync
        const arcPhaseOffset = ((idx * 7.31) % 1.0)  // deterministic pseudo-random per arc
        for (let b = 0; b < blobCount; b++) {
          const blob = dataSource.entities.add({
            id: `news-arc-blob-${idx}-${b}`,
            position: positions[0],
            point: {
              pixelSize: blobSize,
              color: blobColor.withAlpha(0.9),
              outlineColor: blobColor.withAlpha(0.3),
              outlineWidth: 2,
              disableDepthTestDistance: Number.POSITIVE_INFINITY,
              scaleByDistance: new Cesium.NearFarScalar(5e5, 1.2, 1e7, 0.4),
            },
          })
          this._newsArcEntities.push(blob)
          blob._blobArc = positions
          blob._blobPhase = arcPhaseOffset + (b / blobCount)
          blob._blobSpeed = speed
        }
      }

      // Label at midpoint with arrow showing direction
      const midPos = positions[Math.floor(SEGS / 2)]
      const lbl = dataSource.entities.add({
        id: `news-arc-lbl-${idx}`,
        position: midPos,
        label: {
          text: `${arc.srcCity} → ${arc.evtName} (${arc.count})`,
          font: "10px JetBrains Mono, monospace",
          fillColor: Cesium.Color.fromCssColorString("#ffab40").withAlpha(0.85),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, -4),
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1, 1e7, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1.2e7, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._newsArcEntities.push(lbl)
    })

    // Update news feed panel
    this._updateNewsFeed(arcs)
  }

  // Blob animation is now handled by the consolidated animate() loop

  _updateNewsFeed(arcs) {
    if (!this.hasNewsFeedContentTarget) return
    const count = arcs.length
    if (this.hasNewsFeedCountTarget) {
      this.newsFeedCountTarget.textContent = `${count} route${count !== 1 ? "s" : ""}`
    }

    const categoryColors = {
      conflict: "#f44336", unrest: "#ff9800", disaster: "#ff5722",
      health: "#e91e63", economy: "#ffc107", diplomacy: "#4caf50", other: "#90a4ae",
    }

    const html = arcs.map((arc, idx) => {
      // Determine dominant category from articles
      const cats = {}
      arc.articles.forEach(a => { cats[a.category] = (cats[a.category] || 0) + 1 })
      const topCat = Object.entries(cats).sort((a, b) => b[1] - a[1])[0]?.[0] || "other"
      const color = categoryColors[topCat] || "#90a4ae"
      const avgTone = arc.articles.length
        ? (arc.articles.reduce((s, a) => s + (a.tone || 0), 0) / arc.articles.length).toFixed(1)
        : "0"

      const articleList = arc.articles.slice(0, 5).map(a =>
        `<a href="${a.url}" target="_blank" rel="noopener" class="nf-article">${a.domain}</a>`
      ).join("")

      return `<div class="nf-row" data-action="click->globe#focusNewsArc" data-arc-idx="${idx}">
        <div class="nf-route">
          <span class="nf-origin">${arc.srcCity}</span>
          <span class="nf-arrow">→</span>
          <span class="nf-dest">${arc.evtName}</span>
          <span class="nf-badge" style="background:${color}20;color:${color}">${topCat}</span>
        </div>
        <div class="nf-meta">
          <span class="nf-count">${arc.count} article${arc.count !== 1 ? "s" : ""}</span>
          <span class="nf-tone" style="color:${parseFloat(avgTone) < -2 ? "#ef5350" : parseFloat(avgTone) > 2 ? "#66bb6a" : "#90a4ae"}">tone ${avgTone}</span>
        </div>
        <div class="nf-sources">${articleList}</div>
      </div>`
    }).join("")

    this.newsFeedContentTarget.innerHTML = html
  }

  closeNewsFeed() {
    if (this.hasNewsFeedPanelTarget) this.newsFeedPanelTarget.style.display = "none"
    this._setNewsDotOpacity(1.0)
  }

  switchNewsTab(event) {
    const tab = event.currentTarget.dataset.tab
    this._newsActiveTab = tab

    // Toggle active tab button
    const tabs = event.currentTarget.parentElement.children
    for (const t of tabs) t.classList.toggle("nf-tab--active", t.dataset.tab === tab)

    // Show/hide panes
    if (this.hasNewsArticlesPaneTarget) this.newsArticlesPaneTarget.style.display = tab === "articles" ? "" : "none"
    if (this.hasNewsFlowsPaneTarget) this.newsFlowsPaneTarget.style.display = tab === "flows" ? "" : "none"

    if (tab === "articles") {
      this._renderNewsArticleList()
      this._setNewsDotOpacity(0.25)
    } else {
      this._setNewsDotOpacity(1.0)
      // Update count for flows
      const count = this._newsArcData?.length || 0
      if (this.hasNewsFeedCountTarget) this.newsFeedCountTarget.textContent = `${count} flow${count !== 1 ? "s" : ""}`
    }
  }

  filterNewsArticles() {
    this._renderNewsArticleList()
  }

  _renderNewsArticleList() {
    if (!this.hasNewsArticleListTarget) return
    const events = this._newsData || []

    const catFilter = this.hasNewsArticleCatFilterTarget ? this.newsArticleCatFilterTarget.value : "all"
    const search = this.hasNewsArticleSearchTarget ? this.newsArticleSearchTarget.value.toLowerCase().trim() : ""

    const categoryColors = {
      conflict: "#f44336", unrest: "#ff9800", disaster: "#ff5722",
      health: "#e91e63", economy: "#ffc107", diplomacy: "#4caf50", other: "#90a4ae",
    }

    // Filter and sort (newest first)
    const filtered = events
      .map((ev, i) => ({ ...ev, _idx: i }))
      .filter(ev => {
        if (catFilter !== "all" && ev.category !== catFilter) return false
        if (search && !(ev.title || "").toLowerCase().includes(search) &&
            !(ev.name || "").toLowerCase().includes(search) &&
            !(ev.source || "").toLowerCase().includes(search)) return false
        return true
      })
      .sort((a, b) => {
        if (a.time && b.time) return b.time.localeCompare(a.time)
        if (a.time) return -1
        if (b.time) return 1
        return 0
      })

    // Update count
    if (this.hasNewsFeedCountTarget) {
      this.newsFeedCountTarget.textContent = `${filtered.length} article${filtered.length !== 1 ? "s" : ""}`
    }

    if (filtered.length === 0) {
      this.newsArticleListTarget.innerHTML = '<div style="padding:24px 14px;text-align:center;color:var(--gt-text-dim);font:500 11px var(--gt-mono);">No articles match filters</div>'
      return
    }

    const html = filtered.map(ev => {
      const color = categoryColors[ev.category] || "#90a4ae"
      let domain = ev.source || ""
      if (!domain && ev.url) {
        try { domain = new URL(ev.url).hostname.replace(/^www\./, "") } catch {}
      }

      const timeAgo = ev.time ? this._timeAgo(new Date(ev.time)) : ""
      const tone = ev.tone || 0
      let toneBg, toneColor, toneLabel
      if (tone <= -2) { toneBg = "rgba(244,67,54,0.12)"; toneColor = "#ef5350"; toneLabel = "negative" }
      else if (tone >= 2) { toneBg = "rgba(76,175,80,0.12)"; toneColor = "#66bb6a"; toneLabel = "positive" }
      else { toneBg = "rgba(144,164,174,0.1)"; toneColor = "#90a4ae"; toneLabel = "neutral" }

      const title = this._escapeHtml(ev.title || ev.name || "Untitled")

      return `<div class="nf-card" data-action="click->globe#focusNewsArticle" data-news-idx="${ev._idx}">
        <div class="nf-card-bar" style="background:${color};"></div>
        <div class="nf-card-body">
          <div class="nf-card-headline">${title}</div>
          <div class="nf-card-meta">
            <span class="nf-card-source">${this._escapeHtml(domain)}</span>
            ${timeAgo ? `<span class="nf-card-dot">&middot;</span><span class="nf-card-time">${timeAgo}</span>` : ""}
          </div>
          <div class="nf-card-footer">
            <span class="nf-card-tone" style="background:${toneBg};color:${toneColor}">${toneLabel}</span>
            <a href="${this._escapeHtml(ev.url || "#")}" target="_blank" rel="noopener" class="nf-card-link" onclick="event.stopPropagation()" title="Open article"><i class="fa-solid fa-arrow-up-right-from-square"></i></a>
            <button class="nf-card-locate" data-action="click->globe#locateNewsArticle" data-news-idx="${ev._idx}" title="Locate on map"><i class="fa-solid fa-location-crosshairs"></i></button>
          </div>
        </div>
      </div>`
    }).join("")

    this.newsArticleListTarget.innerHTML = html
  }

  focusNewsArticle(event) {
    const idx = parseInt(event.currentTarget.dataset.newsIdx)
    const ev = this._newsData?.[idx]
    if (!ev) return
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 2000000),
      duration: 1.0,
    })
    // Highlight the dot briefly
    const entity = this._newsEntities?.[idx]
    if (entity?.point) {
      const origSize = entity.point.pixelSize?.getValue() || 10
      entity.point.pixelSize = origSize * 2.5
      entity.point.outlineWidth = 6
      setTimeout(() => {
        if (entity.point) {
          entity.point.pixelSize = origSize
          entity.point.outlineWidth = 3
        }
      }, 2000)
    }
  }

  locateNewsArticle(event) {
    event.stopPropagation()
    const idx = parseInt(event.currentTarget.dataset.newsIdx)
    const ev = this._newsData?.[idx]
    if (!ev) return
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 2000000),
      duration: 1.0,
    })
  }

  _setNewsDotOpacity(alpha) {
    const Cesium = window.Cesium
    for (const entity of this._newsEntities) {
      if (entity.point) {
        const c = entity.point.color?.getValue()
        if (c) entity.point.color = new Cesium.Color(c.red, c.green, c.blue, alpha)
        const oc = entity.point.outlineColor?.getValue()
        if (oc) entity.point.outlineColor = new Cesium.Color(oc.red, oc.green, oc.blue, alpha * 0.5)
      }
      if (entity.label) {
        const fc = entity.label.fillColor?.getValue()
        if (fc) entity.label.fillColor = new Cesium.Color(fc.red, fc.green, fc.blue, alpha)
      }
    }
    this.viewer.scene.requestRender()
  }

  focusNewsArc(event) {
    const idx = parseInt(event.currentTarget.dataset.arcIdx)
    const arc = this._newsArcData?.[idx]
    if (!arc) return
    // Fly to midpoint between source and event
    const midLat = (arc.srcLat + arc.evtLat) / 2
    const midLng = (arc.srcLng + arc.evtLng) / 2
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(midLng, midLat, 5000000),
      duration: 1.0,
    })
    // Also show arc detail
    this.showNewsArcDetail(idx)
  }

  showNewsArcDetail(arcIdx) {
    const arc = this._newsArcData?.[arcIdx]
    if (!arc) return

    const categoryColors = {
      conflict: "#f44336", unrest: "#ff9800", disaster: "#ff5722",
      health: "#e91e63", economy: "#ffc107", diplomacy: "#4caf50", other: "#90a4ae",
    }

    const articleList = arc.articles.map(a => {
      const color = categoryColors[a.category] || "#90a4ae"
      const toneColor = a.tone < -2 ? "#f44336" : a.tone > 2 ? "#4caf50" : "#90a4ae"
      return `<div style="padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
        <div style="font:500 10px var(--gt-mono);color:${color};">
          <a href="${this._escapeHtml(a.url)}" target="_blank" rel="noopener" style="color:${color};text-decoration:none;">${this._escapeHtml(a.domain)}</a>
        </div>
        <div style="font:400 9px var(--gt-mono);color:var(--gt-text-dim);line-height:1.3;">${this._escapeHtml(a.name || "")}</div>
        <div style="font:400 9px var(--gt-mono);color:${toneColor};">${a.category} · tone ${a.tone}</div>
      </div>`
    }).join("")

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#ffab40;">
        <i class="fa-solid fa-newspaper" style="margin-right:6px;"></i>Media Attention
      </div>
      <div class="detail-country">${this._escapeHtml(arc.srcCity)} → ${this._escapeHtml(arc.evtName)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Articles</span>
          <span class="detail-value" style="color:#ffab40;">${arc.count}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Source</span>
          <span class="detail-value">${this._escapeHtml(arc.srcCity)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">About</span>
          <span class="detail-value">${this._escapeHtml(arc.evtName)}</span>
        </div>
      </div>
      <div style="margin-top:8px;font:600 9px var(--gt-mono);color:#ffab40;letter-spacing:1px;text-transform:uppercase;">Publishers</div>
      ${articleList}
    `
    this.detailPanelTarget.style.display = ""
  }

  _clearNewsEntities() {
    const ds = this.getNewsDataSource()
    this._newsEntities.forEach(e => ds.entities.remove(e))
    this._newsEntities = []
    this._clearNewsArcEntities()
  }

  _clearNewsArcEntities() {
    this._stopNewsArcBlobAnim()
    const ds = this.getNewsDataSource()
    ;(this._newsArcEntities || []).forEach(e => ds.entities.remove(e))
    this._newsArcEntities = []
  }

  _stopNewsArcBlobAnim() {
    if (this._newsArcBlobRaf) {
      cancelAnimationFrame(this._newsArcBlobRaf)
      this._newsArcBlobRaf = null
    }
  }

  _removeNewsBlobEntities() {
    const ds = this.getNewsDataSource()
    const kept = []
    for (const e of (this._newsArcEntities || [])) {
      if (e._blobArc) {
        ds.entities.remove(e)
      } else {
        kept.push(e)
      }
    }
    this._newsArcEntities = kept
  }

  showNewsDetail(ev) {
    const categoryColors = {
      conflict: "#f44336", unrest: "#ff9800", disaster: "#ff5722",
      health: "#e91e63", economy: "#ffc107", diplomacy: "#4caf50", other: "#90a4ae",
    }
    const categoryIcons = {
      conflict: "fa-crosshairs", unrest: "fa-bullhorn", disaster: "fa-hurricane",
      health: "fa-heart-pulse", economy: "fa-chart-line", diplomacy: "fa-handshake", other: "fa-newspaper",
    }
    const color = categoryColors[ev.category] || "#90a4ae"
    const icon = categoryIcons[ev.category] || "fa-newspaper"

    // Find nearby stories (within ~1° ≈ 111km)
    const nearby = (this._newsData || []).filter(n =>
      n.url !== ev.url &&
      Math.abs(n.lat - ev.lat) < 1.0 &&
      Math.abs(n.lng - ev.lng) < 1.0
    )

    const themeTags = (ev.themes || []).map(t =>
      `<span style="display:inline-block;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.12);padding:2px 7px;border-radius:3px;margin:2px;font-size:10px;color:rgba(200,210,225,0.7);">${t.replace(/^.*_/, "")}</span>`
    ).join("")

    const timeStr = ev.time ? this._timeAgo(new Date(ev.time)) : ""

    const nearbyHtml = nearby.length > 0 ? `
      <div style="margin-top:12px;padding-top:10px;border-top:1px solid rgba(255,255,255,0.08);">
        <div style="font-size:10px;text-transform:uppercase;letter-spacing:1px;color:rgba(200,210,225,0.5);margin-bottom:8px;">
          ${nearby.length} nearby stor${nearby.length === 1 ? "y" : "ies"}
        </div>
        ${nearby.slice(0, 10).map(n => {
          const nColor = categoryColors[n.category] || "#90a4ae"
          const nName = n.name ? n.name.split(",")[0] : "Story"
          return `<a href="${this._escapeHtml(n.url)}" target="_blank" rel="noopener" style="display:block;padding:5px 0;color:rgba(200,210,225,0.8);text-decoration:none;font-size:11px;border-bottom:1px solid rgba(255,255,255,0.04);">
            <span style="color:${nColor};margin-right:4px;">●</span>
            ${this._escapeHtml(nName)}
            <span style="color:rgba(200,210,225,0.4);font-size:10px;margin-left:4px;">${n.category}</span>
          </a>`
        }).join("")}
      </div>
    ` : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid ${icon}" style="margin-right:6px;"></i>${ev.category.charAt(0).toUpperCase() + ev.category.slice(1)}
      </div>
      <div class="detail-country">${this._escapeHtml(ev.name || "Unknown location")}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Sentiment</span>
          <span class="detail-value">${ev.tone} · ${ev.level}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Location</span>
          <span class="detail-value">${ev.lat.toFixed(2)}°, ${ev.lng.toFixed(2)}°</span>
        </div>
        ${timeStr ? `<div class="detail-field">
          <span class="detail-label">Published</span>
          <span class="detail-value">${timeStr}</span>
        </div>` : ""}
      </div>
      <div style="margin:8px 0;">${themeTags}</div>
      <a href="${this._escapeHtml(ev.url)}" target="_blank" rel="noopener" class="detail-track-btn">Read Article →</a>
      ${nearbyHtml}
    `
    this.detailPanelTarget.style.display = ""

    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 300000),
      duration: 1.5,
    })
  }

  // ── GPS Jamming ─────────────────────────────────────────

  getGpsJammingDataSource() { return getDataSource(this.viewer, this._ds, "gpsJamming") }

  toggleGpsJamming() {
    this.gpsJammingVisible = this.hasGpsJammingToggleTarget && this.gpsJammingToggleTarget.checked
    if (this.gpsJammingVisible) {
      this.fetchGpsJamming()
      this._gpsJammingInterval = setInterval(() => this.fetchGpsJamming(), 60000)
    } else {
      if (this._gpsJammingInterval) { clearInterval(this._gpsJammingInterval); this._gpsJammingInterval = null }
      this._clearGpsJammingEntities()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  async fetchGpsJamming() {
    if (this._timelineActive) return
    this._toast("Loading GPS jamming...")
    try {
      const resp = await fetch("/api/gps_jamming")
      if (!resp.ok) return
      const cells = await resp.json()
      this._renderGpsJamming(cells)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch GPS jamming data:", e)
    }
  }

  _renderGpsJamming(cells) {
    this._clearGpsJammingEntities()
    const dataSource = this.getGpsJammingDataSource()
    const Cesium = window.Cesium

    if (cells.length === 0) return

    const colors = {
      low: Cesium.Color.fromCssColorString("rgba(255, 152, 0, 0.25)"),
      medium: Cesium.Color.fromCssColorString("rgba(255, 87, 34, 0.45)"),
      high: Cesium.Color.fromCssColorString("rgba(244, 67, 54, 0.55)")
    }
    const outlines = {
      low: Cesium.Color.fromCssColorString("rgba(255, 152, 0, 0.5)"),
      medium: Cesium.Color.fromCssColorString("rgba(255, 87, 34, 0.8)"),
      high: Cesium.Color.fromCssColorString("rgba(244, 67, 54, 0.9)")
    }

    const hexRadius = 0.5 // degrees — matches backend HEX_SIZE for flush tiling

    cells.forEach(cell => {
      const hexPoints = this._hexVertices(cell.lat, cell.lng, hexRadius)
      const positions = hexPoints.map(p => Cesium.Cartesian3.fromDegrees(p[1], p[0]))

      const hexEntity = dataSource.entities.add({
        id: `jam-${cell.lat}-${cell.lng}`,
        polygon: {
          hierarchy: new Cesium.PolygonHierarchy(positions),
          material: colors[cell.level] || colors.medium,
          outline: true,
          outlineColor: outlines[cell.level] || outlines.medium,
          outlineWidth: 2,
          height: 0,
        },
        description: `<div style="font-family: 'DM Sans', sans-serif;">
          <div style="font-size: 15px; font-weight: 600; margin-bottom: 6px;">GPS Interference</div>
          <div style="font-size: 13px; color: ${cell.level === 'high' ? '#f44336' : '#ffc107'}; font-weight: 600; margin-bottom: 4px;">${cell.level.toUpperCase()} — ${cell.pct}%</div>
          <div style="font-size: 12px; color: #aaa;">${cell.bad} of ${cell.total} aircraft with degraded accuracy</div>
          <div style="font-size: 11px; color: #666; margin-top: 6px;">NACp ≤ 6 indicates GPS jamming or spoofing</div>
        </div>`,
      })
      this._gpsJammingEntities.push(hexEntity)

      // Label only for medium/high
      if (cell.level !== "low") {
        const labelEntity = dataSource.entities.add({
          id: `jam-lbl-${cell.lat}-${cell.lng}`,
          position: Cesium.Cartesian3.fromDegrees(cell.lng, cell.lat, 200),
          label: {
            text: `⚠ ${cell.pct}%`,
            font: "13px DM Sans, sans-serif",
            fillColor: cell.level === "high" ? Cesium.Color.fromCssColorString("#ff5252") : Cesium.Color.fromCssColorString("#ffd54f"),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1.0, 8e6, 0.4),
          },
        })
        this._gpsJammingEntities.push(labelEntity)
      }
    })
  }

  // Generate 6 vertices of a flat-top hexagon at (lat, lng) with given radius in degrees.
  // Corrects longitude for latitude so hexagons appear regular on the globe.
  _hexVertices(lat, lng, radius) {
    const vertices = []
    const cosLat = Math.cos(lat * Math.PI / 180)
    const lngR = cosLat > 0.01 ? radius / cosLat : radius
    for (let i = 0; i < 6; i++) {
      const angle = (Math.PI / 3) * i  // flat-top: 0°, 60°, 120°...
      vertices.push([
        lat + radius * Math.sin(angle),
        lng + lngR * Math.cos(angle),
      ])
    }
    return vertices
  }

  _clearGpsJammingEntities() {
    const ds = this.getGpsJammingDataSource()
    this._gpsJammingEntities.forEach(e => ds.entities.remove(e))
    this._gpsJammingEntities = []
  }

  // ── Submarine Cables ──────────────────────────────────────

  getCablesDataSource() { return getDataSource(this.viewer, this._ds, "cables") }

  toggleCables() {
    this.cablesVisible = this.hasCablesToggleTarget && this.cablesToggleTarget.checked
    if (this.cablesVisible) {
      this.fetchCables()
    } else {
      this._clearCableEntities()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  async fetchCables() {
    this._toast("Loading submarine cables...")
    try {
      const resp = await fetch("/api/submarine_cables")
      if (!resp.ok) return
      const data = await resp.json()
      const hasData = (data.cables?.length || 0) > 0 || (data.landingPoints?.length || 0) > 0
      this._handleBackgroundRefresh(resp, "submarine-cables", hasData, () => {
        if (this.cablesVisible) this.fetchCables()
      })
      this._renderCables(data.cables, data.landingPoints)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch submarine cables:", e)
    }
  }

  _renderCables(cables, landingPoints) {
    this._clearCableEntities()
    const Cesium = window.Cesium
    const dataSource = this.getCablesDataSource()

    // Render cable polylines
    cables.forEach(cable => {
      const color = Cesium.Color.fromCssColorString(cable.color || "#00bcd4").withAlpha(0.6)
      const coords = cable.coordinates || []

      // Each cable may have multiple segments (array of arrays of [lng, lat])
      coords.forEach((segment, si) => {
        if (!Array.isArray(segment) || segment.length < 2) return
        const positions = segment.map(pt => {
          if (Array.isArray(pt) && pt.length >= 2) {
            return Cesium.Cartesian3.fromDegrees(pt[0], pt[1], -50)
          }
          return null
        }).filter(p => p !== null)

        if (positions.length < 2) return

        const entity = dataSource.entities.add({
          id: `cable-${cable.id}-${si}`,
          polyline: {
            positions,
            width: 1.5,
            material: new Cesium.PolylineGlowMaterialProperty({
              glowPower: 0.15,
              color,
            }),
            clampToGround: false,
          },
          properties: {
            cableName: cable.name,
            cableId: cable.id,
          },
        })
        this._cableEntities.push(entity)
      })
    })

    // Render landing points
    if (landingPoints) {
      landingPoints.forEach(lp => {
        const entity = dataSource.entities.add({
          id: `landing-${lp.id}`,
          position: Cesium.Cartesian3.fromDegrees(lp.lng, lp.lat, 0),
          point: {
            pixelSize: 4,
            color: Cesium.Color.fromCssColorString("#00e5ff").withAlpha(0.9),
            outlineColor: Cesium.Color.fromCssColorString("#00838f").withAlpha(0.5),
            outlineWidth: 1,
            scaleByDistance: new Cesium.NearFarScalar(5e4, 1.2, 5e6, 0.3),
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          },
          label: {
            text: lp.name || "",
            font: "10px JetBrains Mono, monospace",
            fillColor: Cesium.Color.fromCssColorString("#80deea").withAlpha(0.8),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 2,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: new Cesium.Cartesian2(0, -10),
            scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 2e6, 0),
            translucencyByDistance: new Cesium.NearFarScalar(1e4, 1.0, 3e6, 0),
          },
        })
        this._landingPointEntities.push(entity)
      })
    }

    // Cross-layer: highlight landing points in attacked countries
    if (this.trafficVisible && this._attackedCountries?.size) {
      this._refreshCableAttackHighlights()
    }
  }

  _clearCableEntities() {
    const ds = this.getCablesDataSource()
    this._cableEntities.forEach(e => ds.entities.remove(e))
    this._cableEntities = []
    this._landingPointEntities.forEach(e => ds.entities.remove(e))
    this._landingPointEntities = []
  }

  _refreshCableAttackHighlights() {
    this._clearCableAttackHighlights()
    if (!this.trafficVisible || !this._attackedCountries?.size || !this._landingPointEntities.length) return
    if (!this._countryFeatures.length) return // need borders data for country lookup

    const Cesium = window.Cesium
    const dataSource = this.getCablesDataSource()
    this._cableAttackEntities = []

    this._landingPointEntities.forEach(e => {
      const pos = e.position?.getValue(Cesium.JulianDate.now())
      if (!pos) return
      const carto = Cesium.Cartographic.fromCartesian(pos)
      const lat = Cesium.Math.toDegrees(carto.latitude)
      const lng = Cesium.Math.toDegrees(carto.longitude)
      const country = findCountryAtPoint(this._countryFeatures, lat, lng)
      const code = country?.properties?.ISO_A2 || country?.properties?.iso_a2
      if (!code || !this._attackedCountries.has(code)) return

      const ring = dataSource.entities.add({
        id: `cable-atk-${e.id}`,
        position: Cesium.Cartesian3.fromDegrees(lng, lat, 0),
        point: {
          pixelSize: 8,
          color: Cesium.Color.RED.withAlpha(0.8),
          outlineColor: Cesium.Color.RED.withAlpha(0.3),
          outlineWidth: 4,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.4, 5e6, 0.4),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
      })
      this._cableAttackEntities.push(ring)
    })
  }

  _clearCableAttackHighlights() {
    if (!this._cableAttackEntities) return
    const ds = this._ds["cables"]
    if (ds) {
      this._cableAttackEntities.forEach(e => ds.entities.remove(e))
    }
    this._cableAttackEntities = []
  }

  // ── Internet Outages ─────────────────────────────────────

  getOutagesDataSource() { return getDataSource(this.viewer, this._ds, "outages") }

  toggleOutages() {
    this.outagesVisible = this.hasOutagesToggleTarget && this.outagesToggleTarget.checked
    if (this.outagesVisible) {
      this.fetchOutages()
      this._outageInterval = setInterval(() => this.fetchOutages(), 300000) // 5min
    } else {
      if (this._outageInterval) clearInterval(this._outageInterval)
      this._clearOutageEntities()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  async fetchOutages() {
    if (this._timelineActive) return
    this._toast("Loading outages...")
    try {
      const resp = await fetch("/api/internet_outages")
      if (!resp.ok) return
      const data = await resp.json()
      const hasData = (data.summary?.length || 0) > 0 || (data.events?.length || 0) > 0
      this._handleBackgroundRefresh(resp, "internet-outages", hasData, () => {
        if (this.outagesVisible && !this._timelineActive) this.fetchOutages()
      })
      this._outageData = data.summary || []
      this._renderOutages(data)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch internet outages:", e)
    }
  }

  _renderOutages(data) {
    this._clearOutageEntities()
    const Cesium = window.Cesium
    const dataSource = this.getOutagesDataSource()

    const levelColors = {
      critical: "#e040fb",
      severe: "#f44336",
      moderate: "#ff9800",
      minor: "#ffc107",
    }

    // Country centroids for rendering (ISO-2 to approx lat/lng)
    const countryCentroids = {
      AD:[42.5,1.5],AE:[24,54],AF:[33,65],AG:[17.1,-61.8],AL:[41,20],AM:[40,45],AO:[-12.5,18.5],AR:[-34,-64],AT:[47.5,13.5],AU:[-25,135],AW:[12.5,-70],AZ:[40.5,47.5],BA:[44,18],BB:[13.2,-59.5],BD:[24,90],BE:[50.8,4],BF:[13,-1.5],BG:[43,25],BH:[26,50.6],BI:[-3.5,30],BJ:[9.5,2.25],BM:[32.3,-64.8],BN:[4.5,114.7],BO:[-17,-65],BR:[-10,-55],BS:[25,-77.4],BT:[27.5,90.5],BW:[-22,24],BY:[53,28],BZ:[17.2,-88.5],CA:[60,-95],CD:[-2.5,23.5],CF:[7,21],CG:[-1,15],CH:[47,8],CI:[8,-5.5],CL:[-30,-71],CM:[6,12],CN:[35,105],CO:[4,-72],CR:[10,-84],CU:[22,-80],CV:[16,-24],CW:[12.2,-69],CY:[35,33],CZ:[49.75,15.5],DE:[51,9],DJ:[11.5,43],DK:[56,10],DO:[19,-70.7],DZ:[28,3],EC:[-2,-77.5],EE:[59,26],EG:[27,30],ER:[15,39],ES:[40,-4],ET:[8,38],FI:[64,26],FJ:[-18,179],FO:[62,-7],FR:[46,2],GA:[-1,11.8],GB:[54,-2],GD:[12.1,-61.7],GE:[42,43.5],GF:[4,-53],GG:[49.5,-2.5],GH:[8,-1.2],GI:[36.1,-5.4],GM:[13.5,-16.5],GN:[11,-10],GP:[16.3,-61.5],GQ:[2,10],GR:[39,22],GT:[15.5,-90.3],GU:[13.4,144.8],GW:[12,-15],GY:[5,-59],HK:[22.3,114.2],HN:[15,-86.5],HR:[45.2,15.5],HT:[19,-72.3],HU:[47,20],ID:[-5,120],IE:[53,-8],IL:[31.5,34.8],IM:[54.2,-4.5],IN:[20,77],IQ:[33,44],IR:[32,53],IS:[65,-18],IT:[42.8,12.8],JE:[49.2,-2.1],JM:[18.1,-77.3],JO:[31,36],JP:[36,138],KE:[1,38],KG:[41,75],KH:[12.5,105],KP:[40,127],KR:[37,128],KW:[29.5,47.8],KY:[19.3,-81.3],KZ:[48,68],LA:[18,105],LB:[33.8,35.8],LC:[13.9,-61],LI:[47.2,9.6],LK:[7,81],LR:[6.5,-9.5],LS:[-29.5,28.5],LT:[56,24],LU:[49.8,6.2],LV:[57,25],LY:[25,17],MA:[32,-5],MC:[43.7,7.4],MD:[47,29],ME:[42.5,19.3],MG:[-20,47],MK:[41.5,22],ML:[17,-4],MM:[22,98],MN:[46,105],MO:[22.2,113.5],MQ:[14.6,-61],MR:[20,-12],MT:[35.9,14.4],MU:[-20.3,57.6],MV:[3.2,73],MW:[-13.5,34],MX:[23,-102],MY:[2.5,112.5],MZ:[-18.3,35],NA:[-22,17],NC:[-22.3,166.5],NE:[16,8],NG:[10,8],NI:[13,-85],NL:[52.5,5.8],NO:[62,10],NP:[28,84],NZ:[-42,174],OM:[21,57],PA:[9,-80],PE:[-10,-76],PF:[-17.7,-149.4],PG:[-6,147],PH:[13,122],PK:[30,70],PL:[52,20],PR:[18.2,-66.5],PS:[31.9,35.2],PT:[39.5,-8],PY:[-23,-58],QA:[25.5,51.3],RE:[-21.1,55.5],RO:[46,25],RS:[44,21],RU:[60,100],RW:[-2,30],SA:[25,45],SC:[-4.7,55.5],SD:[16,30],SE:[62,15],SG:[1.4,103.8],SI:[46.1,14.8],SK:[48.7,19.5],SL:[8.5,-11.8],SN:[14,-14],SO:[6,46],SR:[4,-56],SS:[7,30],SV:[13.8,-88.9],SY:[35,38],SZ:[-26.5,31.5],TD:[15,19],TG:[8,1.2],TH:[15,100],TJ:[39,71],TL:[-8.5,126],TM:[40,60],TN:[34,9],TR:[39,35],TT:[10.5,-61.3],TW:[23.5,121],TZ:[-6,35],UA:[49,32],UG:[1,32],US:[38,-97],UY:[-33,-56],UZ:[41,64],VC:[13.3,-61.2],VE:[8,-66],VG:[18.4,-64.6],VI:[18.3,-64.9],VN:[16,108],XK:[42.6,21],YE:[15,48],ZA:[-29,24],ZM:[-15,30],ZW:[-20,30],
    }

    const summaries = data.summary || []
    summaries.forEach(s => {
      const centroid = countryCentroids[s.code]
      if (!centroid) return

      const color = levelColors[s.level] || "#ffc107"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const intensity = Math.min(s.score / 100, 1)
      const pixelSize = 8 + intensity * 16

      // Pulsing ring for outage area
      const ring = dataSource.entities.add({
        id: `outage-ring-${s.code}`,
        position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 0),
        ellipse: {
          semiMinorAxis: 50000 + intensity * 300000,
          semiMajorAxis: 50000 + intensity * 300000,
          material: cesiumColor.withAlpha(0.06 + intensity * 0.08),
          outline: true,
          outlineColor: cesiumColor.withAlpha(0.2),
          outlineWidth: 1,
          height: 0,
        },
      })
      this._outageEntities.push(ring)

      // Center marker
      const entity = dataSource.entities.add({
        id: `outage-${s.code}`,
        position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 0),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(0.85),
          outlineColor: cesiumColor.withAlpha(0.4),
          outlineWidth: 3,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.5),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
        label: {
          text: `${s.code} ▼${s.score}`,
          font: "bold 12px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -18),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1.0, 1e7, 0),
        },
      })
      this._outageEntities.push(entity)
    })
  }

  _clearOutageEntities() {
    const ds = this.getOutagesDataSource()
    this._outageEntities.forEach(e => ds.entities.remove(e))
    this._outageEntities = []
  }

  showOutageDetail(code) {
    const s = this._outageData.find(o => o.code === code)
    if (!s) return

    const levelColors = { critical: "#e040fb", severe: "#f44336", moderate: "#ff9800", minor: "#ffc107" }
    const color = levelColors[s.level] || "#ffc107"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-wifi" style="margin-right:6px;"></i>Internet Outage
      </div>
      <div class="detail-country">${this._escapeHtml(s.name || s.code)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Severity</span>
          <span class="detail-value" style="color:${color};">${s.level.toUpperCase()}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Score</span>
          <span class="detail-value">${s.score}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Country</span>
          <span class="detail-value">${s.code}</span>
        </div>
      </div>
      <a href="https://ioda.inetintel.cc.gatech.edu/country/${s.code}" target="_blank" rel="noopener" class="detail-track-btn">View on IODA →</a>
    `
    this.detailPanelTarget.style.display = ""
  }

  // ── Power Plants ────────────────────────────────────────────

  getPowerPlantsDataSource() { return getDataSource(this.viewer, this._ds, "power-plants") }

  togglePowerPlants() {
    this.powerPlantsVisible = this.hasPowerPlantsToggleTarget && this.powerPlantsToggleTarget.checked
    if (this.powerPlantsVisible) {
      this._ensurePowerPlantData().then(() => { this.renderPowerPlants(); this._updateThreatsPanel() })
      if (!this._ppCameraCb) {
        this._ppCameraCb = () => { if (this.powerPlantsVisible) this.renderPowerPlants() }
        this.viewer.camera.moveEnd.addEventListener(this._ppCameraCb)
      }
    } else {
      this._clearPowerPlantEntities()
      if (this._ppCameraCb) { this.viewer.camera.moveEnd.removeEventListener(this._ppCameraCb); this._ppCameraCb = null }
      if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = "none"
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  async _ensurePowerPlantData() {
    if (this._powerPlantAll) return // already loaded
    this._toast("Loading power plants...")
    try {
      const resp = await fetch("/api/power_plants")
      if (!resp.ok) return
      const raw = await resp.json()
      // API returns arrays: [id, lat, lng, fuel, capacity, name, country_code]
      this._powerPlantAll = raw.map(r => ({
        id: r[0], lat: r[1], lng: r[2], fuel: r[3],
        capacity: r[4], name: r[5], country: r[6],
      }))
      console.log(`[PowerPlants] Loaded ${this._powerPlantAll.length} plants`)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch power plants:", e)
    }
  }

  renderPowerPlants() {
    this._clearPowerPlantEntities()
    if (!this._powerPlantAll) return

    const Cesium = window.Cesium
    const dataSource = this.getPowerPlantsDataSource()
    const bounds = getViewportBounds(this.viewer)

    const fuelColors = {
      Coal: "#616161", Gas: "#ff9800", Oil: "#795548", Nuclear: "#fdd835",
      Hydro: "#42a5f5", Solar: "#ffca28", Wind: "#80cbc4", Biomass: "#8bc34a",
      Geothermal: "#e64a19", Waste: "#9e9e9e", Petcoke: "#424242",
      Cogeneration: "#ab47bc", Storage: "#00bcd4", Other: "#78909c",
    }

    // Filter to viewport, already sorted by capacity desc from API
    let visible = this._powerPlantAll
    if (bounds) {
      visible = visible.filter(p =>
        p.lat >= bounds.south && p.lat <= bounds.north &&
        p.lng >= bounds.west && p.lng <= bounds.east
      )
    }
    if (this.hasActiveFilter()) {
      visible = visible.filter(p => this.pointPassesFilter(p.lat, p.lng))
    }
    // Cap at 1500 entities for performance (largest first)
    visible = visible.slice(0, 1500)

    dataSource.entities.suspendEvents()
    visible.forEach(p => {
      const color = fuelColors[p.fuel] || "#78909c"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const cap = p.capacity || 1
      const pixelSize = Math.min(4 + Math.sqrt(cap) * 0.5, 18)

      const entity = dataSource.entities.add({
        id: `pp-${p.id}`,
        position: Cesium.Cartesian3.fromDegrees(p.lng, p.lat, 0),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(0.85),
          outlineColor: cesiumColor.withAlpha(0.3),
          outlineWidth: 1,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 8e6, 0.3),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
        label: {
          text: p.name,
          font: "12px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, -10),
          scaleByDistance: new Cesium.NearFarScalar(5e3, 1, 2e5, 0),
          translucencyByDistance: new Cesium.NearFarScalar(5e3, 1.0, 2e5, 0),
        },
      })
      this._powerPlantEntities.push(entity)

      // Cross-layer: attack warning ring if this country is under cyber attack
      if (this.trafficVisible && this._attackedCountries?.has(p.country)) {
        const atkRing = dataSource.entities.add({
          id: `pp-atk-${p.id}`,
          position: Cesium.Cartesian3.fromDegrees(p.lng, p.lat, 0),
          ellipse: {
            semiMinorAxis: 20000 + (p.capacity || 1) * 5,
            semiMajorAxis: 20000 + (p.capacity || 1) * 5,
            material: Cesium.Color.RED.withAlpha(0.06),
            outline: true,
            outlineColor: Cesium.Color.RED.withAlpha(0.35),
            outlineWidth: 1,
            height: 0,
          },
        })
        this._powerPlantEntities.push(atkRing)
      }
    })
    dataSource.entities.resumeEvents(); this._requestRender()
    this._powerPlantData = visible // for click lookups
  }

  _clearPowerPlantEntities() {
    const ds = this._ds["power-plants"]
    if (ds) {
      ds.entities.suspendEvents()
      this._powerPlantEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents(); this._requestRender()
    }
    this._powerPlantEntities = []
  }

  _updateThreatsPanel() {
    if (!this.hasThreatsContentTarget) return
    const attacked = this._attackedCountries
    if (!attacked?.size || !this._powerPlantAll?.length) {
      if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = "none"
      return
    }

    // Find all power plants in attacked countries
    const threatened = this._powerPlantAll
      .filter(p => attacked.has(p.country))
      .sort((a, b) => (b.capacity || 0) - (a.capacity || 0))
      .slice(0, 200)

    if (!threatened.length) {
      if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = "none"
      return
    }

    if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = ""
    if (this.hasThreatsCountTarget) {
      this.threatsCountTarget.textContent = `${threatened.length} target${threatened.length !== 1 ? "s" : ""}`
    }

    const pairs = this._trafficData?.attack_pairs || []
    const fuelColors = {
      Coal: "#616161", Gas: "#ff9800", Oil: "#795548", Nuclear: "#fdd835",
      Hydro: "#42a5f5", Solar: "#ffca28", Wind: "#80cbc4", Biomass: "#8bc34a",
      Geothermal: "#e64a19", Other: "#78909c",
    }

    // Group by country
    const byCountry = {}
    threatened.forEach(p => {
      if (!byCountry[p.country]) byCountry[p.country] = []
      byCountry[p.country].push(p)
    })

    const html = Object.entries(byCountry).map(([country, plants]) => {
      const countryAttacks = pairs.filter(p => p.target === country)
      const totalPct = countryAttacks.reduce((s, p) => s + (p.pct || 0), 0).toFixed(1)
      const origins = countryAttacks.map(p => p.origin_name || p.origin).join(", ")

      const plantRows = plants.slice(0, 15).map(p => {
        const color = fuelColors[p.fuel] || "#78909c"
        return `<div class="th-plant" data-action="click->globe#focusThreat" data-lat="${p.lat}" data-lng="${p.lng}" data-pp-id="${p.id}">
          <span class="th-fuel" style="color:${color}"><i class="fa-solid fa-bolt"></i></span>
          <span class="th-name">${this._escapeHtml(p.name)}</span>
          <span class="th-cap">${p.capacity ? p.capacity.toLocaleString() + " MW" : ""}</span>
          <span class="th-type" style="background:${color}20;color:${color}">${p.fuel}</span>
        </div>`
      }).join("")

      const moreCount = plants.length > 15 ? `<div class="th-more">+ ${plants.length - 15} more</div>` : ""

      return `<div class="th-country">
        <div class="th-country-header">
          <span class="th-country-name">${this._escapeHtml(country)}</span>
          <span class="th-attack-pct">${totalPct}% DDoS</span>
        </div>
        <div class="th-origins">from ${this._escapeHtml(origins)}</div>
        <div class="th-plants">${plantRows}${moreCount}</div>
      </div>`
    }).join("")

    this.threatsContentTarget.innerHTML = html
  }

  closeThreats() {
    if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = "none"
  }

  focusThreat(event) {
    const lat = parseFloat(event.currentTarget.dataset.lat)
    const lng = parseFloat(event.currentTarget.dataset.lng)
    if (isNaN(lat) || isNaN(lng)) return
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, 500000),
      duration: 1.0,
    })
    // Show detail if we have the plant data
    const ppId = event.currentTarget.dataset.ppId
    const pp = this._powerPlantData?.find(p => String(p.id) === ppId) ||
               this._powerPlantAll?.find(p => String(p.id) === ppId)
    if (pp) this.showPowerPlantDetail(pp)
  }

  showPowerPlantDetail(pp) {
    const fuelColors = {
      Coal: "#616161", Gas: "#ff9800", Oil: "#795548", Nuclear: "#fdd835",
      Hydro: "#42a5f5", Solar: "#ffca28", Wind: "#80cbc4", Biomass: "#8bc34a",
      Geothermal: "#e64a19", Other: "#78909c",
    }
    const color = fuelColors[pp.fuel] || "#78909c"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-plug" style="margin-right:6px;"></i>${this._escapeHtml(pp.name)}
      </div>
      <div class="detail-country">${this._escapeHtml(pp.country || "Unknown")}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Fuel</span>
          <span class="detail-value" style="color:${color};">${pp.fuel || "Unknown"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Capacity</span>
          <span class="detail-value">${pp.capacity ? pp.capacity.toLocaleString() + " MW" : "—"}</span>
        </div>
      </div>
      ${this.trafficVisible && this._attackedCountries?.has(pp.country) ? `
        <div style="margin-top:10px;padding:6px 8px;background:rgba(244,67,54,0.1);border:1px solid rgba(244,67,54,0.3);border-radius:4px;">
          <div style="font:600 9px var(--gt-mono);color:#f44336;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">⚠ CYBER ATTACK TARGET</div>
          ${(this._trafficData?.attack_pairs || []).filter(p => p.target === pp.country).map(p =>
            `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">${this._escapeHtml(p.origin_name)} → ${p.pct?.toFixed(1)}%</div>`
          ).join("")}
        </div>
      ` : ""}
    `
    this.detailPanelTarget.style.display = ""
  }

  // ── Conflict Events ───────────────────────────────────────────

  getConflictsDataSource() { return getDataSource(this.viewer, this._ds, "conflicts") }

  toggleConflicts() {
    this.conflictsVisible = this.hasConflictsToggleTarget && this.conflictsToggleTarget.checked
    if (this.conflictsVisible) {
      this.fetchConflicts()
    } else {
      this._clearConflictEntities()
      this._conflictData = []
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  async fetchConflicts() {
    if (this._timelineActive) return
    this._toast("Loading conflicts...")
    try {
      const resp = await fetch("/api/conflict_events")
      if (!resp.ok) return
      this._conflictData = await resp.json()
      this._handleBackgroundRefresh(resp, "conflict-events", this._conflictData.length > 0, () => {
        if (this.conflictsVisible && !this._timelineActive) this.fetchConflicts()
      })
      this.renderConflicts()
      this._updateStats()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch conflict events:", e)
    }
  }

  renderConflicts() {
    this._clearConflictEntities()
    const Cesium = window.Cesium
    const dataSource = this.getConflictsDataSource()

    const typeColors = {
      1: "#f44336", // state-based
      2: "#ff9800", // non-state
      3: "#e040fb", // one-sided
    }

    this._conflictData.forEach(c => {
      if (this.hasActiveFilter() && !this.pointPassesFilter(c.lat, c.lng)) return

      const color = typeColors[c.type] || "#f44336"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const deaths = c.deaths || 0
      const pixelSize = Math.min(5 + Math.sqrt(deaths) * 2, 22)

      // Impact ring for higher-casualty events
      if (deaths >= 5) {
        const ring = dataSource.entities.add({
          id: `conf-ring-${c.id}`,
          position: Cesium.Cartesian3.fromDegrees(c.lng, c.lat, 0),
          ellipse: {
            semiMinorAxis: 5000 + deaths * 800,
            semiMajorAxis: 5000 + deaths * 800,
            material: cesiumColor.withAlpha(0.06),
            outline: true,
            outlineColor: cesiumColor.withAlpha(0.2),
            outlineWidth: 1,
            height: 0,
          },
        })
        this._conflictEntities.push(ring)
      }

      const entity = dataSource.entities.add({
        id: `conf-${c.id}`,
        position: Cesium.Cartesian3.fromDegrees(c.lng, c.lat, 0),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(0.85),
          outlineColor: cesiumColor.withAlpha(0.4),
          outlineWidth: 2,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 8e6, 0.4),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
        label: {
          text: `${c.conflict || c.country}`,
          font: "12px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, -12),
          scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 3e6, 0),
          translucencyByDistance: new Cesium.NearFarScalar(1e4, 1.0, 3e6, 0),
        },
      })
      this._conflictEntities.push(entity)
    })
  }

  _clearConflictEntities() {
    const ds = this._ds["conflicts"]
    if (ds) this._conflictEntities.forEach(e => ds.entities.remove(e))
    this._conflictEntities = []
  }

  showConflictDetail(c) {
    const typeColors = { 1: "#f44336", 2: "#ff9800", 3: "#e040fb" }
    const color = typeColors[c.type] || "#f44336"
    const totalDeaths = c.deaths || 0

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-crosshairs" style="margin-right:6px;"></i>${this._escapeHtml(c.conflict || "Conflict Event")}
      </div>
      <div class="detail-country">${this._escapeHtml(c.country || "")} — ${this._escapeHtml(c.type_label)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Side A</span>
          <span class="detail-value" style="font-size:11px;">${this._escapeHtml(c.side_a || "—")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Side B</span>
          <span class="detail-value" style="font-size:11px;">${this._escapeHtml(c.side_b || "—")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Deaths</span>
          <span class="detail-value" style="color:${color};">${totalDeaths}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Civilian</span>
          <span class="detail-value">${c.deaths_civilians || 0}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Date</span>
          <span class="detail-value">${c.date_start || "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Location</span>
          <span class="detail-value" style="font-size:10px;">${this._escapeHtml(c.location || "—")}</span>
        </div>
      </div>
      ${c.headline ? `<div style="margin-top:8px;font:400 10px var(--gt-mono);color:var(--gt-text-dim);line-height:1.4;">${this._escapeHtml(c.headline)}</div>` : ""}
      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${c.lat}" data-lng="${c.lng}">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
      </button>
    `
    this.detailPanelTarget.style.display = ""
  }

  // ── Satellite-to-Ground Visibility ─────────────────────────

  showSatVisibility(event) {
    // Toggle: if already showing, hide
    if (this._satVisEntities?.length) {
      this._clearSatVisEntities()
      event.currentTarget.classList.remove("tracking")
      return
    }

    const lat = parseFloat(event.currentTarget.dataset.lat)
    const lng = parseFloat(event.currentTarget.dataset.lng)
    if (isNaN(lat) || isNaN(lng)) return

    event.currentTarget.classList.add("tracking")
    this._clearSatVisEntities()
    this._satVisEventPos = { lat, lng }

    const sat = window.satellite
    if (!sat || !this.satelliteData.length) {
      // Append message to detail panel
      const msg = document.createElement("div")
      msg.style.cssText = "margin-top:8px;font:400 10px var(--gt-mono);color:#ce93d8;"
      msg.textContent = "Enable satellite categories first to see overhead passes."
      event.currentTarget.parentNode.appendChild(msg)
      return
    }

    const Cesium = window.Cesium
    const now = new Date()
    const gmst = sat.gstime(now)
    const observerGd = {
      latitude: lat * Math.PI / 180,
      longitude: lng * Math.PI / 180,
      height: 0,
    }

    const visible = []

    this.satelliteData.forEach(s => {
      try {
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) return

        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        const satLng = sat.degreesLong(posGd.longitude)
        const satLat = sat.degreesLat(posGd.latitude)
        const satAlt = posGd.height // km

        if (isNaN(satLng) || isNaN(satLat) || isNaN(satAlt)) return

        // Compute look angles (elevation)
        const posEcf = sat.eciToEcf(posVel.position, gmst)
        const lookAngles = sat.ecfToLookAngles(observerGd, posEcf)
        const elevationDeg = lookAngles.elevation * 180 / Math.PI

        if (elevationDeg > 5) {
          visible.push({
            name: s.name,
            norad_id: s.norad_id,
            category: s.category,
            lat: satLat,
            lng: satLng,
            alt: satAlt,
            elevation: elevationDeg,
            azimuth: lookAngles.azimuth * 180 / Math.PI,
          })
        }
      } catch (e) {
        // Skip satellites with bad TLE
      }
    })

    // Sort by elevation (highest first) and limit to top 15
    visible.sort((a, b) => b.elevation - a.elevation)
    const top = visible.slice(0, 15)

    // Render visibility lines
    const dataSource = this.getSatellitesDataSource()

    top.forEach((s, i) => {
      const color = Cesium.Color.fromCssColorString(this.satCategoryColors[s.category] || "#ce93d8").withAlpha(0.5)

      // Line from satellite to ground event
      const line = dataSource.entities.add({
        id: `satvis-line-${i}`,
        polyline: {
          positions: [
            Cesium.Cartesian3.fromDegrees(s.lng, s.lat, s.alt * 1000),
            Cesium.Cartesian3.fromDegrees(lng, lat, 0),
          ],
          width: 1.5,
          material: new Cesium.PolylineDashMaterialProperty({
            color: color,
            dashLength: 16,
          }),
        },
      })
      this._satVisEntities.push(line)

      // Small label at satellite position
      const lbl = dataSource.entities.add({
        id: `satvis-lbl-${i}`,
        position: Cesium.Cartesian3.fromDegrees(s.lng, s.lat, s.alt * 1000),
        label: {
          text: `${s.name} (${s.elevation.toFixed(0)}°)`,
          font: "10px JetBrains Mono, monospace",
          fillColor: color.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(8, 0),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 5e7, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1, 5e7, 0.1),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._satVisEntities.push(lbl)
    })

    // Ground marker at event location
    const groundMarker = dataSource.entities.add({
      id: "satvis-ground",
      position: Cesium.Cartesian3.fromDegrees(lng, lat, 0),
      ellipse: {
        semiMinorAxis: 50000,
        semiMajorAxis: 50000,
        material: Cesium.Color.fromCssColorString("#ce93d8").withAlpha(0.1),
        outline: true,
        outlineColor: Cesium.Color.fromCssColorString("#ce93d8").withAlpha(0.4),
        outlineWidth: 1,
        height: 0,
      },
    })
    this._satVisEntities.push(groundMarker)

    // Append satellite list to the detail panel
    const listHtml = top.length > 0
      ? top.map(s => {
          const catColor = this.satCategoryColors[s.category] || "#ce93d8"
          return `<div style="display:flex;justify-content:space-between;font:400 10px var(--gt-mono);color:var(--gt-text-dim);padding:1px 0;">
            <span style="color:${catColor};">${this._escapeHtml(s.name)}</span>
            <span>${s.elevation.toFixed(0)}° el · ${Math.round(s.alt)} km</span>
          </div>`
        }).join("")
      : `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">No satellites currently overhead. Enable more satellite categories.</div>`

    const container = document.createElement("div")
    container.id = "satvis-results"
    container.innerHTML = `
      <div style="margin-top:10px;padding:6px 8px;background:rgba(171,71,188,0.08);border:1px solid rgba(171,71,188,0.25);border-radius:4px;">
        <div style="font:600 9px var(--gt-mono);color:#ce93d8;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">
          <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>${top.length} SATELLITES OVERHEAD
        </div>
        ${listHtml}
      </div>
    `

    // Remove previous results if any
    document.getElementById("satvis-results")?.remove()
    this.detailContentTarget.appendChild(container)
  }

  _clearSatVisEntities() {
    if (!this._satVisEntities?.length) return
    const ds = this._ds["satellites"]
    if (ds) {
      this._satVisEntities.forEach(e => ds.entities.remove(e))
    }
    this._satVisEntities = []
    this._satVisEventPos = null
    document.getElementById("satvis-results")?.remove()
    document.getElementById("ground-events-results")?.remove()
  }

  showGroundEvents(event) {
    // Toggle: if already showing, hide
    if (this._satVisEntities?.length) {
      this._clearSatVisEntities()
      event.currentTarget.classList.remove("tracking")
      return
    }

    const noradId = parseInt(event.currentTarget.dataset.norad)
    const satData = this.satelliteData.find(s => s.norad_id === noradId)
    if (!satData) return

    event.currentTarget.classList.add("tracking")

    const sat = window.satellite
    if (!sat) return
    const Cesium = window.Cesium
    const now = new Date()
    const gmst = sat.gstime(now)

    // Get satellite position
    const satrec = sat.twoline2satrec(satData.tle_line1, satData.tle_line2)
    const posVel = sat.propagate(satrec, now)
    if (!posVel.position) return
    const posGd = sat.eciToGeodetic(posVel.position, gmst)
    const satLat = sat.degreesLat(posGd.latitude)
    const satLng = sat.degreesLong(posGd.longitude)
    const satAltKm = posGd.height

    // Footprint radius: horizon distance from satellite altitude
    // Simple approximation: sqrt(2 * R * h) where R = 6371km
    const footprintKm = Math.sqrt(2 * 6371 * satAltKm)
    const footprintM = footprintKm * 1000

    // Collect ground events within footprint
    const events = []
    const catIcons = { earthquake: "house-crack", natural: "bolt", conflict: "crosshairs", news: "newspaper" }
    const catColors = { earthquake: "#ff7043", natural: "#66bb6a", conflict: "#f44336", news: "#ff9800" }

    // Earthquakes
    if (this._earthquakeData?.length) {
      this._earthquakeData.forEach(eq => {
        const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat: eq.lat, lng: eq.lng })
        if (dist <= footprintM) {
          events.push({ type: "earthquake", label: `M${eq.mag.toFixed(1)} ${eq.title}`, lat: eq.lat, lng: eq.lng, dist })
        }
      })
    }

    // Natural events
    if (this._naturalEventData?.length) {
      this._naturalEventData.forEach(ev => {
        const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat: ev.lat, lng: ev.lng })
        if (dist <= footprintM) {
          events.push({ type: "natural", label: ev.title, lat: ev.lat, lng: ev.lng, dist })
        }
      })
    }

    // Conflicts
    if (this._conflictData?.length) {
      this._conflictData.forEach(c => {
        if (!c.lat || !c.lng) return
        const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat: c.lat, lng: c.lng })
        if (dist <= footprintM) {
          events.push({ type: "conflict", label: `${c.conflict || "Conflict"} — ${c.country || ""}`, lat: c.lat, lng: c.lng, dist })
        }
      })
    }

    // News
    if (this._newsData?.length) {
      this._newsData.forEach(n => {
        if (!n.lat || !n.lng) return
        const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat: n.lat, lng: n.lng })
        if (dist <= footprintM) {
          events.push({ type: "news", label: n.title || "News", lat: n.lat, lng: n.lng, dist })
        }
      })
    }

    events.sort((a, b) => a.dist - b.dist)
    const top = events.slice(0, 20)

    // Draw lines from satellite to each ground event
    this._clearSatVisEntities()
    const dataSource = this.getSatellitesDataSource()
    const satColor = Cesium.Color.fromCssColorString(this.satCategoryColors[satData.category] || "#ce93d8")

    // Footprint circle on ground
    const fpCircle = dataSource.entities.add({
      id: "satvis-footprint",
      position: Cesium.Cartesian3.fromDegrees(satLng, satLat, 0),
      ellipse: {
        semiMinorAxis: footprintM,
        semiMajorAxis: footprintM,
        material: satColor.withAlpha(0.04),
        outline: true,
        outlineColor: satColor.withAlpha(0.2),
        outlineWidth: 1,
        height: 0,
      },
    })
    this._satVisEntities.push(fpCircle)

    top.forEach((ev, i) => {
      const evColor = Cesium.Color.fromCssColorString(catColors[ev.type] || "#ce93d8").withAlpha(0.5)
      const line = dataSource.entities.add({
        id: `satvis-gnd-${i}`,
        polyline: {
          positions: [
            Cesium.Cartesian3.fromDegrees(satLng, satLat, satAltKm * 1000),
            Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 0),
          ],
          width: 1.5,
          material: new Cesium.PolylineDashMaterialProperty({ color: evColor, dashLength: 16 }),
        },
      })
      this._satVisEntities.push(line)
    })

    // Build results HTML
    const listHtml = top.length > 0
      ? top.map(ev => {
          const color = catColors[ev.type] || "#ce93d8"
          const icon = catIcons[ev.type] || "circle"
          const distKm = Math.round(ev.dist / 1000)
          return `<div style="display:flex;gap:6px;align-items:start;font:400 10px var(--gt-mono);color:var(--gt-text-dim);padding:2px 0;">
            <i class="fa-solid fa-${icon}" style="color:${color};margin-top:2px;font-size:9px;flex-shrink:0;"></i>
            <span style="flex:1;line-height:1.3;">${this._escapeHtml(ev.label)}</span>
            <span style="flex-shrink:0;color:${color};">${distKm} km</span>
          </div>`
        }).join("")
      : `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">No active events in footprint. Enable event layers (EQ, EVT, WAR, NEWS).</div>`

    const container = document.createElement("div")
    container.id = "ground-events-results"
    container.innerHTML = `
      <div style="margin-top:10px;padding:6px 8px;background:rgba(171,71,188,0.08);border:1px solid rgba(171,71,188,0.25);border-radius:4px;">
        <div style="font:600 9px var(--gt-mono);color:#ce93d8;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">
          <i class="fa-solid fa-crosshairs" style="margin-right:4px;"></i>${top.length} EVENTS IN FOOTPRINT
          <span style="font-weight:400;text-transform:none;margin-left:4px;">(${Math.round(footprintKm)} km radius)</span>
        </div>
        ${listHtml}
      </div>
    `
    document.getElementById("ground-events-results")?.remove()
    this.detailContentTarget.appendChild(container)
  }

  // ── NOTAMs / No-Fly Zones ─────────────────────────────────

  getNotamsDataSource() { return getDataSource(this.viewer, this._ds, "notams") }

  toggleNotams() {
    this.notamsVisible = this.hasNotamsToggleTarget && this.notamsToggleTarget.checked
    if (this.notamsVisible) {
      this.fetchNotams()
      if (!this._notamCameraCb) {
        this._notamCameraCb = () => { if (this.notamsVisible) this.fetchNotams() }
        this.viewer.camera.moveEnd.addEventListener(this._notamCameraCb)
      }
    } else {
      this._clearNotamEntities()
      if (this._notamCameraCb) { this.viewer.camera.moveEnd.removeEventListener(this._notamCameraCb); this._notamCameraCb = null }
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  async fetchNotams() {
    this._toast("Loading NOTAMs...")
    try {
      const bounds = getViewportBounds(this.viewer)
      let url = "/api/notams"
      if (bounds) {
        url += `?lamin=${bounds.south.toFixed(2)}&lamax=${bounds.north.toFixed(2)}&lomin=${bounds.west.toFixed(2)}&lomax=${bounds.east.toFixed(2)}`
      }
      const resp = await fetch(url)
      if (!resp.ok) return
      this._notamData = await resp.json()
      this.renderNotams()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch NOTAMs:", e)
    }
  }

  renderNotams() {
    this._clearNotamEntities()
    if (!this._notamData || this._notamData.length === 0) return

    const Cesium = window.Cesium
    const dataSource = this.getNotamsDataSource()
    dataSource.entities.suspendEvents()

    const reasonColors = {
      "VIP Movement": "#ff1744",
      "White House": "#ff1744",
      "US Capitol": "#ff1744",
      "Washington DC SFRA": "#ff5252",
      "Washington DC FRZ": "#ff1744",
      "Camp David": "#ff1744",
      "Wildfire": "#ff6d00",
      "Space Operations": "#7c4dff",
      "Sporting Event": "#00c853",
      "Security": "#ff9100",
      "Restricted Area": "#d50000",
      "Hazard": "#ffab00",
      "TFR": "#ef5350",
      "Nuclear Facility": "#ffea00",
      "Government": "#ff1744",
      "Military": "#d50000",
      "Conflict Zone": "#ff3d00",
      "Environmental": "#00e676",
      "Danger": "#ff6d00",
      "Prohibited": "#d50000",
      "Warning": "#ffab00",
    }

    this._notamData.forEach((n) => {
      const color = reasonColors[n.reason] || "#ef5350"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const radius = n.radius_m || 5556

      const altLow = (n.alt_low_ft || 0) * 0.3048
      const altHigh = Math.min((n.alt_high_ft || 18000) * 0.3048, 60000)

      const ellipse = dataSource.entities.add({
        id: `notam-${n.id}`,
        position: Cesium.Cartesian3.fromDegrees(n.lng, n.lat, 0),
        ellipse: {
          semiMinorAxis: radius,
          semiMajorAxis: radius,
          height: altLow,
          extrudedHeight: altHigh,
          material: cesiumColor.withAlpha(0.08),
          outline: true,
          outlineColor: cesiumColor.withAlpha(0.4),
          outlineWidth: 1,
        },
      })
      this._notamEntities.push(ellipse)

      const label = dataSource.entities.add({
        id: `notam-lbl-${n.id}`,
        position: Cesium.Cartesian3.fromDegrees(n.lng, n.lat, altHigh + 500),
        label: {
          text: `⛔ ${n.reason}`,
          font: "bold 11px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 4,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 5e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(1e4, 1.0, 5e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._notamEntities.push(label)
    })
    dataSource.entities.resumeEvents(); this._requestRender()

    this._checkFlightNotamProximity()
  }

  _clearNotamEntities() {
    const ds = this._ds["notams"]
    if (ds) {
      ds.entities.suspendEvents()
      this._notamEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents(); this._requestRender()
    }
    this._notamEntities = []
    this._clearFlightNotamWarnings()
  }

  _checkFlightNotamProximity() {
    if (!this.notamsVisible || !this._notamData?.length) return
    this._clearFlightNotamWarnings()

    const Cesium = window.Cesium
    const dataSource = this.getNotamsDataSource()
    this._notamFlightWarnings = []

    this.flightData.forEach((f, icao24) => {
      if (!f.latitude || !f.longitude) return

      for (const n of this._notamData) {
        const dist = haversineDistance(
          { lat: f.latitude, lng: f.longitude },
          { lat: n.lat, lng: n.lng }
        )
        const proximityThreshold = (n.radius_m || 5556) * 1.5

        if (dist <= proximityThreshold) {
          const warningEntity = dataSource.entities.add({
            id: `notam-warn-${icao24}`,
            position: Cesium.Cartesian3.fromDegrees(f.longitude, f.latitude, (f.baro_altitude || 0)),
            ellipse: {
              semiMinorAxis: 8000,
              semiMajorAxis: 8000,
              material: Cesium.Color.RED.withAlpha(0.15),
              outline: true,
              outlineColor: Cesium.Color.RED.withAlpha(0.6),
              outlineWidth: 2,
              height: (f.baro_altitude || 0) - 500,
              extrudedHeight: (f.baro_altitude || 0) + 500,
            },
          })
          this._notamFlightWarnings.push(warningEntity)
          break
        }
      }
    })
  }

  _clearFlightNotamWarnings() {
    if (!this._notamFlightWarnings) return
    const ds = this._ds["notams"]
    if (ds) {
      this._notamFlightWarnings.forEach(e => ds.entities.remove(e))
    }
    this._notamFlightWarnings = []
  }

  showNotamDetail(n) {
    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#ef5350;">
        <i class="fa-solid fa-ban" style="margin-right:6px;"></i>${this._escapeHtml(n.reason)}
      </div>
      <div class="detail-country">${this._escapeHtml(n.id)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Radius</span>
          <span class="detail-value">${n.radius_nm} NM (${(n.radius_m / 1000).toFixed(1)} km)</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Altitude</span>
          <span class="detail-value">${n.alt_low_ft?.toLocaleString() || 'SFC'} – ${n.alt_high_ft?.toLocaleString()} ft</span>
        </div>
        ${n.effective_start ? `<div class="detail-field">
          <span class="detail-label">Effective</span>
          <span class="detail-value" style="font-size:9px;">${n.effective_start}</span>
        </div>` : ""}
      </div>
      <div style="margin-top:8px;font:400 10px var(--gt-mono);color:var(--gt-text-dim);line-height:1.4;">${this._escapeHtml(n.text)}</div>
    `
    this.detailPanelTarget.style.display = ""
  }
  // ── Internet Traffic (Cloudflare Radar) ─────────────────────

  getTrafficDataSource() { return getDataSource(this.viewer, this._ds, "traffic") }

  toggleTraffic() {
    this.trafficVisible = this.hasTrafficToggleTarget && this.trafficToggleTarget.checked
    if (this.trafficVisible) {
      this.fetchTraffic()
      if (this.hasTrafficArcControlsTarget) this.trafficArcControlsTarget.style.display = ""
    } else {
      this._clearTrafficEntities()
      this._trafficData = null
      if (this.hasTrafficArcControlsTarget) this.trafficArcControlsTarget.style.display = "none"
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  toggleTrafficArcs() {
    this.trafficArcsVisible = this.hasTrafficArcsToggleTarget && this.trafficArcsToggleTarget.checked
    if (!this.trafficArcsVisible) {
      this.trafficBlobsVisible = false
      if (this.hasTrafficBlobsToggleTarget) this.trafficBlobsToggleTarget.checked = false
      this._clearTrafficEntities()
      if (this._trafficData) this.renderTraffic()
    } else if (this._trafficData) {
      this._clearTrafficEntities()
      this.renderTraffic()
    }
  }

  toggleTrafficBlobs() {
    this.trafficBlobsVisible = this.hasTrafficBlobsToggleTarget && this.trafficBlobsToggleTarget.checked
    if (this.trafficBlobsVisible && !this.trafficArcsVisible) {
      this.trafficBlobsVisible = false
      if (this.hasTrafficBlobsToggleTarget) this.trafficBlobsToggleTarget.checked = false
      return
    }
    if (!this.trafficBlobsVisible) {
      this._stopTrafficBlobAnim()
      this._removeTrafficBlobEntities()
    } else if (this._trafficData) {
      this._clearTrafficEntities()
      this.renderTraffic()
    }
  }

  async fetchTraffic() {
    if (this._timelineActive) return
    this._toast("Loading internet traffic...")
    try {
      console.log("[Traffic] Fetching /api/internet_traffic ...")
      const resp = await fetch("/api/internet_traffic")
      console.log("[Traffic] Response status:", resp.status)
      if (!resp.ok) {
        console.warn("[Traffic] Non-OK response:", resp.status, resp.statusText)
        return
      }
      this._trafficData = await resp.json()
      const hasData = (this._trafficData.traffic?.length || 0) > 0 || (this._trafficData.attack_pairs?.length || 0) > 0
      this._handleBackgroundRefresh(resp, "internet-traffic", hasData, () => {
        if (this.trafficVisible && !this._timelineActive) this.fetchTraffic()
      })
      console.log("[Traffic] Got data:", this._trafficData.traffic?.length, "countries,", this._trafficData.attack_pairs?.length, "attack pairs")
      this.renderTraffic()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch internet traffic:", e)
    }
  }

  renderTraffic() {
    this._clearTrafficEntities()
    if (!this._trafficData) return

    const Cesium = window.Cesium
    const dataSource = this.getTrafficDataSource()
    dataSource.entities.suspendEvents()

    // Reuse outage country centroids (ISO-2 → [lat, lng])
    const CC = {
      AD:[42.5,1.5],AE:[24,54],AF:[33,65],AG:[17.1,-61.8],AL:[41,20],AM:[40,45],AO:[-12.5,18.5],AR:[-34,-64],AT:[47.5,13.5],AU:[-25,135],AW:[12.5,-70],AZ:[40.5,47.5],BA:[44,18],BB:[13.2,-59.5],BD:[24,90],BE:[50.8,4],BF:[13,-1.5],BG:[43,25],BH:[26,50.6],BI:[-3.5,30],BJ:[9.5,2.25],BM:[32.3,-64.8],BN:[4.5,114.7],BO:[-17,-65],BR:[-10,-55],BS:[25,-77.4],BT:[27.5,90.5],BW:[-22,24],BY:[53,28],BZ:[17.2,-88.5],CA:[60,-95],CD:[-2.5,23.5],CF:[7,21],CG:[-1,15],CH:[47,8],CI:[8,-5.5],CL:[-30,-71],CM:[6,12],CN:[35,105],CO:[4,-72],CR:[10,-84],CU:[22,-80],CV:[16,-24],CW:[12.2,-69],CY:[35,33],CZ:[49.75,15.5],DE:[51,9],DJ:[11.5,43],DK:[56,10],DO:[19,-70.7],DZ:[28,3],EC:[-2,-77.5],EE:[59,26],EG:[27,30],ER:[15,39],ES:[40,-4],ET:[8,38],FI:[64,26],FJ:[-18,179],FO:[62,-7],FR:[46,2],GA:[-1,11.8],GB:[54,-2],GD:[12.1,-61.7],GE:[42,43.5],GF:[4,-53],GG:[49.5,-2.5],GH:[8,-1.2],GI:[36.1,-5.4],GM:[13.5,-16.5],GN:[11,-10],GP:[16.3,-61.5],GQ:[2,10],GR:[39,22],GT:[15.5,-90.3],GU:[13.4,144.8],GW:[12,-15],GY:[5,-59],HK:[22.3,114.2],HN:[15,-86.5],HR:[45.2,15.5],HT:[19,-72.3],HU:[47,20],ID:[-5,120],IE:[53,-8],IL:[31.5,34.8],IM:[54.2,-4.5],IN:[20,77],IQ:[33,44],IR:[32,53],IS:[65,-18],IT:[42.8,12.8],JE:[49.2,-2.1],JM:[18.1,-77.3],JO:[31,36],JP:[36,138],KE:[1,38],KG:[41,75],KH:[12.5,105],KP:[40,127],KR:[37,128],KW:[29.5,47.8],KY:[19.3,-81.3],KZ:[48,68],LA:[18,105],LB:[33.8,35.8],LC:[13.9,-61],LI:[47.2,9.6],LK:[7,81],LR:[6.5,-9.5],LS:[-29.5,28.5],LT:[56,24],LU:[49.8,6.2],LV:[57,25],LY:[25,17],MA:[32,-5],MC:[43.7,7.4],MD:[47,29],ME:[42.5,19.3],MG:[-20,47],MK:[41.5,22],ML:[17,-4],MM:[22,98],MN:[46,105],MO:[22.2,113.5],MQ:[14.6,-61],MR:[20,-12],MT:[35.9,14.4],MU:[-20.3,57.6],MV:[3.2,73],MW:[-13.5,34],MX:[23,-102],MY:[2.5,112.5],MZ:[-18.3,35],NA:[-22,17],NC:[-22.3,166.5],NE:[16,8],NG:[10,8],NI:[13,-85],NL:[52.5,5.8],NO:[62,10],NP:[28,84],NZ:[-42,174],OM:[21,57],PA:[9,-80],PE:[-10,-76],PF:[-17.7,-149.4],PG:[-6,147],PH:[13,122],PK:[30,70],PL:[52,20],PR:[18.2,-66.5],PS:[31.9,35.2],PT:[39.5,-8],PY:[-23,-58],QA:[25.5,51.3],RE:[-21.1,55.5],RO:[46,25],RS:[44,21],RU:[60,100],RW:[-2,30],SA:[25,45],SC:[-4.7,55.5],SD:[16,30],SE:[62,15],SG:[1.4,103.8],SI:[46.1,14.8],SK:[48.7,19.5],SL:[8.5,-11.8],SN:[14,-14],SO:[6,46],SR:[4,-56],SS:[7,30],SV:[13.8,-88.9],SY:[35,38],SZ:[-26.5,31.5],TD:[15,19],TG:[8,1.2],TH:[15,100],TJ:[39,71],TL:[-8.5,126],TM:[40,60],TN:[34,9],TR:[39,35],TT:[10.5,-61.3],TW:[23.5,121],TZ:[-6,35],UA:[49,32],UG:[1,32],US:[38,-97],UY:[-33,-56],UZ:[41,64],VC:[13.3,-61.2],VE:[8,-66],VG:[18.4,-64.6],VI:[18.3,-64.9],VN:[16,108],XK:[42.6,21],YE:[15,48],ZA:[-29,24],ZM:[-15,30],ZW:[-20,30],
    }

    const traffic = this._trafficData.traffic || []
    const maxTraffic = traffic.length > 0 ? Math.max(...traffic.map(t => t.traffic || 0)) : 1

    // Traffic volume markers (blue-green gradient)
    traffic.forEach(t => {
      const centroid = CC[t.code]
      if (!centroid || !t.traffic) return

      const intensity = t.traffic / maxTraffic
      const pixelSize = 6 + intensity * 20
      // Blue (low) → green (high)
      const r = Math.round(30 * (1 - intensity))
      const g = Math.round(200 + 55 * intensity)
      const b = Math.round(220 * (1 - intensity) + 80)
      const color = Cesium.Color.fromBytes(r, g, b, 200)

      const entity = dataSource.entities.add({
        id: `traf-${t.code}`,
        position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 0),
        point: {
          pixelSize,
          color,
          outlineColor: color.withAlpha(0.3),
          outlineWidth: 3,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.5),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
        label: {
          text: `${t.code} ${t.traffic.toFixed(1)}%`,
          font: "12px JetBrains Mono, monospace",
          fillColor: color.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, -14),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1.0, 1e7, 0),
        },
      })
      this._trafficEntities.push(entity)

      // Attack indicator ring (red) if country is attack target
      if (t.attack_target > 0.5) {
        const atkIntensity = Math.min(t.attack_target / 20, 1)
        const atkColor = Cesium.Color.fromCssColorString("#f44336")
        const ring = dataSource.entities.add({
          id: `traf-atk-${t.code}`,
          position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 0),
          ellipse: {
            semiMinorAxis: 50000 + atkIntensity * 250000,
            semiMajorAxis: 50000 + atkIntensity * 250000,
            material: atkColor.withAlpha(0.06 + atkIntensity * 0.06),
            outline: true,
            outlineColor: atkColor.withAlpha(0.2 + atkIntensity * 0.2),
            outlineWidth: 1,
            height: 0,
          },
        })
        this._trafficEntities.push(ring)
      }
    })

    // DDoS attack arcs (origin → target) with labels and directional arrows
    const pairs = this._trafficData.attack_pairs || []

    // Build set of attacked country codes for cross-layer correlation
    this._attackedCountries = new Set()
    pairs.forEach(p => { if (p.pct > 0.5) this._attackedCountries.add(p.target) })

    // Re-render infra layers if visible to show attack highlighting
    if (this.powerPlantsVisible) this.renderPowerPlants()
    if (this.cablesVisible) this._refreshCableAttackHighlights()
    this._updateThreatsPanel()

    if (!this.trafficArcsVisible) {
      dataSource.entities.resumeEvents(); this._requestRender()
      return
    }

    pairs.forEach((p, idx) => {
      const originC = CC[p.origin]
      const targetC = CC[p.target]
      if (!originC || !targetC) return

      const pct = p.pct || 1
      const arcWidth = Math.max(2, pct * 0.4)
      const arcAlpha = Math.min(0.3 + pct * 0.02, 0.8)

      // Build a raised geodesic arc with multiple segments for smooth curve
      const oLat = originC[0] * Math.PI / 180, oLng = originC[1] * Math.PI / 180
      const tLat = targetC[0] * Math.PI / 180, tLng = targetC[1] * Math.PI / 180
      const SEGS = 40
      const arcPositions = []
      for (let i = 0; i <= SEGS; i++) {
        const f = i / SEGS
        // Spherical interpolation (SLERP on the sphere surface)
        const d = Math.acos(Math.sin(oLat)*Math.sin(tLat) + Math.cos(oLat)*Math.cos(tLat)*Math.cos(tLng-oLng))
        if (d < 0.001) break // same point
        const A = Math.sin((1-f)*d)/Math.sin(d)
        const B = Math.sin(f*d)/Math.sin(d)
        const x = A*Math.cos(oLat)*Math.cos(oLng) + B*Math.cos(tLat)*Math.cos(tLng)
        const y = A*Math.cos(oLat)*Math.sin(oLng) + B*Math.cos(tLat)*Math.sin(tLng)
        const z = A*Math.sin(oLat) + B*Math.sin(tLat)
        const lat = Math.atan2(z, Math.sqrt(x*x+y*y)) * 180/Math.PI
        const lng = Math.atan2(y, x) * 180/Math.PI
        // Raise the arc in the middle (parabolic lift)
        const lift = Math.sin(f * Math.PI) * (200000 + d * 1500000)
        arcPositions.push(Cesium.Cartesian3.fromDegrees(lng, lat, lift))
      }
      if (arcPositions.length < 2) return

      // Arc line — dimmer base trail
      const arcColor = Cesium.Color.fromCssColorString("#f44336").withAlpha(arcAlpha * 0.5)
      const arc = dataSource.entities.add({
        id: `traf-arc-${idx}`,
        polyline: {
          positions: arcPositions,
          width: arcWidth,
          material: new Cesium.PolylineGlowMaterialProperty({
            glowPower: 0.15,
            color: arcColor,
          }),
        },
      })
      this._trafficEntities.push(arc)

      // Animated attack blobs — 1 to 4 based on severity, staggered along path
      if (this.trafficBlobsVisible) {
        const blobCount = Math.min(4, Math.max(1, Math.ceil(pct / 5)))
        const speed = 0.3 + Math.min(pct * 0.01, 0.4) // 0.3–0.7 full-path per second
        const blobSize = Math.max(7, Math.min(16, 5 + pct * 0.3))
        const blobColor = Cesium.Color.fromCssColorString("#ff1744")
        const glowColor = Cesium.Color.fromCssColorString("#ff5252")

        for (let b = 0; b < blobCount; b++) {
          const blob = dataSource.entities.add({
            id: `traf-blob-${idx}-${b}`,
            position: arcPositions[0],
            point: {
              pixelSize: blobSize,
              color: blobColor.withAlpha(0.9),
              outlineColor: glowColor.withAlpha(0.4),
              outlineWidth: 3,
              disableDepthTestDistance: Number.POSITIVE_INFINITY,
              scaleByDistance: new Cesium.NearFarScalar(5e5, 1.2, 1e7, 0.4),
            },
          })
          this._trafficEntities.push(blob)
          // Store animation metadata on the entity for the RAF loop
          blob._blobArc = arcPositions
          blob._blobPhase = b / blobCount
          blob._blobSpeed = speed
        }
      }

      // Label at midpoint of arc
      const midPos = arcPositions[Math.floor(SEGS / 2)]
      const label = dataSource.entities.add({
        id: `traf-lbl-${idx}`,
        position: midPos,
        label: {
          text: `${p.origin} → ${p.target}  ${pct.toFixed(1)}%`,
          font: "11px JetBrains Mono, monospace",
          fillColor: Cesium.Color.fromCssColorString("#ff8a80"),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 4,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, -6),
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1, 1.2e7, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1.5e7, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._trafficEntities.push(label)
    })
    dataSource.entities.resumeEvents(); this._requestRender()

    // Blob animation is handled by the consolidated animate() loop
  }

  // Blob animation is now handled by the consolidated animate() loop

  _clearTrafficEntities() {
    this._stopTrafficBlobAnim()
    const ds = this._ds["traffic"]
    if (ds) {
      ds.entities.suspendEvents()
      this._trafficEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents(); this._requestRender()
    }
    this._trafficEntities = []
    this._attackedCountries = null
    this._clearCableAttackHighlights()
    if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = "none"
  }

  _stopTrafficBlobAnim() {
    if (this._trafficBlobRaf) {
      cancelAnimationFrame(this._trafficBlobRaf)
      this._trafficBlobRaf = null
    }
  }

  _removeTrafficBlobEntities() {
    const ds = this._ds["traffic"]
    if (!ds) return
    const kept = []
    ds.entities.suspendEvents()
    for (const e of this._trafficEntities) {
      if (e._blobArc) {
        ds.entities.remove(e)
      } else {
        kept.push(e)
      }
    }
    ds.entities.resumeEvents(); this._requestRender()
    this._trafficEntities = kept
  }

  showTrafficDetail(code) {
    if (!this._trafficData) return
    const t = this._trafficData.traffic?.find(x => x.code === code)
    if (!t) return

    const pairs = this._trafficData.attack_pairs || []
    const inbound = pairs.filter(p => p.target === code)
    const outbound = pairs.filter(p => p.origin === code)

    let attackHtml = ""
    if (inbound.length > 0) {
      attackHtml += `<div style="margin-top:8px;font:500 9px var(--gt-mono);color:#f44336;letter-spacing:1px;text-transform:uppercase;">Attacks targeting</div>`
      attackHtml += inbound.map(p => `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">${this._escapeHtml(p.origin_name)} → ${p.pct?.toFixed(1)}%</div>`).join("")
    }
    if (outbound.length > 0) {
      attackHtml += `<div style="margin-top:8px;font:500 9px var(--gt-mono);color:#ff9800;letter-spacing:1px;text-transform:uppercase;">Attacks originating</div>`
      attackHtml += outbound.map(p => `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">→ ${this._escapeHtml(p.target_name)} ${p.pct?.toFixed(1)}%</div>`).join("")
    }

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#69f0ae;">
        <i class="fa-solid fa-globe" style="margin-right:6px;"></i>Internet Traffic
      </div>
      <div class="detail-country">${this._escapeHtml(t.name || t.code)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Traffic Share</span>
          <span class="detail-value" style="color:#69f0ae;">${t.traffic?.toFixed(2)}%</span>
        </div>
        ${t.attack_target > 0 ? `<div class="detail-field">
          <span class="detail-label">Attack Target</span>
          <span class="detail-value" style="color:#f44336;">${t.attack_target?.toFixed(2)}%</span>
        </div>` : ""}
        ${t.attack_origin > 0 ? `<div class="detail-field">
          <span class="detail-label">Attack Origin</span>
          <span class="detail-value" style="color:#ff9800;">${t.attack_origin?.toFixed(2)}%</span>
        </div>` : ""}
      </div>
      ${attackHtml}
      ${this._trafficData.recorded_at ? `<div style="margin-top:8px;font:400 9px var(--gt-mono);color:var(--gt-text-dim);">Updated: ${new Date(this._trafficData.recorded_at).toLocaleString()}</div>` : ""}
    `
    this.detailPanelTarget.style.display = ""
  }

  // ── Unified Timeline ─────────────────────────────────────────

  async timelineOpen() {
    if (this._timelineActive) { this.timelineClose(); return }

    try {
      const res = await fetch("/api/playback/range")
      const range = await res.json()
      if (!range.oldest) {
        console.warn("No timeline data available yet")
        return
      }

      this._timelineActive = true
      this._timelinePlaying = false
      this._timelineSpeed = 5
      this._timelineFrames = {}
      this._timelineKeys = []
      this._timelineFrameIndex = 0

      const oldest = new Date(range.oldest)
      const newest = new Date(range.newest)
      // Default to last 1 hour for a manageable playback window
      const oneHourAgo = new Date(newest.getTime() - 60 * 60 * 1000)
      this._timelineRangeStart = oneHourAgo > oldest ? oneHourAgo : oldest
      this._timelineRangeEnd = newest
      this._timelineCursor = new Date(this._timelineRangeStart.getTime())

      // Pause all live refresh intervals
      this._timelinePauseLive()

      this.timelineBarTarget.style.display = ""
      this.timelineTimeStartTarget.textContent = this._fmtTimelineDateTime(oldest)
      this.timelineTimeEndTarget.textContent = this._fmtTimelineDateTime(newest)
      this._updateTimelineCursorDisplay()

      // Load position snapshot frames for the full range
      await this._timelineLoadFrames()

      // Load event data for current cursor position
      this._timelineUpdateEvents()
    } catch (e) {
      console.error("Timeline open error:", e)
    }
  }

  async _timelineLoadFrames() {
    if (!this._timelineActive) return
    const from = this._timelineRangeStart.toISOString()
    const to = this._timelineRangeEnd.toISOString()

    // Only fetch entity types that were active before entering playback
    let playbackType = "all"
    if (this.flightsVisible && !this.shipsVisible) playbackType = "flight"
    else if (this.shipsVisible && !this.flightsVisible) playbackType = "ship"
    let url = `/api/playback?from=${from}&to=${to}&type=${playbackType}`
    // Use country/circle filter bounds if active, otherwise viewport
    const bounds = this.hasActiveFilter() ? this.getFilterBounds() : getViewportBounds(this.viewer)
    if (bounds) {
      url += `&lamin=${bounds.lamin}&lamax=${bounds.lamax}&lomin=${bounds.lomin}&lomax=${bounds.lomax}`
    }

    try {
      const res = await fetch(url)
      const data = await res.json()
      this._timelineFrames = data.frames || {}
      this._timelineKeys = Object.keys(this._timelineFrames).sort()
      this._timelineFrameIndex = 0

      if (this._timelineKeys.length > 0) {
        this._renderTimelineFrame(0)
      }
    } catch (e) {
      console.error("Timeline frame load error:", e)
    }
  }

  _timelinePauseLive() {
    // Store which intervals were active so we can restore them
    this._timelinePausedIntervals = {
      flight: !!this.flightInterval,
      ship: !!this.shipInterval,
      gpsJamming: !!this._gpsJammingInterval,
      news: !!this._newsInterval,
      events: !!this._eventsInterval,
      outages: !!this._outageInterval,
    }
    if (this.flightInterval) { clearInterval(this.flightInterval); this.flightInterval = null }
    if (this.shipInterval) { clearInterval(this.shipInterval); this.shipInterval = null }
    if (this._gpsJammingInterval) { clearInterval(this._gpsJammingInterval); this._gpsJammingInterval = null }
    if (this._newsInterval) { clearInterval(this._newsInterval); this._newsInterval = null }
    if (this._eventsInterval) { clearInterval(this._eventsInterval); this._eventsInterval = null }
    if (this._outageInterval) { clearInterval(this._outageInterval); this._outageInterval = null }

    // Hide only live-data sources that conflict with playback entities
    // Keep static overlays (borders, airports, cities, notams, etc.) visible
    const liveDataSources = new Set(["flights", "ships", "trails", "events", "gpsJamming", "news", "outages", "traffic", "conflictEvents"])
    this._timelineHiddenSources = []
    for (const [name, ds] of Object.entries(this._ds)) {
      if (!liveDataSources.has(name)) continue
      if (ds && ds.show) {
        ds.show = false
        this._timelineHiddenSources.push(name)
      }
    }
  }

  _timelineResumeLive() {
    // Restore only data sources whose layer is still toggled on
    if (this._timelineHiddenSources) {
      const activeDs = new Set()
      if (this.flightsVisible) activeDs.add("flights")
      if (this.shipsVisible) activeDs.add("ships")
      if (this.airportsVisible) activeDs.add("airports")
      if (this.earthquakesVisible || this.naturalEventsVisible) activeDs.add("events")
      if (this.gpsJammingVisible) activeDs.add("gpsJamming")
      if (this.newsVisible) activeDs.add("news")
      if (this.outagesVisible) activeDs.add("outages")
      if (this.trailsVisible) activeDs.add("trails")
      for (const name of this._timelineHiddenSources) {
        if (this._ds[name]) this._ds[name].show = activeDs.has(name)
      }
      this._timelineHiddenSources = null
    }
    // Restart live fetch intervals for active layers
    if (this.flightsVisible) {
      this.fetchFlights()
      this.flightInterval = setInterval(() => this.fetchFlights(), 10000)
    }
    if (this.shipsVisible) {
      this.fetchShips()
      this.shipInterval = setInterval(() => this.fetchShips(), 15000)
    }
    if (this.gpsJammingVisible) {
      this.fetchGpsJamming()
      this._gpsJammingInterval = setInterval(() => this.fetchGpsJamming(), 60000)
    }
    if (this.newsVisible) {
      this.fetchNews()
      this._newsInterval = setInterval(() => this.fetchNews(), 900000)
    }
    if (this.earthquakesVisible || this.naturalEventsVisible) {
      if (this.earthquakesVisible) this.fetchEarthquakes()
      if (this.naturalEventsVisible) this.fetchNaturalEvents()
      this._eventsInterval = setInterval(() => {
        if (this.earthquakesVisible) this.fetchEarthquakes()
        if (this.naturalEventsVisible) this.fetchNaturalEvents()
      }, 300000)
    }
    if (this.outagesVisible) {
      this.fetchOutages()
      this._outageInterval = setInterval(() => this.fetchOutages(), 300000)
    }
  }

  timelineToggle() {
    if (!this._timelineActive) return
    this._timelinePlaying = !this._timelinePlaying

    if (this.hasTimelinePlayBtnTarget) this.timelinePlayBtnTarget.classList.toggle("playing", this._timelinePlaying)
    if (this.hasTimelinePlayIconTarget) this.timelinePlayIconTarget.className = this._timelinePlaying ? "fa-solid fa-pause" : "fa-solid fa-play"

    if (this._timelinePlaying) {
      this._timelineLastTick = performance.now()
      this._timelineTick()
    } else {
      if (this._timelineRaf) cancelAnimationFrame(this._timelineRaf)
    }
  }

  _timelineTick() {
    if (!this._timelinePlaying || !this._timelineActive) return

    const now = performance.now()
    const dt = (now - this._timelineLastTick) / 1000
    this._timelineLastTick = now

    // Advance cursor by dt * speed * 10 seconds per real second
    const advanceMs = dt * this._timelineSpeed * 10000
    const newCursorMs = Math.min(
      this._timelineCursor.getTime() + advanceMs,
      this._timelineRangeEnd.getTime()
    )
    this._timelineCursor = new Date(newCursorMs)

    // Update scrubber position
    this._syncScrubberToCursor()
    this._updateTimelineCursorDisplay()

    // Find and render the nearest position frame
    this._renderNearestFrame()

    // Debounced event updates
    this._timelineEventDebounce()

    // Stop at end
    if (newCursorMs >= this._timelineRangeEnd.getTime()) {
      this._timelinePlaying = false
      if (this.hasTimelinePlayBtnTarget) this.timelinePlayBtnTarget.classList.remove("playing")
      if (this.hasTimelinePlayIconTarget) this.timelinePlayIconTarget.className = "fa-solid fa-play"
      return
    }

    this._timelineRaf = requestAnimationFrame(() => this._timelineTick())
  }

  timelineStepBack() {
    if (!this._timelineActive || this._timelineKeys.length === 0) return
    this._timelineFrameIndex = Math.max(0, this._timelineFrameIndex - 1)
    const key = this._timelineKeys[this._timelineFrameIndex]
    if (key) {
      this._timelineCursor = new Date(key)
      this._syncScrubberToCursor()
      this._updateTimelineCursorDisplay()
      this._renderTimelineFrame(this._timelineFrameIndex)
      this._timelineEventDebounce()
    }
  }

  timelineStepForward() {
    if (!this._timelineActive || this._timelineKeys.length === 0) return
    this._timelineFrameIndex = Math.min(this._timelineKeys.length - 1, this._timelineFrameIndex + 1)
    const key = this._timelineKeys[this._timelineFrameIndex]
    if (key) {
      this._timelineCursor = new Date(key)
      this._syncScrubberToCursor()
      this._updateTimelineCursorDisplay()
      this._renderTimelineFrame(this._timelineFrameIndex)
      this._timelineEventDebounce()
    }
  }

  timelineScrub() {
    if (!this._timelineActive || !this.hasTimelineScrubberTarget) return
    const val = parseInt(this.timelineScrubberTarget.value)
    const range = this._timelineRangeEnd.getTime() - this._timelineRangeStart.getTime()
    const cursorMs = this._timelineRangeStart.getTime() + (val / 10000) * range
    this._timelineCursor = new Date(cursorMs)
    this._updateTimelineCursorDisplay()
    this._renderNearestFrame()
    this._timelineEventDebounce()
  }

  timelineSetSpeed() {
    if (this.hasTimelineSpeedTarget) {
      this._timelineSpeed = parseInt(this.timelineSpeedTarget.value)
    }
  }

  timelineGoLive() {
    this._timelineCursor = new Date(this._timelineRangeEnd.getTime())
    this._syncScrubberToCursor()
    this._updateTimelineCursorDisplay()
    this._renderNearestFrame()
    this._timelineUpdateEvents()
  }

  timelineClose() {
    this._timelineActive = false
    this._timelinePlaying = false
    if (this._timelineRaf) cancelAnimationFrame(this._timelineRaf)
    if (this._timelineEventTimer) clearTimeout(this._timelineEventTimer)
    this.timelineBarTarget.style.display = "none"

    // Clear timeline entities (positions + events)
    const ds = this._ds["timeline"]
    if (ds) ds.entities.removeAll()
    const evDs = this._ds["timelineEvents"]
    if (evDs) evDs.entities.removeAll()

    // Clear only live-data entities before resuming — they'll be re-fetched fresh
    const liveDataSources = new Set(["flights", "ships", "trails", "events", "gpsJamming", "news", "outages", "traffic", "conflictEvents"])
    for (const [name, source] of Object.entries(this._ds)) {
      if (!liveDataSources.has(name)) continue
      if (source) source.entities.removeAll()
    }
    // Clear flight/ship tracking maps so renderFlights/renderShips rebuild cleanly
    if (this.flightData) this.flightData.clear()
    if (this.shipData) this.shipData.clear()

    // Resume live data
    this._timelineResumeLive()
  }

  _syncScrubberToCursor() {
    if (!this.hasTimelineScrubberTarget) return
    const range = this._timelineRangeEnd.getTime() - this._timelineRangeStart.getTime()
    if (range <= 0) return
    const pos = ((this._timelineCursor.getTime() - this._timelineRangeStart.getTime()) / range) * 10000
    this.timelineScrubberTarget.value = Math.round(pos)
  }

  _updateTimelineCursorDisplay() {
    if (!this._timelineCursor) return
    const d = this._timelineCursor
    if (this.hasTimelineCursorDateTarget) {
      this.timelineCursorDateTarget.textContent = d.toISOString().slice(0, 10)
    }
    if (this.hasTimelineCursorTimeTarget) {
      this.timelineCursorTimeTarget.textContent = d.toUTCString().slice(17, 25)
    }
  }

  _renderNearestFrame() {
    if (this._timelineKeys.length === 0) return
    // Binary search for nearest frame key
    const cursorIso = this._timelineCursor.toISOString()
    let lo = 0, hi = this._timelineKeys.length - 1
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (this._timelineKeys[mid] < cursorIso) lo = mid + 1
      else hi = mid
    }
    // Check if previous frame is closer
    if (lo > 0) {
      const prev = new Date(this._timelineKeys[lo - 1]).getTime()
      const curr = new Date(this._timelineKeys[lo]).getTime()
      const target = this._timelineCursor.getTime()
      if (Math.abs(target - prev) < Math.abs(target - curr)) lo = lo - 1
    }
    this._timelineFrameIndex = lo
    this._renderTimelineFrame(lo)
  }

  _timelineEventDebounce() {
    if (this._timelineEventTimer) clearTimeout(this._timelineEventTimer)
    this._timelineEventTimer = setTimeout(() => this._timelineUpdateEvents(), 400)
  }

  async _timelineUpdateEvents() {
    if (!this._timelineActive) return
    const cursor = this._timelineCursor
    const windowMs = 3600000
    const from = new Date(cursor.getTime() - windowMs).toISOString()
    const to = new Date(cursor.getTime() + windowMs).toISOString()

    // Build type filter based on visible layers
    const types = []
    if (this.earthquakesVisible) types.push("earthquake")
    if (this.naturalEventsVisible) types.push("natural_event")
    if (this.newsVisible) types.push("news")
    if (this.gpsJammingVisible) types.push("gps_jamming")
    if (this.outagesVisible) types.push("internet_outage")

    if (types.length === 0) return

    let url = `/api/playback/events?from=${from}&to=${to}&types=${types.join(",")}`
    const bounds = this.hasActiveFilter() ? this.getFilterBounds() : getViewportBounds(this.viewer)
    if (bounds) {
      url += `&lamin=${bounds.lamin}&lamax=${bounds.lamax}&lomin=${bounds.lomin}&lomax=${bounds.lomax}`
    }

    try {
      const res = await fetch(url)
      const events = await res.json()
      this._renderUnifiedTimelineEvents(events)
      this._updateStats()
    } catch (e) {
      console.error("Timeline events error:", e)
    }
  }

  _renderUnifiedTimelineEvents(events) {
    const Cesium = window.Cesium
    const dataSource = getDataSource(this.viewer, this._ds, "timelineEvents")

    // Clear previous event markers
    dataSource.entities.removeAll()

    // Group by type for the existing render methods
    const byType = {}
    events.forEach(e => {
      if (!byType[e.type]) byType[e.type] = []
      byType[e.type].push(e)
    })

    // Dispatch to existing renderers with the right data shape
    if (byType.earthquake && this.earthquakesVisible) {
      this._earthquakeData = byType.earthquake.map(e => ({
        id: e.id, title: e.title, mag: e.mag, magType: e.magType,
        lat: e.lat, lng: e.lng, depth: e.depth, url: e.url,
        time: e.time ? new Date(e.time).getTime() : null,
      }))
      this.renderEarthquakes()
    }
    if (byType.natural_event && this.naturalEventsVisible) {
      this._naturalEventData = byType.natural_event.map(e => ({
        id: e.id, title: e.title, categoryId: e.categoryId,
        categoryTitle: e.categoryTitle, lat: e.lat, lng: e.lng,
        date: e.time, magnitudeValue: e.magnitudeValue,
      }))
      this.renderNaturalEvents()
    }
    if (byType.news && this.newsVisible) {
      const newsData = byType.news.map(e => ({
        lat: e.lat, lng: e.lng, name: e.name, url: e.url,
        tone: e.tone, level: e.level, category: e.category,
        themes: e.themes || [], time: e.time,
      }))
      this._newsData = newsData
      this._renderNews(newsData)
    }
    if (byType.gps_jamming && this.gpsJammingVisible) {
      const jammingData = byType.gps_jamming.map(e => ({
        lat: e.lat, lng: e.lng, total: e.total, bad: e.bad,
        pct: e.pct, level: e.level,
      }))
      this._renderGpsJamming(jammingData)
    }
    if (byType.internet_outage && this.outagesVisible) {
      const outageEvents = byType.internet_outage.map(e => ({
        id: e.id, code: e.code, name: e.name,
        score: e.score, level: e.level,
      }))
      this._outageData = outageEvents
      this._renderOutages({ summary: outageEvents, events: outageEvents })
    }
  }

  // Render a playback frame, interpolating positions between current and next frame
  _renderTimelineFrame(index) {
    const Cesium = window.Cesium
    const key = this._timelineKeys[index]
    if (!key) return

    const entities = this._timelineFrames[key]
    if (!entities) return

    // Build lookup for next frame (for interpolation)
    const nextKey = this._timelineKeys[index + 1]
    const nextEntities = nextKey ? this._timelineFrames[nextKey] : null
    const nextMap = new Map()
    if (nextEntities) {
      nextEntities.forEach(e => nextMap.set(`${e.type}-${e.id}`, e))
    }

    // Compute interpolation factor (0-1) between current and next frame
    let t = 0
    if (nextKey && this._timelineCursor) {
      const curMs = new Date(key).getTime()
      const nextMs = new Date(nextKey).getTime()
      const cursorMs = this._timelineCursor.getTime()
      if (nextMs > curMs) t = Math.max(0, Math.min(1, (cursorMs - curMs) / (nextMs - curMs)))
    }

    const dataSource = getDataSource(this.viewer, this._ds, "timeline")
    const existingIds = new Set()
    const hasFilter = this.hasActiveFilter()

    entities.forEach(e => {
      // Interpolate with next frame if available
      const next = nextMap.get(`${e.type}-${e.id}`)
      const lat = next ? e.lat + (next.lat - e.lat) * t : e.lat
      const lng = next ? e.lng + (next.lng - e.lng) * t : e.lng
      const alt = next ? (e.alt || 0) + ((next.alt || 0) - (e.alt || 0)) * t : (e.alt || 0)
      const hdg = next ? this._lerpAngle(e.hdg || 0, next.hdg || 0, t) : (e.hdg || 0)

      // Apply precise country/circle filter
      if (hasFilter && !this.pointPassesFilter(lat, lng)) return

      const isFlight = e.type === "flight"
      const id = `tl-${e.type}-${e.id}`
      existingIds.add(id)

      let entity = dataSource.entities.getById(id)
      const position = Cesium.Cartesian3.fromDegrees(lng, lat, alt + 100)

      if (entity) {
        entity.position = position
        entity.billboard.rotation = -Cesium.Math.toRadians(hdg)
        if (entity.label) entity.label.text = e.callsign || e.id
      } else {
        entity = dataSource.entities.add({
          id,
          position,
          billboard: {
            image: isFlight
              ? (e.gnd ? this.planeIconGround : this.planeIcon)
              : this._timelineShipIcon(),
            scale: isFlight ? 1.0 : 0.8,
            rotation: -Cesium.Math.toRadians(hdg),
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            heightReference: Cesium.HeightReference.NONE,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
          label: {
            text: e.callsign || e.id,
            font: "12px JetBrains Mono, monospace",
            fillColor: Cesium.Color.fromCssColorString(isFlight ? "rgba(200,210,225,0.85)" : "rgba(38,198,218,0.85)"),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: new Cesium.Cartesian2(0, -18),
            scale: 0.8,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          }
        })
      }
    })

    // Remove entities not in this frame
    const toRemove = []
    for (let i = 0; i < dataSource.entities.values.length; i++) {
      const ent = dataSource.entities.values[i]
      if (!existingIds.has(ent.id)) toRemove.push(ent)
    }
    toRemove.forEach(ent => dataSource.entities.remove(ent))

    this._requestRender()
  }

  // Interpolate between two angles (degrees), handling 359°→1° wraparound
  _lerpAngle(a, b, t) {
    let diff = b - a
    if (diff > 180) diff -= 360
    if (diff < -180) diff += 360
    return (a + diff * t + 360) % 360
  }

  _timelineShipIcon() {
    if (this._cachedTimelineShipIcon) return this._cachedTimelineShipIcon
    const canvas = document.createElement("canvas")
    canvas.width = 20
    canvas.height = 20
    const ctx = canvas.getContext("2d")
    ctx.fillStyle = "#26c6da"
    ctx.beginPath()
    ctx.moveTo(10, 2)
    ctx.lineTo(16, 16)
    ctx.lineTo(10, 13)
    ctx.lineTo(4, 16)
    ctx.closePath()
    ctx.fill()
    this._cachedTimelineShipIcon = canvas.toDataURL()
    return this._cachedTimelineShipIcon
  }

  _fmtTimelineDateTime(dateOrStr) {
    const d = typeof dateOrStr === "string" ? new Date(dateOrStr) : dateOrStr
    if (!d || isNaN(d)) return "--"
    const mo = String(d.getUTCMonth() + 1).padStart(2, "0")
    const dy = String(d.getUTCDate()).padStart(2, "0")
    const hh = String(d.getUTCHours()).padStart(2, "0")
    const mm = String(d.getUTCMinutes()).padStart(2, "0")
    return `${mo}-${dy} ${hh}:${mm}`
  }

  disconnect() {
    Object.values(this._backgroundRefreshRetryTimers || {}).forEach(timer => clearTimeout(timer))
    if (this._mediaRecorder) this._stopRecording()
    if (this._timelineRaf) cancelAnimationFrame(this._timelineRaf)
    if (this._timelineEventTimer) clearTimeout(this._timelineEventTimer)
    if (this.flightInterval) clearInterval(this.flightInterval)
    if (this.shipInterval) clearInterval(this.shipInterval)
    if (this._gpsJammingInterval) clearInterval(this._gpsJammingInterval)
    if (this._newsInterval) clearInterval(this._newsInterval)
    if (this.animationFrame) cancelAnimationFrame(this.animationFrame)
    if (this._handler) this._handler.destroy()
    if (this.viewer) this.viewer.destroy()
  }
}
