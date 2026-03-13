import { getDataSource } from "../utils"

export function applyFlightMethods(GlobeController) {
  GlobeController.prototype.fetchFlights = async function() {
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

  GlobeController.prototype.renderFlights = function(flights) {
    const Cesium = window.Cesium
    const dataSource = this.getFlightsDataSource()
    const currentIds = new Set()

    dataSource.entities.suspendEvents()
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
        existing.squawk = flight.squawk
        existing.emergency = flight.emergency
        existing.category = flight.category
        existing.mach = flight.mach
        existing.trueAirspeed = flight.true_airspeed
        existing.windDirection = flight.wind_direction
        existing.windSpeed = flight.wind_speed
        existing.outsideAirTemp = flight.outside_air_temp
        existing.navAltitudeFms = flight.nav_altitude_fms

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

        const milCheck = { id, callsign, military: flight.military }
        const isMil = this._isMilitaryFlight(milCheck)
        const isEmergency = this._isEmergencyFlight(flight)
        existing.entity.billboard.image = this._flightIcon(flight, isMil)
        existing.entity.billboard.rotation = -Cesium.Math.toRadians(heading)
        existing.entity.label.text = isEmergency ? `${callsign} [${flight.squawk || "EMG"}]` : callsign
        existing.entity.label.fillColor = isEmergency ? Cesium.Color.fromCssColorString("#ff9800") : Cesium.Color.WHITE.withAlpha(0.95)
      } else {
        const milCheck = { id, callsign, military: flight.military }
        const isMil = this._isMilitaryFlight(milCheck)
        const isEmergency = this._isEmergencyFlight(flight)
        const pos = Cesium.Cartesian3.fromDegrees(projLng, projLat, projAlt)
        const entity = dataSource.entities.add({
          id: id,
          position: pos,
          billboard: {
            image: this._flightIcon(flight, isMil),
            scale: isEmergency ? 1.1 : 0.8,
            rotation: -Cesium.Math.toRadians(heading),
            alignedAxis: Cesium.Cartesian3.UNIT_Z,
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, isEmergency ? 0.5 : 0.3),
          },
          label: {
            text: isEmergency ? `${callsign} [${flight.squawk || "EMG"}]` : callsign,
            font: "15px JetBrains Mono, monospace",
            fillColor: isEmergency ? Cesium.Color.fromCssColorString("#ff9800") : Cesium.Color.WHITE.withAlpha(0.95),
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
          squawk: flight.squawk,
          emergency: flight.emergency,
          category: flight.category,
          mach: flight.mach,
          trueAirspeed: flight.true_airspeed,
          windDirection: flight.wind_direction,
          windSpeed: flight.wind_speed,
          outsideAirTemp: flight.outside_air_temp,
          navAltitudeFms: flight.nav_altitude_fms,
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
    dataSource.entities.resumeEvents()

    // Update stats and airline detection
    this._updateStats()
    this._detectAirlines()

    // Render trails
    if (this.trailsVisible) this.renderTrails()

    // Update entity list if visible
    if (this.hasActiveFilter() && this.entityListPanelTarget.classList.contains("rp-pane--active")) {
      this.updateEntityList()
    }

    this.viewer.scene.requestRender()
  }

  // Simplify trail by removing redundant straight-line points (Ramer-Douglas-Peucker),
  // then smooth the remaining key points with a Catmull-Rom spline.

  GlobeController.prototype._interpolateTrailSpline = function(positions, segmentsPerPoint = 4) {
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

  GlobeController.prototype._rdpSimplify = function(points, epsilon) {
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

  GlobeController.prototype._pointToLineDist = function(p, a, b, Cesium) {
    const ap = Cesium.Cartesian3.subtract(p, a, new Cesium.Cartesian3())
    const ab = Cesium.Cartesian3.subtract(b, a, new Cesium.Cartesian3())
    const abLen = Cesium.Cartesian3.magnitude(ab)
    if (abLen < 1e-10) return Cesium.Cartesian3.distance(p, a)

    const cross = Cesium.Cartesian3.cross(ap, ab, new Cesium.Cartesian3())
    return Cesium.Cartesian3.magnitude(cross) / abLen
  }

  GlobeController.prototype.renderTrails = function() {
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

  GlobeController.prototype.getTrailsDataSource = function() { return getDataSource(this.viewer, this._ds, "trails") }

  GlobeController.prototype.toggleTrails = function() {
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

  GlobeController.prototype.toggleFlightFilter = function() {
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

  GlobeController.prototype.showDetail = function(id, data) {
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

    const isEmergency = this._isEmergencyFlight(data)
    const squawkLabels = { "7500": "HIJACK", "7600": "RADIO FAIL", "7700": "EMERGENCY" }
    const squawkDisplay = data.squawk ? (squawkLabels[data.squawk] ? `${data.squawk} (${squawkLabels[data.squawk]})` : data.squawk) : null

    this.detailContentTarget.innerHTML = `
      ${isEmergency ? `<div class="detail-emergency-banner">${squawkLabels[data.squawk] || (data.emergency || "EMERGENCY").toUpperCase()}</div>` : ""}
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
        ${data.mach ? `<div class="detail-field">
          <span class="detail-label">Mach</span>
          <span class="detail-value">${data.mach.toFixed(3)}</span>
        </div>` : ""}
        ${squawkDisplay ? `<div class="detail-field">
          <span class="detail-label">Squawk</span>
          <span class="detail-value" ${isEmergency ? 'style="color:#ff9800;font-weight:bold;"' : ""}>${squawkDisplay}</span>
        </div>` : ""}
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
        ${data.category ? `<div class="detail-field">
          <span class="detail-label">Category</span>
          <span class="detail-value">${data.category}</span>
        </div>` : ""}
        ${data.windDirection != null && data.windSpeed != null ? `<div class="detail-field">
          <span class="detail-label">Wind</span>
          <span class="detail-value">${data.windDirection}° / ${data.windSpeed} kt</span>
        </div>` : ""}
        ${data.outsideAirTemp != null ? `<div class="detail-field">
          <span class="detail-label">OAT</span>
          <span class="detail-value">${data.outsideAirTemp}°C</span>
        </div>` : ""}
        ${data.navAltitudeFms ? `<div class="detail-field">
          <span class="detail-label">Target Alt</span>
          <span class="detail-value">${Math.round(data.navAltitudeFms).toLocaleString()} ft</span>
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
      <div style="display:flex;gap:6px;align-items:center;">
        <button class="detail-track-btn ${isTracking ? "tracking" : ""}" data-flight-id="${id}" style="flex:1;">
          ${isTracking ? "Stop Tracking" : "Track Flight"}
        </button>
        ${isTracking ? `<button class="detail-track-btn" id="tracking-height-btn" style="flex:0;white-space:nowrap;">${this._trackingHeightLabels[this._trackingHeightIdx]}</button>` : ""}
      </div>
      ${this.signedInValue ? `<button class="detail-watch-btn" data-action="click->globe#createWatch"
        data-watch-type="entity"
        data-watch-name="Watch ${callsign || id}"
        data-watch-conditions='${JSON.stringify({ entity_type: "flight", identifier: callsign || id, match: "callsign_exact" })}'>
        <i class="fa-solid fa-eye"></i> Watch
      </button>` : ""}
      ${this.signedInValue ? `<button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showFlightHistory" data-flight-icao="${id}">
        <i class="fa-solid fa-clock-rotate-left" style="margin-right:4px;"></i>Flight History (24h)
      </button>` : ""}
      ${this._connectionsPlaceholder()}
    `

    // Bind track button
    this.detailContentTarget.querySelector(".detail-track-btn[data-flight-id]").addEventListener("click", (e) => {
      const fid = e.currentTarget.dataset.flightId
      if (this.trackedFlightId === fid) {
        this.stopTracking()
      } else {
        this.trackFlight(fid)
      }
      const d = this.flightData.get(fid)
      if (d) this.showDetail(fid, d)
    })
    const hBtn = document.getElementById("tracking-height-btn")
    if (hBtn) hBtn.addEventListener("click", () => {
      this.cycleTrackingHeight()
      const fid = this.trackedFlightId
      const d = fid && this.flightData.get(fid)
      if (d) this.showDetail(fid, d)
    })

    this.detailPanelTarget.style.display = ""

    // Fetch connections
    this._fetchConnections("flight", data.currentLat, data.currentLng, {
      squawk: data.squawk || "",
      origin_country: data.originCountry || "",
    })

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

  GlobeController.prototype._getAirport = function(icao) {
    return this._airportDb[icao] || null
  }

  GlobeController.prototype._fetchAirportData = async function() {
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

  GlobeController.prototype.fetchRoute = async function(callsign) {
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

  GlobeController.prototype._drawFlightRoute = function(callsign, origin, dest) {
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

  GlobeController.prototype.showFlightHistory = async function(event) {
    const icao = event.currentTarget.dataset.flightIcao
    if (!icao) return
    const btn = event.currentTarget
    btn.disabled = true
    btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin" style="margin-right:4px;"></i>Loading...'

    try {
      const resp = await fetch(`/api/exports/flight_history/${encodeURIComponent(icao)}`)
      if (!resp.ok) throw new Error("Not found")
      const data = await resp.json()

      if (!data.route || data.route.length < 2) {
        btn.innerHTML = '<i class="fa-solid fa-clock-rotate-left" style="margin-right:4px;"></i>No history available'
        btn.disabled = false
        return
      }

      // Render the historical trail on the globe
      this._clearFlightHistory()
      const Cesium = window.Cesium
      const ds = this._ds["flights"] || this.getEventsDataSource()
      this._flightHistoryEntities = []

      const positions = data.route.map(p => Cesium.Cartesian3.fromDegrees(p.lng, p.lat, p.alt || 0))

      const trail = ds.entities.add({
        id: `flt-history-${icao}`,
        polyline: {
          positions,
          width: 2,
          material: new Cesium.PolylineGlowMaterialProperty({
            glowPower: 0.2,
            color: Cesium.Color.fromCssColorString("#ce93d8").withAlpha(0.8),
          }),
          clampToGround: false,
        },
      })
      this._flightHistoryEntities.push(trail)

      // Start point marker
      const first = data.route[0]
      const startE = ds.entities.add({
        id: `flt-history-start-${icao}`,
        position: Cesium.Cartesian3.fromDegrees(first.lng, first.lat, first.alt || 0),
        point: { pixelSize: 6, color: Cesium.Color.fromCssColorString("#ce93d8"), outlineColor: Cesium.Color.WHITE, outlineWidth: 1 },
        label: {
          text: `${data.callsign || icao} (${new Date(first.t * 1000).toISOString().slice(11, 16)} UTC)`,
          font: "10px monospace",
          fillColor: Cesium.Color.fromCssColorString("#ce93d8"),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 2,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -12),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.0, 5e6, 0.3),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._flightHistoryEntities.push(startE)

      this._requestRender()
      btn.innerHTML = `<i class="fa-solid fa-clock-rotate-left" style="margin-right:4px;"></i>${data.point_count} points loaded`
      btn.disabled = false
    } catch (e) {
      console.warn("Flight history failed:", e)
      btn.innerHTML = '<i class="fa-solid fa-clock-rotate-left" style="margin-right:4px;"></i>History unavailable'
      btn.disabled = false
    }
  }

  GlobeController.prototype._clearFlightHistory = function() {
    if (!this._flightHistoryEntities?.length) return
    const ds = this._ds["flights"] || this._ds["events"]
    if (ds) this._flightHistoryEntities.forEach(e => ds.entities.remove(e))
    this._flightHistoryEntities = []
  }

  GlobeController.prototype._clearFlightRoute = function() {
    if (!this._flightRouteEntities) return
    const ds = this._ds["flights"]
    if (ds) {
      this._flightRouteEntities.forEach(e => ds.entities.remove(e))
    }
    this._flightRouteEntities = []
  }

  GlobeController.prototype._greatCirclePoints = function(lat1, lng1, lat2, lng2, numPoints) {
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

  GlobeController.prototype.trackFlight = function(id) {
    this.trackedFlightId = id
    this.trackedTrainId = null
    const data = this.flightData.get(id)
    if (data) {
      const Cesium = window.Cesium
      const h = this._trackingHeights[this._trackingHeightIdx]
      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(data.currentLng, data.currentLat, h),
        duration: 1.5,
      })
    }
  }

  GlobeController.prototype.stopTracking = function() {
    this.trackedFlightId = null
  }

  GlobeController.prototype.cycleTrackingHeight = function() {
    this._trackingHeightIdx = (this._trackingHeightIdx + 1) % this._trackingHeights.length
    const label = this._trackingHeightLabels[this._trackingHeightIdx]
    this._toast(`Tracking: ${label}`)
    const btn = document.getElementById("tracking-height-btn")
    if (btn) btn.textContent = label
  }

  GlobeController.prototype.closeDetail = function() {
    this.detailPanelTarget.style.display = "none"
    this._focusedSelection = null
    this._renderSelectionTray()
    this.stopTracking()
    this.stopTrainTracking()
    this.clearSatFootprint()
    this._clearFlightRoute()
    this._clearSatVisEntities()
    this._clearNewsArcEntities()
    if (this._clearShakeMap) this._clearShakeMap()
    if (this._clearFlightHistory) this._clearFlightHistory()
    if (this._webcamRefreshInterval) { clearInterval(this._webcamRefreshInterval); this._webcamRefreshInterval = null }
    if (this._ytMessageCleanup) { this._ytMessageCleanup(); this._ytMessageCleanup = null }
  }

  // ── Entity List Panel ─────────────────────────────────────

  GlobeController.prototype.getFlightsDataSource = function() { return getDataSource(this.viewer, this._ds, "flights") }

  GlobeController.prototype.toggleFlights = function() {
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

  GlobeController.prototype._isMilitaryFlight = function(f) {
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

  GlobeController.prototype._isEmergencyFlight = function(flight) {
    const sq = flight.squawk || ""
    if (sq === "7500" || sq === "7600" || sq === "7700") return true
    const em = (flight.emergency || "").toLowerCase()
    return em !== "" && em !== "none"
  }

  GlobeController.prototype._flightIcon = function(flight, isMil) {
    if (flight.onGround || flight.on_ground) return this.planeIconGround
    if (this._isEmergencyFlight(flight)) return this.planeIconEmergency
    if (isMil) return this.planeIconMil
    return this.planeIcon
  }

  // ── Airline Lookup & Filter ─────────────────────────────────

}
