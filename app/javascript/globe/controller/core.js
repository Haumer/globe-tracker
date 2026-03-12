import { getViewportBounds, restoreCamera, saveCamera } from "../camera"
import { createPlaneIcon, findCountryAtPoint, haversineDistance, pointInPolygon, screenToLatLng } from "../utils"
import { decodeHash, applyDeepLink, encodeState, copyShareLink } from "../deeplinks"

export function applyCoreMethods(GlobeController) {
  GlobeController.prototype.connect = function() {
    this._airportDb = {}
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
    this._webcamEntityMap = new Map()
    this._webcamFetchToken = 0
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
    this._entityListRequested = false
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

  GlobeController.prototype.loadCesium = function() {
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

  GlobeController.prototype.loadScript = function(src) {
    return new Promise((resolve) => {
      const script = document.createElement("script")
      script.src = src
      script.onload = resolve
      document.head.appendChild(script)
    })
  }

  GlobeController.prototype.initViewer = function() {
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

    // Mobile performance tuning
    if (this._isMobile && this._isMobile()) {
      this.viewer.scene.fxaa = false
      this.viewer.scene.globe.maximumScreenSpaceError = 4
    }

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

    // Apply deep link from URL hash (takes priority over saved prefs)
    const deepLinkState = decodeHash(window.location.hash)
    if (deepLinkState) {
      applyDeepLink(this, deepLinkState)
    } else {
      // Apply DB-saved preferences (camera, layers, sections, countries)
      this._applyRestoredPrefs()
    }

    // Track data freshness per layer
    this._layerFreshness = {}

    // Show onboarding for first-time users (no deep link, no saved prefs, no prior session)
    const hadSavedPrefs = this.savedPrefsValue && Object.keys(this.savedPrefsValue).length > 0
    const hadSession = !!sessionStorage.getItem("globe_camera")
    if (!deepLinkState && !hadSavedPrefs && !hadSession) {
      this._maybeShowOnboarding()
    }

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
          const pickedWebcamId = picked.id.properties?.webcamId?.getValue?.()
          const cam = this._webcamEntityMap.get(entityId) ||
            this._webcamData.find(c => String(c.id) === camId || String(c.id) === String(pickedWebcamId))
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
    this.planeIconEmergency = this.createPlaneIcon("#ff9800")

    // Pre-build satellite icons per category color
    this._satIcons = {}
    this._satPrevPositions = new Map() // norad_id -> { lat, lng, alt, time }

    // Layers start disabled — fetching begins when toggled on

    // Load workspace list for signed-in users
    this._loadWorkspaceList()

    // Start animation loop
    this.lastAnimTime = performance.now()
    this.animate()
  }

  GlobeController.prototype._requestRender = function() { if (this.viewer) this.viewer.scene.requestRender() }

  GlobeController.prototype.createPlaneIcon = function(color) { return createPlaneIcon(color) }

  GlobeController.prototype.saveCamera = function() { saveCamera(this.viewer) }

  GlobeController.prototype.shareView = function() { copyShareLink(this) }

  GlobeController.prototype._markFresh = function(layerKey) {
    if (!this._layerFreshness) this._layerFreshness = {}
    this._layerFreshness[layerKey] = Date.now()
    this._updateFreshnessDots()
  }

  GlobeController.prototype._updateFreshnessDots = function() {
    if (!this._layerFreshness) return
    const now = Date.now()
    const dotMap = {
      flights: "qlFlights", ships: "qlShips", earthquakes: "qlEarthquakes",
      naturalEvents: "qlEvents", news: "qlNews", gpsJamming: "qlGpsJamming",
      cameras: "qlCameras", outages: "qlOutages", conflicts: "qlConflicts",
      traffic: "qlTraffic",
    }
    for (const [layer, targetName] of Object.entries(dotMap)) {
      const hasTarget = "has" + targetName.charAt(0).toUpperCase() + targetName.slice(1) + "Target"
      if (!this[hasTarget]) continue
      const btn = this[targetName + "Target"]
      let dot = btn.querySelector(".freshness-dot")
      // Only show dot when layer is active
      const visKey = layer === "naturalEvents" ? "naturalEventsVisible" : layer + "Visible"
      if (!this[visKey]) {
        if (dot) dot.remove()
        continue
      }
      if (!dot) {
        dot = document.createElement("span")
        dot.className = "freshness-dot"
        btn.appendChild(dot)
      }
      const lastUpdate = this._layerFreshness[layer]
      if (!lastUpdate) {
        dot.dataset.freshness = "stale"
      } else {
        const age = now - lastUpdate
        if (age < 30000) dot.dataset.freshness = "fresh"
        else if (age < 120000) dot.dataset.freshness = "warm"
        else dot.dataset.freshness = "stale"
      }
    }
  }

  GlobeController.prototype.getViewportBounds = function() { return getViewportBounds(this.viewer) }

  // Returns filter bounds from circle/countries, or viewport if no filter active

  GlobeController.prototype.getFilterBounds = function() {
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

  GlobeController.prototype.pointPassesFilter = function(lat, lng) {
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

  GlobeController.prototype._pointInSelectedCountries = function(lat, lng) {
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

  GlobeController.prototype._updateSelectedCountriesBbox = function() {
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

  GlobeController.prototype._computeConvexHull = function(points) {
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

  GlobeController.prototype.hasActiveFilter = function() {
    return !!this._activeCircle || this.selectedCountries.size > 0
  }

  // ── Toast ──────────────────────────────────────────────────

  GlobeController.prototype._toast = function(msg) {
    const el = document.getElementById("gt-toast")
    if (!el) return
    el.textContent = msg
    el.classList.add("visible")
    clearTimeout(this._toastTimer)
    this._toastTimer = setTimeout(() => el.classList.remove("visible"), 2000)
  }

  GlobeController.prototype._toastHide = function() {
    const el = document.getElementById("gt-toast")
    if (el) el.classList.remove("visible")
    clearTimeout(this._toastTimer)
  }

  GlobeController.prototype._handleBackgroundRefresh = function(resp, key, hasData, retryFn) {
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

  GlobeController.prototype.animate = function() {
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

    // Update freshness dots every 10s
    if (!this._lastFreshnessCheck || now - this._lastFreshnessCheck > 10000) {
      this._lastFreshnessCheck = now
      this._updateFreshnessDots()
    }

    if (needsRender) this.viewer.scene.requestRender()

    this.animationFrame = requestAnimationFrame(() => this.animate())
  }

  GlobeController.prototype._timeAgo = function(date) {
    const seconds = Math.floor((Date.now() - date.getTime()) / 1000)
    if (seconds < 60) return "just now"
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
    return `${Math.floor(seconds / 86400)}d ago`
  }

  GlobeController.prototype._escapeHtml = function(str) {
    if (!str) return ""
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }

  // Extract a URL from a Windy player field, which can be:
  //   - a string URL directly
  //   - an object with { link, embed } properties
  //   - undefined/null

  GlobeController.prototype.screenToLatLng = function(screenPos) { return screenToLatLng(this.viewer, screenPos) }

  GlobeController.prototype.haversineDistance = function(a, b) { return haversineDistance(a, b) }

  GlobeController.prototype.pointInPolygon = function(lat, lng, ring) { return pointInPolygon(lat, lng, ring) }

  GlobeController.prototype.findCountryAtPoint = function(lat, lng) { return findCountryAtPoint(this._countryFeatures, lat, lng) }

  // ── Onboarding ──────────────────────────────────────────

  GlobeController.prototype._maybeShowOnboarding = function() {
    if (localStorage.getItem("gt_onboarded")) return
    const overlay = document.getElementById("onboarding-overlay")
    if (!overlay) return

    overlay.style.display = ""

    const dismiss = () => {
      overlay.style.display = "none"
      localStorage.setItem("gt_onboarded", "1")
    }

    document.getElementById("onboarding-dismiss")?.addEventListener("click", dismiss)

    overlay.querySelectorAll(".onboarding-card").forEach(card => {
      card.addEventListener("click", () => {
        this._applyScenario(card.dataset.scenario)
        dismiss()
      })
    })
  }

  GlobeController.prototype._applyScenario = function(scenario) {
    const Cesium = window.Cesium
    const scenarios = {
      aviation: {
        layers: ["flights", "airports", "borders"],
        camera: { lat: 48, lng: 10, height: 5000000 },
      },
      events: {
        layers: ["earthquakes", "naturalEvents", "news", "conflicts", "borders"],
        camera: { lat: 20, lng: 30, height: 15000000 },
      },
      space: {
        satCategories: ["stations", "gps-ops", "military", "analyst"],
        camera: { lat: 30, lng: 0, height: 20000000 },
      },
      infrastructure: {
        layers: ["cables", "powerPlants", "gpsJamming", "outages", "borders"],
        camera: { lat: 35, lng: 30, height: 12000000 },
      },
    }

    const s = scenarios[scenario]
    if (!s) return

    // Fly to camera position
    if (s.camera) {
      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(s.camera.lng, s.camera.lat, s.camera.height),
        duration: 1.5,
      })
    }

    // Activate layers
    if (s.layers) {
      applyDeepLink(this, { layers: s.layers })
    }

    // Activate satellite categories
    if (s.satCategories) {
      applyDeepLink(this, { satCategories: s.satCategories })
    }
  }

  // ── Cities Layer ─────────────────────────────────────────

  GlobeController.prototype.disconnect = function() {
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
