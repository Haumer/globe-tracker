import { createSatelliteIcon, getDataSource } from "../../utils"

export function applySatDataMethods(GlobeController) {
  GlobeController.prototype.getSatellitesDataSource = function() { return getDataSource(this.viewer, this._ds, "satellites") }
  GlobeController.prototype.getSatOrbitsDataSource = function() { return getDataSource(this.viewer, this._ds, "sat-orbits") }

  GlobeController.prototype.fetchSatCategory = async function(cat) {
    this._toast("Loading satellites...")
    try {
      const response = await fetch(`/api/satellites?category=${cat}`)
      if (!response.ok) return
      const sats = await response.json()
      this._handleBackgroundRefresh(response, `satellites-${cat}`, sats.length > 0, () => {
        if (this.satCategoryVisible[cat]) this.fetchSatCategory(cat)
      })

      // Remove old data for this category, add fresh
      const removed = this.satelliteData.filter(s => s.category === cat)
      this.satelliteData = this.satelliteData.filter(s => s.category !== cat)
      this.satelliteData.push(...sats)
      this._loadedSatCategories.add(cat)
      // Invalidate cached satrec objects for refreshed TLEs
      if (this._satrecCache) removed.forEach(s => this._satrecCache.delete(s.norad_id))

      this.updateSatellitePositions()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch satellites:", e)
    }
  }

  Object.defineProperty(GlobeController.prototype, "satCategoryColors", {
    configurable: true,
    get: function() {
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
    },
  })

  GlobeController.prototype._getSatIcon = function(color) {
    if (!this._satIcons[color]) {
      this._satIcons[color] = createSatelliteIcon(color)
    }
    return this._satIcons[color]
  }

  // Compute target positions for satellites (called every ~2s)
  // Stores current + next position for smooth lerping in animate()

  GlobeController.prototype.updateSatellitePositions = function() {
    const Cesium = window.Cesium
    const sat = window.satellite
    if (!sat) return

    const dataSource = this.getSatellitesDataSource()
    const now = this._timelineActive && this._timelineCursor ? new Date(this._timelineCursor.getTime()) : new Date()
    const future = new Date(now.getTime() + 2000) // 2s ahead for lerp target
    const gmst = sat.gstime(now)
    const gmstF = sat.gstime(future)
    const currentIds = new Set()

    // Cache satrec objects — twoline2satrec is expensive
    if (!this._satrecCache) this._satrecCache = new Map()

    this.satelliteData.forEach(s => {
      if (!this.satCategoryVisible[s.category]) return

      try {
        let satrec = this._satrecCache.get(s.norad_id)
        if (!satrec) {
          satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
          this._satrecCache.set(s.norad_id, satrec)
        }
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

  GlobeController.prototype.renderSatOrbits = function() {
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

  GlobeController.prototype.toggleSatCategory = function(event) {
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

  GlobeController.prototype.toggleSatOrbits = function() {
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

  GlobeController.prototype.selectSatFootprint = function(noradId) {
    this.clearSatFootprint()
    this.selectedSatNoradId = noradId
    this.updateSatellitePositions()
  }

  GlobeController.prototype._clearNadirFootprint = function() {
    if (this._satFootprintEntities.length > 0 && this._ds["satellites"]) {
      this._satFootprintEntities.forEach(e => this._ds["satellites"].entities.remove(e))
      this._satFootprintEntities = []
    }
    this._nadirLinePositions = null
    this._nadirDotPosition = null
  }

  GlobeController.prototype.clearSatFootprint = function() {
    this.selectedSatNoradId = null
    this._selectedSatPosition = null
    this._selectedSatGeoLerp = null
    this._clearNadirFootprint()
  }
}
