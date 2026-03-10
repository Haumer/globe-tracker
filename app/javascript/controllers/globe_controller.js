import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { cesiumToken: String }
  static targets = ["flightsToggle", "trainsToggle", "camerasToggle", "detailPanel", "detailContent", "flightCount", "trailsToggle", "satStationsToggle", "satStarlinkToggle", "satGpsToggle", "satWeatherToggle", "satOrbitsToggle", "satHeatmapToggle", "shipsToggle", "bordersToggle", "citiesToggle", "entityListPanel", "entityListHeader", "entityListContent", "entityFlightCount", "entityShipCount", "entitySatCount"]

  connect() {
    this.flightsVisible = false
    this.flightInterval = null
    this.flightData = new Map()
    this.selectedFlights = new Set()
    this._selectedFlightEntities = new Map()
    this.animationFrame = null
    this.lastAnimTime = null
    this.trailsVisible = false
    this.trailHistory = new Map()
    this.trackedFlightId = null
    this.satelliteData = []
    this._loadedSatCategories = new Set()
    this.satelliteEntities = new Map()
    this.satCategoryVisible = { stations: false, starlink: false, "gps-ops": false, weather: false, resource: false, science: false, military: false, geo: false, iridium: false, oneweb: false, planet: false, spire: false }
    this.satOrbitsVisible = false
    this.satOrbitEntities = new Map()
    this.selectedSatNoradId = null
    this._satFootprintEntities = []
    this.satHeatmapVisible = false
    this._heatmapEntities = []
    this._heatmapGrid = new Map()       // key "row,col" → { lat, lng, hits: [timestamp, ...] }
    this._heatmapHitLifeSec = 60        // each hit layer lasts 60s
    this._heatmapLastUpdate = 0         // throttle: timestamp of last computation
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
    this.countrySelectMode = false
    this.drawMode = false
    this._drawCenter = null
    this._drawing = false
    this._drawCircleEntity = null
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

    this.viewer = new Cesium.Viewer("cesium-viewer", {
      terrain: Cesium.Terrain.fromWorldTerrain(),
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
    })

    this.viewer.scene.globe.enableLighting = true
    this.viewer.scene.skyAtmosphere.show = true
    this.viewer.scene.fog.enabled = true
    this.viewer.scene.globe.showGroundAtmosphere = true

    // Restore camera position or use default
    const saved = sessionStorage.getItem("globe_camera")
    if (saved) {
      try {
        const cam = JSON.parse(saved)
        this.viewer.camera.setView({
          destination: Cesium.Cartesian3.fromDegrees(cam.lng, cam.lat, cam.height),
          orientation: {
            heading: cam.heading,
            pitch: cam.pitch,
            roll: 0,
          },
        })
      } catch {
        this.viewer.camera.flyTo({
          destination: Cesium.Cartesian3.fromDegrees(10, 30, 20_000_000),
          duration: 0,
        })
      }
    } else {
      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(10, 30, 20_000_000),
        duration: 0,
      })
    }

    this.viewer.scene.skyBox.show = true
    this.viewer.scene.backgroundColor = Cesium.Color.BLACK

    // Save camera position on move
    this.viewer.camera.moveEnd.addEventListener(() => this.saveCamera())

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
            this.showSatelliteDetail(satData)
            return
          }
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

    // Layers start disabled — fetching begins when toggled on

    // Start animation loop
    this.lastAnimTime = performance.now()
    this.animate()
  }

  createPlaneIcon(color) {
    const size = 32
    const canvas = document.createElement("canvas")
    canvas.width = size
    canvas.height = size
    const ctx = canvas.getContext("2d")

    ctx.translate(size / 2, size / 2)

    // Draw plane shape pointing up
    ctx.fillStyle = color
    ctx.beginPath()
    // Fuselage
    ctx.moveTo(0, -14)
    ctx.lineTo(3, -6)
    ctx.lineTo(3, 4)
    ctx.lineTo(0, 14)
    ctx.lineTo(-3, 4)
    ctx.lineTo(-3, -6)
    ctx.closePath()
    ctx.fill()
    // Wings
    ctx.beginPath()
    ctx.moveTo(0, -2)
    ctx.lineTo(12, 4)
    ctx.lineTo(12, 6)
    ctx.lineTo(3, 2)
    ctx.lineTo(-3, 2)
    ctx.lineTo(-12, 6)
    ctx.lineTo(-12, 4)
    ctx.closePath()
    ctx.fill()
    // Tail
    ctx.beginPath()
    ctx.moveTo(0, 10)
    ctx.lineTo(5, 13)
    ctx.lineTo(5, 14)
    ctx.lineTo(0, 12)
    ctx.lineTo(-5, 14)
    ctx.lineTo(-5, 13)
    ctx.closePath()
    ctx.fill()

    return canvas.toDataURL()
  }

  saveCamera() {
    const Cesium = window.Cesium
    const carto = this.viewer.camera.positionCartographic
    sessionStorage.setItem("globe_camera", JSON.stringify({
      lng: Cesium.Math.toDegrees(carto.longitude),
      lat: Cesium.Math.toDegrees(carto.latitude),
      height: carto.height,
      heading: this.viewer.camera.heading,
      pitch: this.viewer.camera.pitch,
    }))
  }

  getViewportBounds() {
    const Cesium = window.Cesium
    const scene = this.viewer.scene
    const canvas = scene.canvas

    const corners = [
      new Cesium.Cartesian2(0, 0),
      new Cesium.Cartesian2(canvas.width, 0),
      new Cesium.Cartesian2(0, canvas.height),
      new Cesium.Cartesian2(canvas.width, canvas.height),
      new Cesium.Cartesian2(canvas.width / 2, 0),
      new Cesium.Cartesian2(canvas.width / 2, canvas.height),
      new Cesium.Cartesian2(0, canvas.height / 2),
      new Cesium.Cartesian2(canvas.width, canvas.height / 2),
    ]

    let lats = [], lngs = []

    corners.forEach(corner => {
      const ray = scene.camera.getPickRay(corner)
      const position = scene.globe.pick(ray, scene)
      if (position) {
        const carto = Cesium.Cartographic.fromCartesian(position)
        lats.push(Cesium.Math.toDegrees(carto.latitude))
        lngs.push(Cesium.Math.toDegrees(carto.longitude))
      }
    })

    if (lats.length === 0) return null

    return {
      lamin: Math.min(...lats),
      lamax: Math.max(...lats),
      lomin: Math.min(...lngs),
      lomax: Math.max(...lngs),
    }
  }

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

  // Test point against only the selected countries' polygons
  _pointInSelectedCountries(lat, lng) {
    for (const feature of this._countryFeatures) {
      const name = feature.properties?.NAME || feature.properties?.name
      if (!name || !this.selectedCountries.has(name)) continue

      const geom = feature.geometry
      const polygons = geom.type === "Polygon" ? [geom.coordinates] : geom.type === "MultiPolygon" ? geom.coordinates : []
      for (const poly of polygons) {
        if (this.pointInPolygon(lat, lng, poly[0])) return true
      }
    }
    return false
  }

  // Recompute bounding box whenever selection changes
  _updateSelectedCountriesBbox() {
    if (this.selectedCountries.size === 0) {
      this._selectedCountriesBbox = null
      return
    }
    let minLat = 90, maxLat = -90, minLng = 180, maxLng = -180
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
        }
      }
    }
    this._selectedCountriesBbox = { minLat, maxLat, minLng, maxLng }
  }

  hasActiveFilter() {
    return !!this._activeCircle || this.selectedCountries.size > 0
  }

  async fetchFlights() {
    if (!this.flightsVisible) return

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

      // Record trail history
      let trail = this.trailHistory.get(id)
      if (!trail) {
        trail = []
        this.trailHistory.set(id, trail)
      }
      const lastPoint = trail[trail.length - 1]
      if (!lastPoint || lastPoint.lat !== flight.latitude || lastPoint.lng !== flight.longitude) {
        trail.push({ lat: flight.latitude, lng: flight.longitude, alt })
        if (trail.length > 200) trail.shift() // cap trail length
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

        // Only correct position if the server has genuinely new data
        const newTimePos = flight.time_position || 0
        if (newTimePos !== existing.lastTimePosition) {
          existing.currentLat = existing.currentLat * 0.3 + projLat * 0.7
          existing.currentLng = existing.currentLng * 0.3 + projLng * 0.7
          existing.currentAlt = existing.currentAlt * 0.3 + projAlt * 0.7
          existing.lastTimePosition = newTimePos
        }

        existing.entity.billboard.image = onGround ? this.planeIconGround : this.planeIcon
        existing.entity.billboard.rotation = -Cesium.Math.toRadians(heading)
        existing.entity.label.text = callsign
      } else {
        const entity = dataSource.entities.add({
          id: id,
          position: Cesium.Cartesian3.fromDegrees(projLng, projLat, projAlt),
          billboard: {
            image: onGround ? this.planeIconGround : this.planeIcon,
            scale: 0.8,
            rotation: -Cesium.Math.toRadians(heading),
            alignedAxis: Cesium.Cartesian3.UNIT_Z,
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.3),
          },
          label: {
            text: callsign,
            font: "11px sans-serif",
            fillColor: Cesium.Color.WHITE,
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 2,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: new Cesium.Cartesian2(18, 0),
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
        })
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
        }
      }
    }

    // Update flight count
    if (this.hasFlightCountTarget) {
      this.flightCountTarget.textContent = `${this.flightData.size.toLocaleString()} flights`
    }

    // Render trails
    if (this.trailsVisible) this.renderTrails()

    // Update entity list if visible
    if (this.hasActiveFilter() && this.entityListPanelTarget.style.display !== "none") {
      this.updateEntityList()
    }
  }

  renderTrails() {
    const Cesium = window.Cesium
    const trailSource = this.getTrailsDataSource()

    if (!this._trailEntities) this._trailEntities = new Map()

    const activeIds = new Set()

    for (const [id, trail] of this.trailHistory) {
      if (trail.length < 2) continue
      activeIds.add(id)

      const existing = this._trailEntities.get(id)

      if (!existing) {
        // Use CallbackProperty so Cesium doesn't re-create the primitive on update
        const entity = trailSource.entities.add({
          id: `trail-${id}`,
          polyline: {
            positions: new Cesium.CallbackProperty(() => {
              const t = this.trailHistory.get(id)
              if (!t || t.length < 2) return []
              return t.map(p => Cesium.Cartesian3.fromDegrees(p.lng, p.lat, p.alt))
            }, false),
            width: 1.5,
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

  getTrailsDataSource() {
    const Cesium = window.Cesium
    if (!this._trailsDataSource) {
      this._trailsDataSource = new Cesium.CustomDataSource("trails")
      this.viewer.dataSources.add(this._trailsDataSource)
    }
    return this._trailsDataSource
  }

  toggleTrails() {
    this.trailsVisible = this.hasTrailsToggleTarget && this.trailsToggleTarget.checked
    if (this._trailsDataSource) {
      this._trailsDataSource.show = this.trailsVisible
    }
    if (this.trailsVisible) this.renderTrails()
  }

  animate() {
    const Cesium = window.Cesium
    const now = performance.now()
    const dt = (now - this.lastAnimTime) / 1000
    this.lastAnimTime = now

    if (dt > 0 && dt < 1) {
      for (const [, data] of this.flightData) {
        if (data.onGround || !data.speed) continue

        // Dead reckoning: project forward with speed, heading, and vertical rate
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
      }
    }

    // Update trails during animation (every ~500ms)
    if (this.trailsVisible) {
      if (!this._lastTrailUpdate || now - this._lastTrailUpdate > 500) {
        this._lastTrailUpdate = now
        for (const [id, data] of this.flightData) {
          if (data.onGround || !data.speed) continue
          let trail = this.trailHistory.get(id)
          if (!trail) {
            trail = []
            this.trailHistory.set(id, trail)
          }
          const last = trail[trail.length - 1]
          if (!last || Math.abs(last.lat - data.currentLat) > 0.0001 || Math.abs(last.lng - data.currentLng) > 0.0001) {
            trail.push({ lat: data.currentLat, lng: data.currentLng, alt: data.currentAlt })
            if (trail.length > 200) trail.shift()
          }
        }
        this.renderTrails()
      }
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
      } else {
        this.trackedFlightId = null
      }
    }

    // Update satellite positions (every ~2 seconds to save CPU)
    if (this.satelliteData.length > 0 && Object.values(this.satCategoryVisible).some(v => v)) {
      if (!this._lastSatUpdate || now - this._lastSatUpdate > 2000) {
        this._lastSatUpdate = now
        this.updateSatellitePositions()
      }
    }

    this.animationFrame = requestAnimationFrame(() => this.animate())
  }

  showDetail(id, data) {
    const labelText = data.entity.label?.text
    const callsign = (typeof labelText === "string" ? labelText : labelText?._value) || id
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

    // Fetch route info async
    if (callsign) {
      this.fetchRoute(callsign)
    } else {
      document.getElementById("detail-route").textContent = ""
    }
  }

  async fetchRoute(callsign) {
    const routeEl = document.getElementById("detail-route")
    if (!routeEl) return

    try {
      const response = await fetch(`/api/flights/${encodeURIComponent(callsign)}`)
      if (!response.ok) {
        routeEl.textContent = ""
        return
      }

      const data = await response.json()
      if (data.error || !data.route || data.route.length < 2) {
        routeEl.textContent = ""
        return
      }

      routeEl.innerHTML = `
        <span class="route-airport">${data.route[0]}</span>
        <span class="route-arrow">→</span>
        <span class="route-airport">${data.route[data.route.length - 1]}</span>
      `
    } catch {
      routeEl.textContent = ""
    }
  }

  showSatelliteDetail(satData) {
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

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign">${satData.name}</div>
      <div class="detail-country">${satData.category.toUpperCase()}</div>
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
        <div class="detail-field">
          <span class="detail-label">Category</span>
          <span class="detail-value">${satData.category}</span>
        </div>
      </div>
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
    this.stopTracking()
    this.clearSatFootprint()
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
      if (this.selectedFlights.size > 0) {
        html = `<div class="entity-selection-bar">
          <span>${this.selectedFlights.size} selected</span>
          <button class="entity-clear-btn" data-action="click->globe#clearFlightSelection">Clear</button>
        </div>`
      }
      if (data.flights.length === 0) {
        html += '<div class="entity-empty">No flights in area</div>'
      } else {
        // Sort: selected first, then military, then by altitude
        html += data.flights
          .map(f => ({ ...f, _mil: this._isMilitaryFlight(f), _sel: this.selectedFlights.has(f.id) ? 1 : 0 }))
          .sort((a, b) => (b._sel - a._sel) || (b._mil - a._mil) || (b.altitude || 0) - (a.altitude || 0))
          .map(f => {
          const alt = f.currentAlt || f.altitude || 0
          const vr = f.verticalRate || 0
          const spd = f.speed || 0
          const isMil = f._mil

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

          return `
          <div class="entity-row${isMil ? " entity-military" : ""}${selClass}" data-action="click->globe#flyToFlight" data-id="${f.id || f.hex}">
            <span class="entity-select-dot ${isSelected ? "active" : ""}"></span>
            <span class="entity-icon" style="color: ${statusColor}"><i class="fa-solid ${statusIcon}"></i></span>
            <span class="entity-name">${f.callsign || f.id || "—"}${milBadge}</span>
            <span class="entity-detail">${altLabel}</span>
            <span class="entity-detail">${spd > 0 ? Math.round(spd) + " kts" : ""}</span>
            <span class="entity-detail" style="color: rgba(255,255,255,0.2)">${f.originCountry || ""}</span>
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

  // ── Flight Multi-Select ───────────────────────────────────

  toggleFlightSelection(id) {
    if (this.selectedFlights.has(id)) {
      this.selectedFlights.delete(id)
      this._removeFlightHighlight(id)
    } else {
      this.selectedFlights.add(id)
      this._addFlightHighlight(id)
    }
    // Refresh entity list to show selection state
    if (this.entityListPanelTarget.style.display !== "none") {
      this.renderEntityTab("flights")
    }
  }

  _addFlightHighlight(id) {
    const Cesium = window.Cesium
    const f = this.flightData.get(id)
    if (!f) return

    const dataSource = this.getFlightsDataSource()
    const ring = dataSource.entities.add({
      id: `sel-${id}`,
      position: new Cesium.CallbackProperty(() => {
        const fd = this.flightData.get(id)
        if (!fd) return Cesium.Cartesian3.fromDegrees(0, 0, 0)
        return Cesium.Cartesian3.fromDegrees(fd.currentLng, fd.currentLat, fd.currentAlt)
      }, false),
      ellipse: {
        semiMajorAxis: 8000,
        semiMinorAxis: 8000,
        height: new Cesium.CallbackProperty(() => {
          const fd = this.flightData.get(id)
          return fd ? fd.currentAlt : 0
        }, false),
        material: Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.15),
        outline: true,
        outlineColor: Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.8),
        outlineWidth: 2,
      },
    })
    this._selectedFlightEntities.set(id, ring)
  }

  _removeFlightHighlight(id) {
    const entity = this._selectedFlightEntities.get(id)
    if (entity) {
      const dataSource = this.getFlightsDataSource()
      dataSource.entities.remove(entity)
      this._selectedFlightEntities.delete(id)
    }
  }

  clearFlightSelection() {
    for (const id of this.selectedFlights) {
      this._removeFlightHighlight(id)
    }
    this.selectedFlights.clear()
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

  getFlightsDataSource() {
    const Cesium = window.Cesium

    if (!this._flightsDataSource) {
      this._flightsDataSource = new Cesium.CustomDataSource("flights")
      this.viewer.dataSources.add(this._flightsDataSource)
    }
    return this._flightsDataSource
  }

  toggleFlights() {
    this.flightsVisible = this.flightsToggleTarget.checked
    if (this._flightsDataSource) {
      this._flightsDataSource.show = this.flightsVisible
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
  }

  async fetchSatCategory(cat) {
    try {
      const response = await fetch(`/api/satellites?category=${cat}`)
      if (!response.ok) return
      const sats = await response.json()

      // Remove old data for this category, add fresh
      this.satelliteData = this.satelliteData.filter(s => s.category !== cat)
      this.satelliteData.push(...sats)
      this._loadedSatCategories.add(cat)

      this.updateSatellitePositions()
    } catch (e) {
      console.error("Failed to fetch satellites:", e)
    }
  }

  get satCategoryColors() {
    return {
      stations: "#ff5252",
      starlink: "#ab47bc",
      "gps-ops": "#66bb6a",
      weather: "#ffa726",
      resource: "#29b6f6",
      science: "#ec407a",
      military: "#ef5350",
      geo: "#78909c",
      iridium: "#26c6da",
      oneweb: "#7e57c2",
      planet: "#8d6e63",
      spire: "#9ccc65",
    }
  }

  updateSatellitePositions() {
    const Cesium = window.Cesium
    const sat = window.satellite
    if (!sat) return

    const dataSource = this.getSatellitesDataSource()
    const now = new Date()
    const gmst = sat.gstime(now)
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

        // Apply country/circle filter if active
        if (this.hasActiveFilter() && !this.pointPassesFilter(lat, lng)) return

        const id = `sat-${s.norad_id}`
        currentIds.add(id)
        const color = this.satCategoryColors[s.category] || "#ab47bc"

        // Update selected satellite footprint (hex grid + beam)
        if (this.selectedSatNoradId === s.norad_id) {
          this._selectedSatPosition = { lat, lng, alt, altKm: posGd.height, color }
        }

        const existing = this.satelliteEntities.get(id)
        if (existing) {
          existing.position = Cesium.Cartesian3.fromDegrees(lng, lat, alt)
        } else {
          const entity = dataSource.entities.add({
            id,
            position: Cesium.Cartesian3.fromDegrees(lng, lat, alt),
            point: {
              pixelSize: s.category === "stations" ? 12 : 6,
              color: Cesium.Color.fromCssColorString(color),
              outlineColor: Cesium.Color.fromCssColorString(color).withAlpha(0.3),
              outlineWidth: s.category === "stations" ? 3 : 1,
              scaleByDistance: new Cesium.NearFarScalar(1e6, 1.5, 5e7, 0.6),
            },
            label: s.category === "stations" ? {
              text: s.name,
              font: "12px sans-serif",
              fillColor: Cesium.Color.fromCssColorString(color),
              outlineColor: Cesium.Color.BLACK,
              outlineWidth: 2,
              style: Cesium.LabelStyle.FILL_AND_OUTLINE,
              pixelOffset: new Cesium.Cartesian2(12, 0),
              scaleByDistance: new Cesium.NearFarScalar(1e6, 1, 2e7, 0),
            } : undefined,
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
      }
    }

    // Remove footprint if selected satellite is gone
    if (this.selectedSatNoradId && !currentIds.has(`sat-${this.selectedSatNoradId}`)) {
      this.clearSatFootprint()
    }

    // Render hex footprint for selected satellite
    if (this._selectedSatPosition) {
      this.renderSatHexFootprint(this._selectedSatPosition)
    }

    // Update orbit trails if visible
    if (this.satOrbitsVisible) this.renderSatOrbits()

    // Update coverage heatmap if visible (throttled internally)
    if (this.satHeatmapVisible && (Date.now() - this._heatmapLastUpdate) > 10000) {
      this.renderSatHeatmap()
    }
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
      (s.category === "stations" || s.category === "gps-ops" || s.category === "weather")
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

  getSatellitesDataSource() {
    const Cesium = window.Cesium
    if (!this._satellitesDataSource) {
      this._satellitesDataSource = new Cesium.CustomDataSource("satellites")
      this.viewer.dataSources.add(this._satellitesDataSource)
    }
    return this._satellitesDataSource
  }

  getSatOrbitsDataSource() {
    const Cesium = window.Cesium
    if (!this._satOrbitsDataSource) {
      this._satOrbitsDataSource = new Cesium.CustomDataSource("sat-orbits")
      this.viewer.dataSources.add(this._satOrbitsDataSource)
    }
    return this._satOrbitsDataSource
  }

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
  }

  toggleSatOrbits() {
    this.satOrbitsVisible = this.satOrbitsToggleTarget.checked
    if (this._satOrbitsDataSource) {
      this._satOrbitsDataSource.show = this.satOrbitsVisible
    }
    if (this.satOrbitsVisible) {
      // Clear cached orbits so they recompute
      this.satOrbitEntities.clear()
      if (this._satOrbitsDataSource) this._satOrbitsDataSource.entities.removeAll()
      this.renderSatOrbits()
    }
  }

  selectSatFootprint(noradId) {
    this.clearSatFootprint()
    this.selectedSatNoradId = noradId
    this.updateSatellitePositions()
  }

  clearSatFootprint() {
    this.selectedSatNoradId = null
    this._selectedSatPosition = null
    if (this._satFootprintEntities.length > 0 && this._satellitesDataSource) {
      this._satFootprintEntities.forEach(e => this._satellitesDataSource.entities.remove(e))
      this._satFootprintEntities = []
    }
  }

  // ── Satellite Coverage Heatmap ───────────────────────────

  toggleSatHeatmap() {
    this.satHeatmapVisible = this.hasSatHeatmapToggleTarget && this.satHeatmapToggleTarget.checked
    if (!this.satHeatmapVisible) {
      this.clearHeatmap()
      this._heatmapGrid.clear()
      this._heatmapLastUpdate = 0
    } else if (this.satelliteData.length > 0) {
      this.renderSatHeatmap()
    }
  }

  clearHeatmap() {
    const ds = this._satellitesDataSource
    if (ds && this._heatmapEntities.length > 0) {
      this._heatmapEntities.forEach(e => ds.entities.remove(e))
    }
    this._heatmapEntities = []
  }

  // Snap lat/lng to nearest hex cell on a fixed global grid
  // Pointy-top hex: size S = 1.0° (center-to-vertex)
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

  renderSatHeatmap() {
    const Cesium = window.Cesium
    const sat = window.satellite
    if (!sat || this.satelliteData.length === 0) return

    const nowMs = Date.now()
    const hitLifeMs = this._heatmapHitLifeSec * 1000

    // Throttle: only recompute grid every 10 seconds
    const shouldRecompute = (nowMs - this._heatmapLastUpdate) > 10000

    if (shouldRecompute) {
      this._heatmapLastUpdate = nowMs
      const now = new Date(nowMs)
      const gmst = sat.gstime(now)

      // Compute satellite positions, limit to 200
      const satPositions = []
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
          satPositions.push({ lat: sLat, lng: sLng, radiusKm: scanRadiusKm })
        } catch { /* skip */ }
      }

      // Stamp hex cells under each satellite footprint
      const S = 0.12
      const sqrt3 = Math.sqrt(3)
      const rowStep = S * 1.5
      const colStep = S * sqrt3

      const hasFilter = this.hasActiveFilter()

      satPositions.forEach(sp => {
        const radiusDeg = sp.radiusKm / 111.32

        for (let la = sp.lat - radiusDeg; la <= sp.lat + radiusDeg; la += rowStep) {
          for (let ln = sp.lng - radiusDeg; ln <= sp.lng + radiusDeg; ln += colStep) {
            const cell = this._snapToHexGrid(la, ln)
            const dLat = (cell.lat - sp.lat) * 111.32
            const cosLat = Math.cos(sp.lat * Math.PI / 180) || 0.01
            const dLng = (cell.lng - sp.lng) * 111.32 * cosLat
            const dist = Math.sqrt(dLat * dLat + dLng * dLng)
            if (dist > sp.radiusKm) continue

            // Only stamp cells inside the selected country/circle
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

    // Prune expired hits and remove empty cells
    for (const [key, cell] of this._heatmapGrid) {
      cell.hits = cell.hits.filter(t => (nowMs - t) < hitLifeMs)
      if (cell.hits.length === 0) this._heatmapGrid.delete(key)
    }

    // ── Render ──
    this.clearHeatmap()
    const dataSource = this.getSatellitesDataSource()
    const bounds = this.hasActiveFilter() ? this.getFilterBounds() : this.getViewportBounds()

    let maxHits = 1
    for (const cell of this._heatmapGrid.values()) {
      if (cell.hits.length > maxHits) maxHits = cell.hits.length
    }

    const S = 0.12
    const heightPerHit = 2000  // 2km per satellite pass
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

      const cosLat = Math.cos(cell.lat * Math.PI / 180) || 0.01
      const verts = []
      for (let i = 0; i < 6; i++) {
        const angle = (Math.PI / 3) * i + (Math.PI / 6) // pointy-top
        const vLat = cell.lat + S * Math.sin(angle)
        const vLng = cell.lng + (S * Math.cos(angle)) / cosLat
        verts.push(Cesium.Cartesian3.fromDegrees(vLng, vLat))
      }

      const extrudedHeight = 100 + count * heightPerHit  // 100m base + 5km per pass

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

    this._satFootprintEntities.forEach(e => dataSource.entities.remove(e))
    this._satFootprintEntities = []

    const baseColor = Cesium.Color.fromCssColorString(color)
    const satPos = Cesium.Cartesian3.fromDegrees(lng, lat, alt)

    const scanRadiusKm = altKm * Math.tan(10 * Math.PI / 180)
    const numRings = 4
    const hexSize = scanRadiusKm / (numRings + 0.5)
    const sqrt3 = Math.sqrt(3)
    const cosLat = Math.cos(lat * Math.PI / 180)

    // Generate hex centers using axial coordinates (q, r)
    // Flat-top hex: x = size * 3/2 * q, y = size * sqrt3 * (r + q/2)
    const hexCenters = [{ q: 0, r: 0 }]
    const cubeDirs = [
      { q: 1, r: 0 },  { q: 1, r: -1 }, { q: 0, r: -1 },
      { q: -1, r: 0 }, { q: -1, r: 1 }, { q: 0, r: 1 },
    ]

    for (let ring = 1; ring <= numRings; ring++) {
      let q = ring, r = 0
      for (let d = 0; d < 6; d++) {
        for (let s = 0; s < ring; s++) {
          hexCenters.push({ q, r })
          q += cubeDirs[(d + 2) % 6].q
          r += cubeDirs[(d + 2) % 6].r
        }
      }
    }

    // Render each hex
    hexCenters.forEach(({ q, r }) => {
      const cx = hexSize * 1.5 * q
      const cy = hexSize * sqrt3 * (r + q / 2)
      const dist = Math.sqrt(cx * cx + cy * cy)
      if (dist > scanRadiusKm * 1.05) return

      const verts = []
      for (let i = 0; i < 6; i++) {
        const angle = (Math.PI / 3) * i
        const vx = cx + hexSize * 0.93 * Math.cos(angle)
        const vy = cy + hexSize * 0.93 * Math.sin(angle)
        verts.push(Cesium.Cartesian3.fromDegrees(
          lng + vx / (111.32 * cosLat),
          lat + vy / 111.32,
          0
        ))
      }

      const falloff = Math.max(0, 1 - dist / scanRadiusKm)
      const entity = dataSource.entities.add({
        polygon: {
          hierarchy: verts,
          material: baseColor.withAlpha(0.02 + falloff * 0.1),
          outline: true,
          outlineColor: baseColor.withAlpha(0.08 + falloff * 0.2),
          height: 0,
        },
      })
      this._satFootprintEntities.push(entity)
    })

    // Nadir line
    this._satFootprintEntities.push(dataSource.entities.add({
      polyline: {
        positions: [satPos, Cesium.Cartesian3.fromDegrees(lng, lat, 0)],
        width: 1.5,
        material: baseColor.withAlpha(0.4),
      },
    }))

    // Cone lines to 6 outer points
    for (let i = 0; i < 6; i++) {
      const angle = (Math.PI / 3) * i
      const oLat = lat + (scanRadiusKm * Math.sin(angle)) / 111.32
      const oLng = lng + (scanRadiusKm * Math.cos(angle)) / (111.32 * cosLat)
      this._satFootprintEntities.push(dataSource.entities.add({
        polyline: {
          positions: [satPos, Cesium.Cartesian3.fromDegrees(oLng, oLat, 0)],
          width: 1,
          material: baseColor.withAlpha(0.15),
        },
      }))
    }

    // Nadir dot
    this._satFootprintEntities.push(dataSource.entities.add({
      position: Cesium.Cartesian3.fromDegrees(lng, lat, 0),
      point: {
        pixelSize: 5,
        color: baseColor.withAlpha(0.7),
        outlineColor: baseColor.withAlpha(0.2),
        outlineWidth: 6,
      },
    }))
  }

  // ── Ships ────────────────────────────────────────────────

  async fetchShips() {
    if (!this.shipsVisible) return

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
            font: "10px sans-serif",
            fillColor: Cesium.Color.fromCssColorString("#26c6da"),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 2,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: new Cesium.Cartesian2(14, 0),
            scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 2e6, 0),
            translucencyByDistance: new Cesium.NearFarScalar(1e4, 1, 5e6, 0),
          },
        })

        this.shipData.set(mmsi, {
          entity,
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
      }
    }
  }

  getShipsDataSource() {
    const Cesium = window.Cesium
    if (!this._shipsDataSource) {
      this._shipsDataSource = new Cesium.CustomDataSource("ships")
      this.viewer.dataSources.add(this._shipsDataSource)
    }
    return this._shipsDataSource
  }

  _isMilitaryFlight(f) {
    const cs = (f.callsign || "").toUpperCase()
    if (!cs) return false

    // Known military callsign prefixes
    const milPrefixes = [
      // US military
      "RCH",    // USAF C-17/C-5 (Reach)
      "RRR",    // USAF KC-135 tankers
      "DUKE",   // US Army
      "EVAC",   // Aeromedical evacuation
      "KING",   // USAF HC-130 rescue
      "FORTE",  // RQ-4 Global Hawk
      "JAKE",   // USAF
      "HOMER",  // USAF P-8
      "IRON",   // USAF
      "DOOM",   // USAF F-35
      "VIPER",  // USAF F-16
      "RAGE",   // USAF
      "REAPER", // MQ-9 Reaper
      "TOPCAT", // US Navy
      "NAVY",   // US Navy
      "ARMY",   // US Army
      "CNV",    // US Navy carrier
      "PAT",    // US Navy P-8/P-3
      // NATO / international
      "NATO",   // NATO
      "MMF",    // French Air Force
      "GAF",    // German Air Force
      "BAF",    // Belgian Air Force
      "RFR",    // French Air Force
      "IAM",    // Italian Air Force
      "ASCOT",  // RAF (UK)
      "RRF",    // French Navy
      "SPAR",   // USAF VIP (SAM when POTUS)
      "SAM",    // Special Air Mission
      "EXEC",   // Executive flight (US govt)
      "CFC",    // Canadian Forces
      "SHF",    // Swedish Air Force
      "PLF",    // Polish Air Force
      "HAF",    // Hellenic Air Force
      "HRZ",    // Croatian Air Force
      "TUAF",   // Turkish Air Force
      "FAB",    // Brazilian Air Force
      "RFAF",   // Royal Air Force
    ]

    for (const p of milPrefixes) {
      if (cs.startsWith(p)) return true
    }

    // ICAO-assigned military hex blocks (common ones)
    const hex = (f.id || "").toLowerCase()
    if (hex) {
      // US military: AE0000-AE ffff
      if (hex.startsWith("ae")) return true
      // Some other military ranges
      if (hex.startsWith("43c")) return true // UK military
    }

    return false
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
    if (this._shipsDataSource) {
      this._shipsDataSource.show = this.shipsVisible
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
  }

  // ── Country Borders, Selection & Draw Tool ───────────────

  screenToLatLng(screenPos) {
    const Cesium = window.Cesium
    const ray = this.viewer.camera.getPickRay(screenPos)
    const cartesian = this.viewer.scene.globe.pick(ray, this.viewer.scene)
    if (!cartesian) return null
    const carto = Cesium.Cartographic.fromCartesian(cartesian)
    return { lat: Cesium.Math.toDegrees(carto.latitude), lng: Cesium.Math.toDegrees(carto.longitude) }
  }

  haversineDistance(a, b) {
    const R = 6371000
    const toRad = d => d * Math.PI / 180
    const dLat = toRad(b.lat - a.lat)
    const dLng = toRad(b.lng - a.lng)
    const sin2 = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2
    return R * 2 * Math.atan2(Math.sqrt(sin2), Math.sqrt(1 - sin2))
  }

  // Point-in-polygon (ray casting)
  pointInPolygon(lat, lng, ring) {
    let inside = false
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const xi = ring[i][0], yi = ring[i][1]
      const xj = ring[j][0], yj = ring[j][1]
      if ((yi > lat) !== (yj > lat) && lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
        inside = !inside
      }
    }
    return inside
  }

  findCountryAtPoint(lat, lng) {
    for (const feature of this._countryFeatures) {
      const geom = feature.geometry
      const name = feature.properties?.NAME || feature.properties?.name
      if (!geom || !name) continue

      const polygons = geom.type === "Polygon" ? [geom.coordinates] : geom.type === "MultiPolygon" ? geom.coordinates : []
      for (const poly of polygons) {
        if (this.pointInPolygon(lat, lng, poly[0])) return name
      }
    }
    return null
  }

  // ── Cities Layer ─────────────────────────────────────────

  toggleCities() {
    this.citiesVisible = this.hasCitiesToggleTarget && this.citiesToggleTarget.checked
    console.log("toggleCities called, visible:", this.citiesVisible, "loaded:", this._citiesLoaded)
    if (this.citiesVisible) {
      if (!this._citiesLoaded) {
        this.loadCities()
      } else {
        this.renderCities()
      }
    } else {
      this.clearCities()
    }
  }

  getCitiesDataSource() {
    const Cesium = window.Cesium
    if (!this._citiesDataSource) {
      this._citiesDataSource = new Cesium.CustomDataSource("cities")
      this.viewer.dataSources.add(this._citiesDataSource)
    }
    return this._citiesDataSource
  }

  async loadCities() {
    console.log("loadCities: starting fetch...")
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

      console.log(`Cities loaded: ${this._citiesData.length} cities, ${this._urbanAreas.length} urban areas`)

      this._citiesLoaded = true
      this.renderCities()
    } catch (e) {
      console.error("Failed to load cities:", e, e.message, e.stack)
    }
  }

  clearCities() {
    const ds = this._citiesDataSource
    if (ds) {
      this._cityEntities.forEach(e => ds.entities.remove(e))
    }
    this._cityEntities = []
  }

  renderCities() {
    const Cesium = window.Cesium
    this.clearCities()
    if (!this.citiesVisible || this._citiesData.length === 0) return

    const dataSource = this.getCitiesDataSource()
    dataSource.show = true
    const hasFilter = this.hasActiveFilter()

    let cities = this._citiesData
    console.log(`renderCities: ${cities.length} total, selectedCountries: ${this.selectedCountries.size}, hasFilter: ${hasFilter}`)

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

    console.log(`renderCities: ${cities.length} after filter, urbanAreas: ${this._urbanAreas?.length || 0}`)
    const maxPop = cities.length > 0 ? cities[0].population : 1

    cities.forEach((city, idx) => {
      try {
        const popRatio = city.population / maxPop
        const pixelSize = city.capital ? 7 : Math.max(3, Math.round(popRatio * 6 + 2))

        const color = city.capital
          ? Cesium.Color.fromCssColorString("#ffd54f")
          : Cesium.Color.fromCssColorString("#e0e0e0")

        const entity = dataSource.entities.add({
          position: Cesium.Cartesian3.fromDegrees(city.lng, city.lat, 100),
          point: {
            pixelSize,
            color: color.withAlpha(0.9),
            outlineColor: color.withAlpha(0.5),
            outlineWidth: 1,
          },
          label: {
            text: city.name,
            font: city.capital ? "bold 12px sans-serif" : "11px sans-serif",
            fillColor: Cesium.Color.WHITE.withAlpha(0.9),
            outlineColor: Cesium.Color.BLACK.withAlpha(0.8),
            outlineWidth: 2,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: new Cesium.Cartesian2(0, -14),
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 1e7, 0.3),
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

          const positions = outerRing.map(c => Cesium.Cartesian3.fromDegrees(c[0], c[1], 50))

          try {
            const entity = dataSource.entities.add({
              polygon: {
                hierarchy: positions,
                material: urbanColor,
                outline: true,
                outlineColor: urbanOutline,
                outlineWidth: 1,
                height: 50,
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
        if (this._bordersDataSource) this._bordersDataSource.show = true
      }
      this.viewer.canvas.style.cursor = "pointer"
    } else {
      this.viewer.canvas.style.cursor = ""
    }
    // Update button state
    const btn = document.getElementById("country-select-btn")
    if (btn) btn.classList.toggle("active", this.countrySelectMode)
  }

  toggleBorders() {
    this.bordersVisible = this.hasBordersToggleTarget && this.bordersToggleTarget.checked
    if (this.bordersVisible && !this.bordersLoaded) {
      this.loadBorders()
    }
    if (this._bordersDataSource) {
      this._bordersDataSource.show = this.bordersVisible
    }
  }

  async loadBorders() {
    const Cesium = window.Cesium

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
      this._bordersDataSource.show = this.bordersVisible
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

    // Re-fetch active layers with updated filter
    if (this.flightsVisible) this.fetchFlights()
    if (this.shipsVisible) this.fetchShips()
    this.updateEntityList()
    if (this.citiesVisible) this.renderCities()
  }

  clearCountrySelection() {
    this.selectedCountries.clear()
    this._selectedCountriesBbox = null
    this._activeCircle = null
    this.countrySelectMode = false
    this.viewer.canvas.style.cursor = ""
    this.removeDrawCircle()
    this.updateBorderColors()
    this.closeDetail()

    // Re-fetch with no filter (back to viewport)
    if (this.flightsVisible) this.fetchFlights()
    if (this.shipsVisible) this.fetchShips()
    this.updateEntityList()
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
      if (this._bordersDataSource) this._bordersDataSource.show = true
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
    if (this._drawCircleEntity && this._bordersDataSource) {
      this._bordersDataSource.entities.remove(this._drawCircleEntity)
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
    this.updateEntityList()
  }

  getBordersDataSource() {
    const Cesium = window.Cesium
    if (!this._bordersDataSource) {
      this._bordersDataSource = new Cesium.CustomDataSource("borders")
      this.viewer.dataSources.add(this._bordersDataSource)
    }
    return this._bordersDataSource
  }

  // ── Camera Controls ──────────────────────────────────────

  resetView() {
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(10, 30, 20_000_000),
      orientation: { heading: 0, pitch: -Cesium.Math.PI_OVER_TWO, roll: 0 },
      duration: 1.5,
    })
  }

  viewTopDown() {
    const Cesium = window.Cesium
    const carto = this.viewer.camera.positionCartographic
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(
        Cesium.Math.toDegrees(carto.longitude),
        Cesium.Math.toDegrees(carto.latitude),
        carto.height
      ),
      orientation: { heading: 0, pitch: -Cesium.Math.PI_OVER_TWO, roll: 0 },
      duration: 1,
    })
  }

  resetTilt() {
    const Cesium = window.Cesium
    const carto = this.viewer.camera.positionCartographic
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(
        Cesium.Math.toDegrees(carto.longitude),
        Cesium.Math.toDegrees(carto.latitude),
        carto.height
      ),
      orientation: {
        heading: this.viewer.camera.heading,
        pitch: -Cesium.Math.PI_OVER_TWO,
        roll: 0,
      },
      duration: 0.8,
    })
  }

  zoomIn() {
    const Cesium = window.Cesium
    const carto = this.viewer.camera.positionCartographic
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(
        Cesium.Math.toDegrees(carto.longitude),
        Cesium.Math.toDegrees(carto.latitude),
        carto.height * 0.5
      ),
      duration: 0.5,
    })
  }

  zoomOut() {
    const Cesium = window.Cesium
    const carto = this.viewer.camera.positionCartographic
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(
        Cesium.Math.toDegrees(carto.longitude),
        Cesium.Math.toDegrees(carto.latitude),
        Math.min(carto.height * 2, 40_000_000)
      ),
      duration: 0.5,
    })
  }

  toggleTrains() {
    // Placeholder
  }

  toggleCameras() {
    // Placeholder
  }

  disconnect() {
    if (this.flightInterval) clearInterval(this.flightInterval)
    if (this.shipInterval) clearInterval(this.shipInterval)
    if (this.animationFrame) cancelAnimationFrame(this.animationFrame)
    if (this._handler) this._handler.destroy()
    if (this.viewer) this.viewer.destroy()
  }
}
