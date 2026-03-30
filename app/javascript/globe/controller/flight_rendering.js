import { getDataSource, createPlaneIcon } from "../utils"

export function applyFlightRenderingMethods(GlobeController) {
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
        existing.military = flight.military
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

        const newTimePos = flight.time_position || 0
        if (newTimePos !== existing.lastTimePosition) {
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
          military: flight.military,
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
        entity.show = isMil ? this.showMilitary : this.showCivilian
      }
    })

    for (const [id, data] of this.flightData) {
      if (!currentIds.has(id)) {
        dataSource.entities.remove(data.entity)
        this.flightData.delete(id)
        this.trailHistory.delete(id)
        if (this.selectedFlights.has(id)) {
          this.selectedFlights.delete(id)
          this._removeFlightHighlight(id)
          this._renderSelectionTray()
        }
      }
    }
    dataSource.entities.resumeEvents()

    this._updateStats()
    this._detectAirlines()

    if (this.trailsVisible) this.renderTrails()

    if (this.hasActiveFilter() && this.entityListPanelTarget.classList.contains("rp-pane--active")) {
      this.updateEntityList()
    }

    this._requestRender()
  }

  GlobeController.prototype._serializeLoadedFlight = function(data) {
    if (!data?.id) return null

    return {
      icao24: data.id,
      callsign: data.callsign,
      latitude: data.currentLat ?? data.latitude,
      longitude: data.currentLng ?? data.longitude,
      altitude: data.currentAlt ?? data.altitude,
      speed: data.speed,
      heading: data.heading,
      origin_country: data.originCountry,
      on_ground: data.onGround,
      vertical_rate: data.verticalRate,
      time_position: data.lastTimePosition,
      source: data.source,
      military: data.military,
      squawk: data.squawk,
      emergency: data.emergency,
      category: data.category,
      registration: data.registration,
      aircraft_type: data.aircraftType,
      mach: data.mach,
      true_airspeed: data.trueAirspeed,
      wind_direction: data.windDirection,
      wind_speed: data.windSpeed,
      outside_air_temp: data.outsideAirTemp,
      nav_altitude_fms: data.navAltitudeFms,
    }
  }

  GlobeController.prototype.upsertFlightRecord = function(flight) {
    if (!flight?.icao24 || flight.latitude == null || flight.longitude == null) return null

    const currentFlights = Array.from(this.flightData.values())
      .map(data => this._serializeLoadedFlight(data))
      .filter(Boolean)
      .filter(data => `${data.icao24}` !== `${flight.icao24}`)

    this.renderFlights([...currentFlights, flight])
    if (this._ds["flights"]) this._ds["flights"].show = true

    return this.flightData.get(flight.icao24) || null
  }

  GlobeController.prototype._interpolateTrailSpline = function(positions, segmentsPerPoint = 4) {
    const Cesium = window.Cesium
    if (positions.length < 3) return positions

    const simplified = this._rdpSimplify(positions, 500)
    if (simplified.length < 3) return simplified

    const times = simplified.map((_, i) => i / (simplified.length - 1))
    const spline = new Cesium.CatmullRomSpline({ times, points: simplified })

    const smoothed = []
    const totalSegments = (simplified.length - 1) * segmentsPerPoint
    for (let i = 0; i <= totalSegments; i++) {
      smoothed.push(spline.evaluate(i / totalSegments))
    }
    return smoothed
  }

  GlobeController.prototype._rdpSimplify = function(points, epsilon) {
    if (points.length <= 2) return points

    const Cesium = window.Cesium
    const first = points[0]
    const last = points[points.length - 1]
    let maxDist = 0
    let maxIdx = 0

    for (let i = 1; i < points.length - 1; i++) {
      const d = this._pointToLineDist(points[i], first, last, Cesium)
      if (d > maxDist) {
        maxDist = d
        maxIdx = i
      }
    }

    if (maxDist > epsilon) {
      const left = this._rdpSimplify(points.slice(0, maxIdx + 1), epsilon)
      const right = this._rdpSimplify(points.slice(maxIdx), epsilon)
      return left.slice(0, -1).concat(right)
    }
    return [first, last]
  }

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
    for (const [, data] of this.flightData) {
      const isMil = this._isMilitaryFlight(data)
      const visible = isMil ? this.showMilitary : this.showCivilian
      data.entity.show = visible
    }
    this.updateEntityList()
    this._savePrefs()
  }

  GlobeController.prototype.toggleMilitaryFlightsFilter = function() {
    this._milFlightsActive = !this._milFlightsActive

    if (this._milFlightsActive) {
      this._fetchMilitaryFlights()
      if (!this._milFlightInterval) {
        this._milFlightInterval = setInterval(() => {
          if (this._milFlightsActive) this._fetchMilitaryFlights()
        }, 10000)
      }
    } else {
      this._clearMilFlightEntities()
      if (this._milFlightInterval) {
        clearInterval(this._milFlightInterval)
        this._milFlightInterval = null
      }
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._fetchMilitaryFlights = async function() {
    const bounds = this.getViewportBounds()
    let url = "/api/flights?filter=military"
    if (bounds) {
      url += `&lamin=${bounds.lamin}&lomin=${bounds.lomin}&lamax=${bounds.lamax}&lomax=${bounds.lomax}`
    }
    try {
      const resp = await fetch(url)
      if (!resp.ok) return
      const flights = await resp.json()
      this._milFlightData = flights
      this._renderMilFlights()
    } catch (e) {
      console.error("Military flights fetch failed:", e)
    }
  }

  GlobeController.prototype._renderMilFlights = function() {
    this._clearMilFlightEntities()
    if (!this._milFlightData?.length || !this._milFlightsActive) return

    const Cesium = window.Cesium
    const ds = getDataSource(this.viewer, this._ds, "mil-flights")

    ds.entities.suspendEvents()
    this._milFlightData.forEach(f => {
      if (!f.latitude || !f.longitude) return

      const entity = ds.entities.add({
        id: `milflt-${f.icao24}`,
        position: Cesium.Cartesian3.fromDegrees(f.longitude, f.latitude, (f.altitude || 0) * 0.3 + 50),
        billboard: {
          image: this._milPlaneIcon || (this._milPlaneIcon = createPlaneIcon("#ef5350")),
          scale: 0.9,
          rotation: -Cesium.Math.toRadians(f.heading || 0),
          alignedAxis: Cesium.Cartesian3.UNIT_Z,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.0, 8e6, 0.3),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: f.callsign || f.icao24 || "",
          font: "11px JetBrains Mono, sans-serif",
          fillColor: Cesium.Color.fromCssColorString("#ef5350").withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          pixelOffset: new Cesium.Cartesian2(0, 14),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 3e6, 0),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1, 2e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._milFlightEntities.push(entity)
    })
    ds.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._clearMilFlightEntities = function() {
    const ds = this._ds["mil-flights"]
    if (ds) {
      ds.entities.suspendEvents()
      this._milFlightEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
      this._requestRender()
    }
    this._milFlightEntities = []
  }

  GlobeController.prototype.getFlightsDataSource = function() { return getDataSource(this.viewer, this._ds, "flights") }

  GlobeController.prototype.toggleFlights = function() {
    this.flightsVisible = this.flightsToggleTarget.checked
    if (this._timelineActive) {
      this._timelineOnLayerToggle?.()
      this._savePrefs()
      return
    }
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
      if (this.flightInterval) {
        clearInterval(this.flightInterval)
        this.flightInterval = null
      }
      if (this._flightCameraCb) {
        this.viewer.camera.moveEnd.removeEventListener(this._flightCameraCb)
        this._flightCameraCb = null
      }
    }
    this._savePrefs()
  }

  GlobeController.prototype._isMilitaryFlight = function(f) {
    if (f.military === true) return true
    if (f.military === false) return false

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
      if (/^UAEAF/i.test(cs)) return true
      if (/^RSAF\d/i.test(cs)) return true
      if (/^RJAF/i.test(cs)) return true
      if (/^EAF\d/i.test(cs)) return true
      if (/^TAF\d/i.test(cs)) return true
    }

    if (hex) {
      if (hex >= "ae0000" && hex <= "afffff") return true
      if (hex.startsWith("43c")) return true
      if (hex >= "3a8000" && hex <= "3affff") return true
      if (hex >= "3f4000" && hex <= "3f7fff") return true
      if (hex >= "4b8000" && hex <= "4b8fff") return true
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
}
