import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { cesiumToken: String }
  static targets = ["flightsToggle", "satellitesToggle", "trainsToggle", "camerasToggle", "detailPanel", "detailContent", "flightCount", "trailsToggle"]

  connect() {
    this.flightsVisible = true
    this.flightInterval = null
    this.flightData = new Map() // icao24 -> { entity, lat, lng, alt, heading, speed }
    this.animationFrame = null
    this.lastAnimTime = null
    this.trailsVisible = false
    this.trailHistory = new Map() // icao24 -> [{lat, lng, alt}]
    this.trackedFlightId = null
    this.satellitesVisible = true
    this.satelliteData = [] // raw TLE records from API
    this.satelliteEntities = new Map()
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
      const picked = this.viewer.scene.pick(click.position)
      if (Cesium.defined(picked) && picked.id) {
        const entityId = picked.id.id || picked.id
        const flightData = this.flightData.get(entityId)
        if (flightData) {
          this.showDetail(entityId, flightData)
          return
        }
        // Check if it's a satellite
        if (typeof entityId === "string" && entityId.startsWith("sat-")) {
          const noradId = parseInt(entityId.replace("sat-", ""))
          const satData = this.satelliteData.find(s => s.norad_id === noradId)
          if (satData) {
            this.showSatelliteDetail(satData)
            return
          }
        }
      }
      this.closeDetail()
    }, Cesium.ScreenSpaceEventType.LEFT_CLICK)
    this._handler = handler

    // Create plane icon
    this.planeIcon = this.createPlaneIcon("#4fc3f7")
    this.planeIconGround = this.createPlaneIcon("#888888")

    // Fetch flights on camera move and on interval
    this.fetchFlights()
    this.flightInterval = setInterval(() => this.fetchFlights(), 10000)
    this.viewer.camera.moveEnd.addEventListener(() => this.fetchFlights())

    // Fetch satellites (TLE data, computed client-side)
    this.fetchSatellites()

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

  async fetchFlights() {
    if (!this.flightsVisible) return

    try {
      let url = "/api/flights"
      const bounds = this.getViewportBounds()
      if (bounds) {
        const params = new URLSearchParams(bounds).toString()
        url += `?${params}`
      }

      const response = await fetch(url)
      if (!response.ok) return

      const flights = await response.json()
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

        // Blend: set current position to weighted average of where we think
        // the plane is (currentLat) and where the server says it should be (projLat)
        // This avoids hard snaps while correcting drift
        existing.currentLat = existing.currentLat * 0.3 + projLat * 0.7
        existing.currentLng = existing.currentLng * 0.3 + projLng * 0.7
        existing.currentAlt = existing.currentAlt * 0.3 + projAlt * 0.7

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
          currentLat: projLat,
          currentLng: projLng,
          currentAlt: projAlt,
          heading,
          speed,
          verticalRate,
          onGround,
          originCountry: flight.origin_country,
        })
      }
    })

    // Remove flights no longer in view
    for (const [id, data] of this.flightData) {
      if (!currentIds.has(id)) {
        dataSource.entities.remove(data.entity)
        this.flightData.delete(id)
        this.trailHistory.delete(id)
      }
    }

    // Update flight count
    if (this.hasFlightCountTarget) {
      this.flightCountTarget.textContent = `${this.flightData.size.toLocaleString()} flights`
    }

    // Render trails
    if (this.trailsVisible) this.renderTrails()
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
    if (this.satellitesVisible && this.satelliteData.length > 0) {
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
    if (this.flightsVisible) this.fetchFlights()
  }

  async fetchSatellites() {
    try {
      // Fetch specific interesting categories instead of all active sats
      const categories = ["stations", "starlink", "gps-ops", "weather"]
      const allSats = []

      for (const cat of categories) {
        const response = await fetch(`/api/satellites?category=${cat}`)
        if (!response.ok) continue
        const sats = await response.json()
        allSats.push(...sats)
      }

      this.satelliteData = allSats
      this.updateSatellitePositions()
    } catch (e) {
      console.error("Failed to fetch satellites:", e)
    }
  }

  updateSatellitePositions() {
    const Cesium = window.Cesium
    const sat = window.satellite
    if (!sat) return

    const dataSource = this.getSatellitesDataSource()
    const now = new Date()
    const gmst = sat.gstime(now)

    const categoryColors = {
      stations: "#ff5252",
      starlink: "#ab47bc",
      "gps-ops": "#66bb6a",
      weather: "#ffa726",
    }

    const currentIds = new Set()

    this.satelliteData.forEach(s => {
      try {
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) return

        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        const lng = sat.degreesLong(posGd.longitude)
        const lat = sat.degreesLat(posGd.latitude)
        const alt = posGd.height * 1000 // km to m

        if (isNaN(lng) || isNaN(lat) || isNaN(alt)) return

        const id = `sat-${s.norad_id}`
        currentIds.add(id)
        const color = categoryColors[s.category] || "#ab47bc"

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

    // Remove stale
    for (const [id, entity] of this.satelliteEntities) {
      if (!currentIds.has(id)) {
        dataSource.entities.remove(entity)
        this.satelliteEntities.delete(id)
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

  toggleSatellites() {
    this.satellitesVisible = this.satellitesToggleTarget.checked
    if (this._satellitesDataSource) {
      this._satellitesDataSource.show = this.satellitesVisible
    }
    if (this.satellitesVisible && this.satelliteData.length === 0) {
      this.fetchSatellites()
    }
  }

  toggleTrains() {
    // Placeholder
  }

  toggleCameras() {
    // Placeholder
  }

  disconnect() {
    if (this.flightInterval) clearInterval(this.flightInterval)
    if (this.animationFrame) cancelAnimationFrame(this.animationFrame)
    if (this._handler) this._handler.destroy()
    if (this.viewer) this.viewer.destroy()
  }
}
