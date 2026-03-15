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
    this.trackedTrainId = null
    this._trackingHeights = [5000, 50000, 200000, 800000]
    this._trackingHeightLabels = ["Street", "Close", "Medium", "Far"]
    this._trackingHeightIdx = 2 // default Medium
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
    this.fireHotspotsVisible = false
    this._fireHotspotData = []
    this._fireHotspotEntities = []
    this.weatherVisible = false
    this._weatherActiveLayers = {}
    this._weatherImageryLayers = {}
    this._weatherAlerts = []
    this._weatherAlertEntities = []
    this._weatherOpacity = 0.6
    this.financialVisible = false
    this._commodityData = []
    this._financialEntities = []
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
    this.pipelinesVisible = false
    this._pipelineEntities = []
    this._pipelineData = []
    this.railwaysVisible = false
    this._railwayEntities = []
    this._railwayData = []
    this.trainsVisible = false
    this._trainEntities = []
    this._trainData = []
    this._trainPollTimer = null
    this._rightPanelUserClosed = false
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
    this._conflictPulseData = []
    this._conflictPulseEntities = []
    this._conflictPulsePrev = {}
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
    this._alertData = []
    this._alertUnseenCount = 0
    this._ds = {} // shared datasource cache for getDataSource()
    this._backgroundRefreshRetryTimers = {}
    this._backgroundRefreshRetryCounts = {}
    // Stats clock
    this._clockInterval = setInterval(() => this._updateClock(), 1000)
    this._updateClock()
    // JS tooltips — position fixed so they escape overflow:hidden containers
    this._initTooltips()
    // Stats bar buttons live outside Stimulus scope (in navbar), wire manually
    const bellBtn = document.getElementById("stat-bell-btn")
    if (bellBtn) bellBtn.addEventListener("click", () => this.toggleAlertsFeed())
    const panelBtn = document.getElementById("stat-panel-toggle")
    if (panelBtn) panelBtn.addEventListener("click", () => this.toggleRightPanel())
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
      this._updateGlobeOcclusion()
    })

    // Click handler for custom detail panel
    const handler = new Cesium.ScreenSpaceEventHandler(this.viewer.scene.canvas)
    handler.setInputAction((click) => {
      // Draw mode handled by mouse down/move/up
      if (this.drawMode) return

      const picked = this.viewer.scene.pick(click.position)

      // In country select mode, prioritize country selection over entity clicks
      if (this.countrySelectMode && this.bordersLoaded) {
        // Allow border entity clicks directly
        if (Cesium.defined(picked) && picked.id) {
          const entityId = (picked.id.id || picked.id)
          if (typeof entityId === "string" && entityId.startsWith("border-")) {
            const d = this._borderCountryMap?.get(entityId)
            if (d) { this.toggleCountrySelection(d.name); this.showBorderDetail(); return }
          }
        }
        // Fall back to point-in-polygon lookup on globe surface
        const globePos = this.screenToLatLng(click.position)
        if (globePos) {
          const country = this.findCountryAtPoint(globePos.lat, globePos.lng)
          if (country) {
            this.toggleCountrySelection(country)
            this.showBorderDetail()
            return
          }
        }
        return // don't handle other entities while in country select mode
      }

      if (Cesium.defined(picked) && picked.id) {
        const entityId = picked.id.id || picked.id
        if (this._handleEntityClick(entityId, picked)) return
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
    this._startAlertPolling()
    this._startInsightPolling()
    this._startConflictPulse()
    this._startMiniTimeline()

    // Start animation loop
    this.lastAnimTime = performance.now()
    this.animate()
  }

  GlobeController.prototype._requestRender = function() { if (this.viewer) this.viewer.scene.requestRender() }

  // ── Globe occlusion culling ────────────────────────────────
  // Hide entities on the far side of the globe (not visible to camera).
  // Uses dot-product of camera position and entity position against R².
  //
  // Three zones:
  //   dot > OCC_R_SQ        → fully visible
  //   OCC_R_SQ_FADE < dot   → fade zone (alpha ramps down in 4 discrete steps)
  //   dot ≤ OCC_R_SQ_FADE   → hidden
  //
  // R² = 6371000² ≈ 4.059e13.  Buffer = R² × 0.85.
  // The fade zone sits between the true horizon and the buffer edge.
  // Entities in this zone are behind the globe (depth-tested for ground
  // entities) but labels/billboards with disableDepthTestDistance fade
  // smoothly instead of popping in.

  const OCC_R_SQ        = 4.0589641e13  // 6371000² — true horizon
  const OCC_R_SQ_FADE   = 3.4501195e13  // R² × 0.85 — outer edge of buffer
  const OCC_FADE_RANGE  = OCC_R_SQ - OCC_R_SQ_FADE
  // Pre-built white tint colors at discrete alpha steps (avoids per-entity allocation)
  let OCC_FADE_COLORS = null

  function getOccFadeColors() {
    if (OCC_FADE_COLORS) return OCC_FADE_COLORS
    const C = window.Cesium?.Color
    if (!C) return null
    OCC_FADE_COLORS = [
      C.WHITE.withAlpha(0.15),
      C.WHITE.withAlpha(0.35),
      C.WHITE.withAlpha(0.55),
      C.WHITE.withAlpha(0.80),
      C.WHITE,  // step 4 = full opacity
    ]
    return OCC_FADE_COLORS
  }

  GlobeController.prototype._isPointVisibleOnGlobe = function(lat, lng) {
    if (!this.viewer) return true
    const Cesium = window.Cesium
    if (!this._occScratch) this._occScratch = new Cesium.Cartesian3()
    const pointPos = Cesium.Cartesian3.fromDegrees(lng, lat, 0, Cesium.Ellipsoid.WGS84, this._occScratch)
    return Cesium.Cartesian3.dot(this.viewer.camera.positionWC, pointPos) > OCC_R_SQ_FADE
  }

  GlobeController.prototype._updateGlobeOcclusion = function() {
    if (!this.viewer) return
    const cx = this.viewer.camera.positionWC.x
    const cy = this.viewer.camera.positionWC.y
    const cz = this.viewer.camera.positionWC.z
    const clock = this.viewer.clock.currentTime
    const fadeColors = getOccFadeColors()

    for (const ds of Object.values(this._ds)) {
      if (!ds.show) continue
      const entities = ds.entities.values
      const len = entities.length
      if (len === 0) continue
      for (let i = 0; i < len; i++) {
        const e = entities[i]
        let pos = e.position
        if (!pos) continue
        if (typeof pos.getValue === "function") pos = pos.getValue(clock)
        if (!pos) continue

        const dot = cx * pos.x + cy * pos.y + cz * pos.z

        if (dot > OCC_R_SQ) {
          // Fully visible — restore if we faded or hid it
          if (e._globeOccluded) {
            e._globeOccluded = false
            e.show = true
          }
          if (e._fadeStep !== undefined && e._fadeStep < 4) {
            e._fadeStep = 4
            if (fadeColors && e.billboard) e.billboard.color = fadeColors[4]
            if (fadeColors && e.label) e.label.fillColor = fadeColors[4]
          }
        } else if (dot > OCC_R_SQ_FADE) {
          // Fade zone — discrete alpha step based on position
          if (e._globeOccluded) { e._globeOccluded = false; e.show = true }
          if (fadeColors) {
            const t = (dot - OCC_R_SQ_FADE) / OCC_FADE_RANGE // 0..1
            const step = Math.min(Math.floor(t * 4), 3)       // 0..3
            if (e._fadeStep !== step) {
              e._fadeStep = step
              if (e.billboard) e.billboard.color = fadeColors[step]
              if (e.label) e.label.fillColor = fadeColors[step]
            }
          }
        } else if (e.show) {
          // Far side — hide
          e._globeOccluded = true
          e.show = false
        }
      }
    }
  }

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
      traffic: "qlTraffic", cables: "qlCables", powerPlants: "qlPowerPlants",
      notams: "qlNotams", fireHotspots: "qlFireHotspots", weather: "qlWeather",
      financial: "qlFinancial",
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
        const oldLbl = btn.querySelector(".freshness-age")
        if (oldLbl) oldLbl.remove()
        btn.style.opacity = ""
        continue
      }
      if (!dot) {
        dot = document.createElement("span")
        dot.className = "freshness-dot"
        btn.appendChild(dot)
      }
      const lastUpdate = this._layerFreshness[layer]
      let ageLabel = ""
      let ageSec = null
      if (!lastUpdate) {
        dot.dataset.freshness = "stale"
        ageLabel = "?"
      } else {
        ageSec = (now - lastUpdate) / 1000
        if (ageSec < 30) {
          dot.dataset.freshness = "fresh"
          ageLabel = ""
        } else if (ageSec < 120) {
          dot.dataset.freshness = "warm"
          ageLabel = Math.floor(ageSec / 60) + "m"
        } else if (ageSec < 600) {
          dot.dataset.freshness = "stale"
          ageLabel = Math.floor(ageSec / 60) + "m"
        } else {
          dot.dataset.freshness = "stale"
          ageLabel = "10m+"
        }
        btn.style.opacity = (ageSec >= 600) ? "0.6" : ""
      }
      // Age label next to dot
      let ageLbl = dot.nextElementSibling
      if (ageLbl && !ageLbl.classList.contains("freshness-age")) ageLbl = null
      if (ageLabel) {
        if (!ageLbl) {
          ageLbl = document.createElement("span")
          ageLbl.className = "freshness-age"
          dot.parentNode.insertBefore(ageLbl, dot.nextSibling)
        }
        ageLbl.textContent = ageLabel
        ageLbl.dataset.freshness = dot.dataset.freshness
      } else if (ageLbl) {
        ageLbl.remove()
      }
    }
  }

  GlobeController.prototype.getViewportBounds = function() { return getViewportBounds(this.viewer) }

  GlobeController.prototype._followEntity = function(lng, lat) {
    const cam = this.viewer.camera
    const h = this._trackingHeights[this._trackingHeightIdx]
    cam.setView({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, h),
      orientation: {
        heading: cam.heading,
        pitch: cam.pitch,
        roll: cam.roll,
      },
    })
  }

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

  GlobeController.prototype._toast = function(msg, type) {
    const el = document.getElementById("gt-toast")
    if (!el) return
    // Clear previous state
    clearTimeout(this._toastTimer)
    el.classList.remove("visible", "gt-toast--success", "gt-toast--error")
    el.innerHTML = ""
    // Set type class
    if (type === "success") el.classList.add("gt-toast--success")
    if (type === "error") el.classList.add("gt-toast--error")
    // Build content
    const span = document.createElement("span")
    span.textContent = msg
    el.appendChild(span)
    // Add close button for error toasts
    if (type === "error") {
      const closeBtn = document.createElement("button")
      closeBtn.className = "gt-toast-close"
      closeBtn.innerHTML = "&times;"
      closeBtn.setAttribute("aria-label", "Dismiss")
      closeBtn.addEventListener("click", () => this._toastHide())
      el.appendChild(closeBtn)
      el.style.pointerEvents = "auto"
    } else {
      el.style.pointerEvents = "none"
    }
    el.classList.add("visible")
    // Auto-hide for non-error toasts
    if (type !== "error") {
      this._toastTimer = setTimeout(() => el.classList.remove("visible"), 2000)
    }
  }

  GlobeController.prototype._toastHide = function() {
    const el = document.getElementById("gt-toast")
    if (!el) return
    el.classList.remove("visible", "gt-toast--success", "gt-toast--error")
    el.style.pointerEvents = "none"
    clearTimeout(this._toastTimer)
  }

  // ── Loading / Empty states ────────────────────────────────────
  // panelKey: "entities" | "news" | "threats" | "cameras" | "insights"

  GlobeController.prototype._showLoading = function(panelKey) {
    const t = panelKey + "Loading"
    if (this[`has${t[0].toUpperCase()}${t.slice(1)}Target`]) {
      this[`${t}Target`].style.display = ""
    }
    const e = panelKey + "Empty"
    if (this[`has${e[0].toUpperCase()}${e.slice(1)}Target`]) {
      this[`${e}Target`].style.display = "none"
    }
  }

  GlobeController.prototype._hideLoading = function(panelKey, itemCount) {
    const t = panelKey + "Loading"
    if (this[`has${t[0].toUpperCase()}${t.slice(1)}Target`]) {
      this[`${t}Target`].style.display = "none"
    }
    const e = panelKey + "Empty"
    if (this[`has${e[0].toUpperCase()}${e.slice(1)}Target`]) {
      this[`${e}Target`].style.display = (itemCount === 0) ? "" : "none"
    }
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

        // Skip GPU position update for flights on the far side of the globe
        if (!this._isPointVisibleOnGlobe(data.currentLat, data.currentLng)) {
          if (data.entity.show) { data.entity.show = false; data.entity._globeOccluded = true }
          continue
        }
        if (data.entity._globeOccluded) { data.entity.show = true; data.entity._globeOccluded = false }

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
        this._followEntity(tracked.currentLng, tracked.currentLat)
        needsRender = true
      } else {
        this.trackedFlightId = null
      }
    }

    // Animate train positions (lerp between poll updates)
    if (this._animateTrains?.(now)) needsRender = true

    // Update satellite positions (every ~2 seconds to save CPU)
    if (this.satelliteData.length > 0 && Object.values(this.satCategoryVisible).some(v => v)) {
      if (!this._lastSatUpdate || now - this._lastSatUpdate > 2000) {
        this._lastSatUpdate = now
        this.updateSatellitePositions()
        // Refresh weather↔satellite beams after positions update
        if (this.weatherVisible && this._weatherSatBeamEntities?.length > 0) {
          this._renderWeatherSatBeams()
        }
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

    // Periodic globe occlusion update for moving entities (every 500ms)
    if (!this._lastOcclusionUpdate || now - this._lastOcclusionUpdate > 500) {
      this._lastOcclusionUpdate = now
      this._updateGlobeOcclusion()
      needsRender = true
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

  // Unified click dispatch — returns true if an entity was handled
  GlobeController.prototype._handleEntityClick = function(entityId, picked) {
    // Flight (non-prefixed, stored in flightData map)
    const flightData = this.flightData.get(entityId)
    if (flightData) {
      this.toggleFlightSelection(entityId)
      this.showDetail(entityId, flightData)
      return true
    }

    if (typeof entityId !== "string") return false

    // Dispatch table: prefix → handler
    const handlers = [
      { prefix: "tl-flight-", skip: [], handler: (id) => {
        // Timeline playback flight — show detail from snapshot data
        const snap = this._timelineLastKnown?.get(`flight-${id}`)
        if (!snap) return false
        this._showTimelineFlightDetail(id, snap)
        return true
      }},
      { prefix: "tl-ship-", skip: [], handler: (id) => {
        const snap = this._timelineLastKnown?.get(`ship-${id}`)
        if (!snap) return false
        this._showTimelineShipDetail(id, snap)
        return true
      }},
      { prefix: "ship-", skip: [], handler: (id) => {
        const d = this.shipData.get(id); if (!d) return false
        this.toggleShipSelection(id); this.showShipDetail(d); return true
      }},
      { prefix: "border-", skip: [], handler: (id) => {
        if (!this.countrySelectMode) return false
        const d = this._borderCountryMap?.get("border-" + id); if (!d) return false
        this.toggleCountrySelection(d.name); this.showBorderDetail(); return true
      }},
      { prefix: "sat-", skip: [], handler: (id) => {
        const noradId = parseInt(id)
        const d = this.satelliteData.find(s => s.norad_id === noradId); if (!d) return false
        this.toggleSatSelection(noradId); this.showSatelliteDetail(d); return true
      }},
      { prefix: "train-", skip: [], handler: (id) => {
        const d = this._trainData?.find(t => t.id === id); if (!d) return false
        this.showTrainDetail(d); return true
      }},
      { prefix: "airport-", skip: [], handler: (id) => { this.showAirportDetail(id); return true }},
      { prefix: "eq-", skip: [], handler: (id) => {
        const d = this._earthquakeData.find(e => e.id === id); if (!d) return false
        this.showEarthquakeDetail(d); return true
      }},
      { prefix: "fire-", skip: ["fire-ring-"], handler: (id) => {
        const d = this._fireHotspotData?.find(f => f.id === id); if (!d) return false
        this.showFireHotspotDetail(d); return true
      }},
      { prefix: "eonet-", skip: [], handler: (id) => {
        const d = this._naturalEventData.find(e => e.id === id); if (!d) return false
        this.showNaturalEventDetail(d); return true
      }},
      { prefix: "news-arc-", skip: [], handler: (_id) => {
        const idx = parseInt(entityId.replace(/^news-arc-(?:lbl-|arr-)?/, ""))
        if (isNaN(idx)) return false; this.showNewsArcDetail(idx); return true
      }},
      { prefix: "news-", skip: ["news-arc-"], handler: (id) => {
        const d = this._newsData?.[parseInt(id)]; if (!d) return false
        this.showNewsDetail(d); return true
      }},
      { prefix: "outage-", skip: ["outage-ring-"], handler: (id) => {
        this.showOutageDetail(id); return true
      }},
      { prefix: "cable-", skip: [], handler: (_id) => {
        const props = picked.id.properties; if (!props) return false
        const name = props.cableName?.getValue() || "Unknown cable"
        this.detailContentTarget.innerHTML = `
          <div class="detail-callsign" style="color:#00bcd4;">
            <i class="fa-solid fa-network-wired" style="margin-right:6px;"></i>Submarine Cable
          </div>
          <div class="detail-country">${this._escapeHtml(name)}</div>
          <a href="https://www.submarinecablemap.com/submarine-cable/${props.cableId?.getValue() || ''}" target="_blank" rel="noopener" class="detail-track-btn">View on TeleGeography →</a>
        `
        this.detailPanelTarget.style.display = ""; return true
      }},
      { prefix: "pipeline-", skip: ["pipeline-label-"], handler: (_id) => {
        const props = picked.id.properties; if (!props) return false
        const pipeId = props.pipelineId?.getValue()
        if (pipeId) { this.showPipelineDetail(pipeId); return true }
        return false
      }},
      { prefix: "cam-", skip: [], handler: (id) => {
        const wId = picked.id.properties?.webcamId?.getValue?.()
        const d = this._webcamEntityMap.get("cam-" + id) ||
          this._webcamData.find(c => String(c.id) === id || String(c.id) === String(wId))
        if (!d) return false; this.showWebcamDetail(d); return true
      }},
      { prefix: "pp-", skip: [], handler: (id) => {
        const d = this._powerPlantData.find(p => p.id === parseInt(id)); if (!d) return false
        this.showPowerPlantDetail(d); return true
      }},
      { prefix: "cpulse-", skip: ["cpulse-core-", "cpulse-ring-", "cpulse-lbl-"], handler: (id) => {
        const idx = parseInt(id); const d = this._conflictPulseData?.[idx]; if (!d) return false
        this.showConflictPulseDetail(d); return true
      }},
      { prefix: "conf-", skip: ["conf-ring-"], handler: (id) => {
        const d = this._conflictData.find(e => e.id === parseInt(id)); if (!d) return false
        this.showConflictDetail(d); return true
      }},
      { prefix: "traf-", skip: ["traf-atk-", "traf-arc-"], handler: (id) => {
        this.showTrafficDetail(id); return true
      }},
      { prefix: "notam-lbl-", skip: [], handler: (id) => {
        const d = this._notamData?.find(x => String(x.id) === id); if (!d) return false
        this.showNotamDetail(d); return true
      }},
      { prefix: "notam-", skip: ["notam-warn-", "notam-lbl-"], handler: (id) => {
        const d = this._notamData?.find(x => String(x.id) === id); if (!d) return false
        this.showNotamDetail(d); return true
      }},
      { prefix: "wx-alert-", skip: [], handler: (id) => {
        const d = this._weatherAlerts?.[parseInt(id)]; if (!d) return false
        this.showWeatherAlertDetail(d); return true
      }},
      { prefix: "fin-", skip: [], handler: (id) => {
        const idx = parseInt(id); const d = this._commodityData?.[idx]; if (!d) return false
        this.showCommodityDetail(d); return true
      }},
      { prefix: "insight-", skip: ["insight-ring-"], handler: (id) => {
        const idx = parseInt(id); const d = this._insightsData?.[idx]; if (!d) return false
        this.focusInsight({ currentTarget: { dataset: { insightIdx: String(idx) } } }); return true
      }},
    ]

    for (const { prefix, skip, handler } of handlers) {
      if (!entityId.startsWith(prefix)) continue
      if (skip.some(s => entityId.startsWith(s))) continue
      const stripped = entityId.slice(prefix.length)
      if (handler(stripped)) return true
    }

    return false
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
    this._stopInsightPolling()
    if (this._handler) this._handler.destroy()
    if (this.viewer) this.viewer.destroy()
  }

}
