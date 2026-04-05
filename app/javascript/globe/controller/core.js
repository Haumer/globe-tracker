import { getViewportBounds, restoreCamera, saveCamera } from "globe/camera"
import { createPlaneIcon, findCountryAtPoint, haversineDistance, pointInPolygon, screenToLatLng } from "globe/utils"
import { decodeHash, decodeFocusParams, applyDeepLink, encodeState, copyShareLink } from "globe/deeplinks"
import { applyCoreEntityClickMethods } from "globe/controller/core_entity_clicks"
import { initializeCoreState, teardownCore, wireCoreChrome } from "globe/controller/core_state"
import { applyCoreUiHelpers } from "globe/controller/core_ui_helpers"

export function applyCoreMethods(GlobeController) {
  applyCoreUiHelpers(GlobeController)
  applyCoreEntityClickMethods(GlobeController)

  GlobeController.prototype.connect = function() {
    if (this._handler || (!this._destroyed && this.viewer)) {
      teardownCore(this)
    }

    this._destroyed = false
    initializeCoreState(this)
    wireCoreChrome(this)
    this.initMobileUi?.()
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
    if (this._handler) {
      try {
        this._handler.destroy()
      } catch {}
      this._handler = null
    }
    if (this._onAnchoredDetailResize) {
      window.removeEventListener("resize", this._onAnchoredDetailResize)
      this._onAnchoredDetailResize = null
    }
    if (this._onAnchoredDetailPostRender && this.viewer?.scene?.postRender?.removeEventListener) {
      try {
        this.viewer.scene.postRender.removeEventListener(this._onAnchoredDetailPostRender)
      } catch {}
      this._onAnchoredDetailPostRender = null
    }
    if (this.viewer && !this._destroyed && typeof this.viewer.destroy === "function") {
      try {
        this.viewer.destroy()
      } catch {}
      this.viewer = null
    }

    const Cesium = window.Cesium

    Cesium.Ion.defaultAccessToken = this.cesiumTokenValue

    this.terrainEnabled = false
    // Use dark ArcGIS tiles instead of default Bing-via-Ion to avoid Ion quota burn
    const baseLayer = Cesium.ImageryLayer.fromProviderAsync(
      Cesium.ArcGisMapServerImageryProvider.fromUrl(
        "https://services.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer"
      )
    )
    this.viewer = new Cesium.Viewer("cesium-viewer", {
      baseLayerPicker: false,
      baseLayer: baseLayer,
      geocoder: false,
      homeButton: false,
      navigationHelpButton: false,
      sceneModePicker: false,
      timeline: false,
      animation: false,
      fullscreenButton: false,
      vrButton: false,
      infoBox: false,
      selectionIndicator: false,
      creditContainer: document.createElement("div"),
      requestRenderMode: true,
      maximumRenderTimeChange: Infinity,
    })

    this._applyInitialMobileSceneMode?.()

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
      try {
        applyDeepLink(this, deepLinkState)
      } catch (error) {
        console.warn("Deep link apply failed; falling back to saved preferences.", error)
        this._applyRestoredPrefs()
      }
    } else {
      // Apply DB-saved preferences (camera, layers, sections, countries)
      this._applyRestoredPrefs()
    }

    const hadSavedPrefs = this.savedPrefsValue && Object.keys(this.savedPrefsValue).length > 0
    if (!deepLinkState && !hadSavedPrefs) {
      this._applyDefaultPrimaryLayers?.()
    }

    this._syncMobileChrome?.()

    // Track data freshness per layer
    this._layerFreshness = {}

    // Show onboarding for first-time users (no deep link, no saved prefs, no prior session)
    const hadSession = !!sessionStorage.getItem("globe_camera")
    if (!deepLinkState && !hadSavedPrefs && !hadSession) {
      this._maybeShowOnboarding()
    }

    // Save camera position on move (sessionStorage + DB)
    this._onCameraMoveEnd = () => {
      if (this._destroyed || !this.viewer?.camera) return
      this.saveCamera()
      this._savePrefs()
      this._updateGlobeOcclusion()
      if (this.fireHotspotsVisible && this._fireHotspotData.length > 0) this.renderFireHotspots?.()
    }
    this.viewer.camera.moveEnd.addEventListener(this._onCameraMoveEnd)

    // Click handler for custom detail panel
    const handler = new Cesium.ScreenSpaceEventHandler(this.viewer.scene.canvas)
    handler.setInputAction((click) => {
      // Draw mode handled by mouse down/move/up
      if (this.drawMode) return

      const picked = this._pickClickableEntity(click.position)

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

      // Try entity pick first — but only for "important" clickable entities
      // (situation bubbles, flights, ships, satellites, chokepoints)
      if (Cesium.defined(picked) && picked.id) {
        const entityId = picked.id.id || picked.id
        if (typeof entityId === "string") {
          // These entity types should always handle clicks (they have detail panels).
          // Decoration entities (rings, cores, labels) are also included — the dispatch
          // table redirects them to their parent entity's detail panel.
          const priorityPrefixes = ["milflt-", "strike-", "gc-", "cpulse-", "flt-", "ship-", "sat-", "choke-", "eq-", "cam-", "pp-", "port-", "fire-", "outage-", "conf-", "insight-", "traf-"]
          const isPriority = priorityPrefixes.some(p => entityId.startsWith(p))
          if (isPriority) {
            if (this._handleEntityClick(entityId, picked, click.position)) return
          }
        }
      }

      // Hex cell detection — only when hex layer is visible
      if (this._hexCellData?.length && this._hexTheaterVisible) {
        const globePos = this.screenToLatLng(click.position)
        if (globePos) {
          const hit = this._findHexAtPosition(globePos.lat, globePos.lng)
          if (hit) { this._showHexDetail(hit); return }
        }
      }

      // Remaining entity types (news dots, conflict events, borders, etc.)
      if (Cesium.defined(picked) && picked.id) {
        const entityId = picked.id.id || picked.id
        if (this._handleEntityClick(entityId, picked, click.position)) return
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

    this._onAnchoredDetailPostRender = () => {
      this._refreshAnchoredDetailPosition?.()
      this._refreshPinnedAnchoredDetailPositions?.()
    }
    this.viewer.scene.postRender.addEventListener(this._onAnchoredDetailPostRender)

    this._onAnchoredDetailResize = () => {
      this._refreshAnchoredDetailPosition?.(true)
      this._refreshPinnedAnchoredDetailPositions?.(true)
    }
    window.addEventListener("resize", this._onAnchoredDetailResize)

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
    this._initRegions()
    this._startAlertPolling()
    this._startMiniTimeline()

    const focusState = decodeFocusParams(window.location.search)
    if (focusState) {
      this._focusContextNode?.(focusState, {
        eyebrow: "OBJECT VIEW",
        title: focusState.title || focusState.id,
        summary: "Loading durable graph context for this object.",
        icon: "fa-table-cells-large",
        accentColor: "#4fc3f7",
      })
    }

    // Start animation loop
    this.lastAnimTime = performance.now()
    this.animate()
  }

  GlobeController.prototype._requestRender = function() {
    if (this._destroyed || !this.viewer?.scene) return
    this.viewer.scene.requestRender()
  }

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
    if (!this.viewer?.camera) return true
    const Cesium = window.Cesium
    if (!this._occScratch) this._occScratch = new Cesium.Cartesian3()
    const pointPos = Cesium.Cartesian3.fromDegrees(lng, lat, 0, Cesium.Ellipsoid.WGS84, this._occScratch)
    return Cesium.Cartesian3.dot(this.viewer.camera.positionWC, pointPos) > OCC_R_SQ_FADE
  }

  GlobeController.prototype._pickClickableEntity = function(screenPos) {
    if (!this.viewer?.scene || !screenPos) return null

    const scene = this.viewer.scene
    const picks = scene.drillPick(screenPos, 12) || []
    if (picks.length === 0) return scene.pick(screenPos)

    return picks.find(pick => this._isPickOnVisibleHemisphere(pick)) || null
  }

  GlobeController.prototype._isPickOnVisibleHemisphere = function(pick) {
    const Cesium = window.Cesium
    const entity = pick?.id
    if (!entity || entity.show === false || entity._globeOccluded) return false

    let pos = entity.position
    if (!pos) return true
    if (typeof pos.getValue === "function") pos = pos.getValue(this.viewer.clock.currentTime)
    if (!pos) return false

    return Cesium.Cartesian3.dot(this.viewer.camera.positionWC, pos) > OCC_R_SQ
  }

  GlobeController.prototype._updateGlobeOcclusion = function() {
    if (!this.viewer?.camera) return
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
      situations: "qlSituations", insights: "qlInsights",
      traffic: "qlTraffic", cables: "qlCables", ports: "qlPorts", shippingLanes: "qlShippingLanes", powerPlants: "qlPowerPlants",
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

  GlobeController.prototype._flyToCoordinates = function(lng, lat, height = 500000, options = {}) {
    const Cesium = window.Cesium
    if (!this.viewer?.camera || !Cesium) return false
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false

    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, height),
      duration: options.duration ?? 1.0,
      orientation: options.orientation,
      complete: options.complete,
      cancel: options.cancel,
    })

    return true
  }

  GlobeController.prototype._flyToCoordinatesAsync = function(lng, lat, height = 500000, duration = 1.0) {
    return new Promise(resolve => {
      const started = this._flyToCoordinates(lng, lat, height, {
        duration,
        complete: () => resolve(true),
        cancel: () => resolve(false),
      })

      if (!started) resolve(false)
    })
  }

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
    // Region mode takes highest priority — scopes ALL data fetches
    if (this._activeRegion) return this._activeRegion.bounds

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
    if (this._activeRegion) {
      const b = this._activeRegion.bounds
      return lat >= b.lamin && lat <= b.lamax && lng >= b.lomin && lng <= b.lomax
    }

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
    return !!this._activeRegion || !!this._activeCircle || this.selectedCountries.size > 0
  }

  // Filter an array of geo-objects to only those within the active region/filter.
  // Accepts objects with {latitude, longitude} or {lat, lng}.
  GlobeController.prototype.filterToRegion = function(items) {
    if (!this.hasActiveFilter()) return items
    return items.filter(item => {
      const lat = item.latitude ?? item.lat
      const lng = item.longitude ?? item.lng
      return lat != null && lng != null && this.pointPassesFilter(lat, lng)
    })
  }

  GlobeController.prototype.animate = function() {
    if (this._destroyed || !this.viewer?.scene) {
      this.animationFrame = null
      return
    }

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
        layers: ["earthquakes", "naturalEvents", "news", "conflicts", "situations", "borders"],
        camera: { lat: 20, lng: 30, height: 15000000 },
      },
      space: {
        satCategories: ["stations", "gps-ops", "military", "analyst"],
        camera: { lat: 30, lng: 0, height: 20000000 },
      },
      infrastructure: {
        layers: ["cables", "ports", "shippingLanes", "powerPlants", "gpsJamming", "outages", "borders"],
        camera: { lat: 35, lng: 30, height: 12000000 },
      },
    }

    const s = scenarios[scenario]
    if (!s) return

    // Fly to camera position
    if (s.camera) {
      this._flyToCoordinates(s.camera.lng, s.camera.lat, s.camera.height, { duration: 1.5 })
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

  // ── Polyline Highlight ──────────────────────────────────
  // Briefly widens + brightens a polyline entity to show it was clicked

  GlobeController.prototype._highlightPolyline = function(entity) {
    if (!entity?.polyline) return
    const Cesium = window.Cesium
    const poly = entity.polyline
    const origWidth = poly.width?.getValue(Cesium.JulianDate.now()) || 4
    poly.width = origWidth + 4
    this._requestRender()
    clearTimeout(this._polyHighlightTimer)
    this._polyHighlightTimer = setTimeout(() => {
      if (entity.polyline) entity.polyline.width = origWidth
      this._requestRender()
    }, 2000)
  }

  // ── Cities Layer ─────────────────────────────────────────

  GlobeController.prototype.disconnect = function() {
    teardownCore(this)
  }

}
