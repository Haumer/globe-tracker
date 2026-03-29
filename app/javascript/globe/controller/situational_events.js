import { getDataSource, createAirportIcon, cachedColor, LABEL_DEFAULTS } from "../utils"
import {
  renderAirportDetailHtml,
  renderEarthquakeDetailHtml,
  renderNaturalEventDetailHtml,
} from "./situational_presenters"

export function applySituationalEventMethods(GlobeController) {
  GlobeController.prototype.getAirportsDataSource = function() { return getDataSource(this.viewer, this._ds, "airports") }

  GlobeController.prototype.toggleAirports = async function() {
    this.airportsVisible = this.hasAirportsToggleTarget && this.airportsToggleTarget.checked
    if (this.airportsVisible) {
      await this._fetchAirportData()
      this.renderAirports()
    } else {
      this._clearAirportEntities()
    }
    this._savePrefs()
  }

  GlobeController.prototype.renderAirports = function() {
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

    const civilColorHex = "#ffd54f"
    const milColorHex = "#ef5350"
    const civilIcon = createAirportIcon(civilColorHex, false)
    const milIcon = createAirportIcon(milColorHex, true)
    const civilColor = Cesium.Color.fromCssColorString(civilColorHex)
    const milColor = Cesium.Color.fromCssColorString(milColorHex)

    dataSource.entities.suspendEvents()
    for (const [icao, ap] of entries) {
      const isMil = ap.military
      const color = isMil ? milColor : civilColor

      const entity = dataSource.entities.add({
        id: `airport-${icao}`,
        position: Cesium.Cartesian3.fromDegrees(ap.lng, ap.lat, 10),
        billboard: {
          image: isMil ? milIcon : civilIcon,
          scale: 1,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.2, 1e7, 0.4),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: icao,
          font: LABEL_DEFAULTS.font,
          fillColor: color.withAlpha(0.95),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          pixelOffset: LABEL_DEFAULTS.pixelOffsetBelow(),
          scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
          translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._airportEntities.push(entity)
    }
    dataSource.entities.resumeEvents()
  }

  GlobeController.prototype._clearAirportEntities = function() {
    const ds = this._ds["airports"]
    if (ds) {
      ds.entities.suspendEvents()
      this._airportEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._airportEntities = []
  }

  GlobeController.prototype.showAirportDetail = function(icao) {
    const ap = this._getAirport(icao)
    if (!ap) return

    this.detailContentTarget.innerHTML = renderAirportDetailHtml(this, icao, ap)
    this.detailPanelTarget.style.display = ""

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ap.lng, ap.lat, 200000),
      duration: 1.5,
    })
  }

  GlobeController.prototype.getEventsDataSource = function() { return getDataSource(this.viewer, this._ds, "events") }

  GlobeController.prototype.toggleEarthquakes = function() {
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

  GlobeController.prototype.toggleNaturalEvents = function() {
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

  GlobeController.prototype._startEventsRefresh = function() {
    if (this._eventsInterval) clearInterval(this._eventsInterval)
    if (this.earthquakesVisible || this.naturalEventsVisible) {
      this._eventsInterval = setInterval(() => {
        if (this.earthquakesVisible) this.fetchEarthquakes()
        if (this.naturalEventsVisible) this.fetchNaturalEvents()
      }, 300000)
    }
  }

  GlobeController.prototype.fetchEarthquakes = async function() {
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

  GlobeController.prototype.renderEarthquakes = function() {
    const Cesium = window.Cesium
    this._clearEarthquakeEntities()
    const dataSource = this.getEventsDataSource()

    dataSource.entities.suspendEvents()
    this._earthquakeData.forEach(eq => {
      if (this.hasActiveFilter() && !this.pointPassesFilter(eq.lat, eq.lng)) return

      const mag = eq.mag || 0
      const t = Math.min(Math.max((mag - 2.5) / 5.5, 0), 1)
      const pixelSize = 6 + t * 14
      const pulseScale = 2 + t * 4

      let color
      if (mag < 3) color = cachedColor("#66bb6a")
      else if (mag < 4) color = cachedColor("#ffa726")
      else if (mag < 5) color = cachedColor("#ff7043")
      else if (mag < 6) color = cachedColor("#ef5350")
      else color = cachedColor("#d50000")

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
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._earthquakeEntities.push(ring)

      const entity = dataSource.entities.add({
        id: `eq-${eq.id}`,
        position: Cesium.Cartesian3.fromDegrees(eq.lng, eq.lat, 10),
        point: {
          pixelSize,
          color: color.withAlpha(0.85),
          outlineColor: color.withAlpha(0.4),
          outlineWidth: pulseScale,
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: `M${mag.toFixed(1)}`,
          font: LABEL_DEFAULTS.font,
          fillColor: Cesium.Color.WHITE.withAlpha(0.95),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: LABEL_DEFAULTS.pixelOffsetAbove(),
          scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
          translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
        },
      })
      this._earthquakeEntities.push(entity)
    })
    dataSource.entities.resumeEvents()
  }

  GlobeController.prototype._clearEarthquakeEntities = function() {
    const ds = this._ds["events"]
    if (ds) {
      ds.entities.suspendEvents()
      this._earthquakeEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._earthquakeEntities = []
  }

  GlobeController.prototype.showEarthquakeDetail = function(eq) {
    this.detailContentTarget.innerHTML = renderEarthquakeDetailHtml(this, eq)
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("earthquake", eq.lat, eq.lng)

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(eq.lng, eq.lat, 500000),
      duration: 1.5,
    })
  }

  GlobeController.prototype._mmiColors = {
    2: { color: "#acd8e9", label: "II - Weak" },
    3: { color: "#acd8e9", label: "III - Weak" },
    4: { color: "#83d0da", label: "IV - Light" },
    5: { color: "#7bc87f", label: "V - Moderate" },
    6: { color: "#f9f518", label: "VI - Strong" },
    7: { color: "#fab72a", label: "VII - Very Strong" },
    8: { color: "#f68528", label: "VIII - Severe" },
    9: { color: "#e9001a", label: "IX - Violent" },
    10: { color: "#c80000", label: "X - Extreme" },
  }

  GlobeController.prototype._mmiRadius = function(mag, depth, targetMmi) {
    const c0 = 2.085, c1 = 1.428, c2 = -1.402, c3 = 0.0, h = Math.max(depth, 5)
    const rhs = (targetMmi - c0 - c1 * mag) / c2
    const R = Math.exp(rhs)
    const dist = Math.sqrt(Math.max(R * R - h * h, 0))
    return dist > 0 && dist < 2000 ? dist : 0
  }

  GlobeController.prototype.toggleShakeMap = function(event) {
    const btn = event.currentTarget
    const lat = parseFloat(btn.dataset.eqLat)
    const lng = parseFloat(btn.dataset.eqLng)
    const mag = parseFloat(btn.dataset.eqMag)
    const depth = parseFloat(btn.dataset.eqDepth)
    const eqId = btn.dataset.eqId

    if (this._shakeMapEqId === eqId && this._shakeMapEntities?.length > 0) {
      this._clearShakeMap()
      btn.style.opacity = "1"
      const infraPanel = this.detailContentTarget.querySelector("[data-globe-shakemap-infra]")
      if (infraPanel) infraPanel.style.display = "none"
      return
    }

    this._clearShakeMap()
    this._shakeMapEqId = eqId
    btn.style.opacity = "0.6"
    this._renderShakeMap(lat, lng, mag, depth)
    this._fetchShakeMapInfra(lat, lng, mag, depth)
  }

  GlobeController.prototype._renderShakeMap = function(lat, lng, mag, depth) {
    const Cesium = window.Cesium
    const ds = this.getEventsDataSource()
    this._shakeMapEntities = []

    const maxMmi = Math.min(Math.round(1.5 * mag - 1), 10)
    const rings = []

    for (let mmi = maxMmi; mmi >= 2; mmi--) {
      const radiusKm = this._mmiRadius(mag, depth, mmi)
      if (radiusKm <= 0 || radiusKm > 1500) continue
      const info = this._mmiColors[mmi]
      if (!info) continue
      rings.push({ mmi, radiusKm, color: info.color, label: info.label })
    }

    rings.reverse().forEach((ring, idx) => {
      const cesiumColor = Cesium.Color.fromCssColorString(ring.color)
      const radiusM = ring.radiusKm * 1000

      const ellipse = ds.entities.add({
        id: `shake-fill-${ring.mmi}`,
        position: Cesium.Cartesian3.fromDegrees(lng, lat, 0),
        ellipse: {
          semiMajorAxis: radiusM,
          semiMinorAxis: radiusM,
          material: cesiumColor.withAlpha(0.08 + idx * 0.02),
          outline: true,
          outlineColor: cesiumColor.withAlpha(0.5),
          outlineWidth: ring.mmi >= 7 ? 2 : 1,
          height: 0,
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._shakeMapEntities.push(ellipse)

      const labelAngle = Math.PI / 4
      const labelLat = lat + (ring.radiusKm / 111) * Math.cos(labelAngle)
      const labelLng = lng + (ring.radiusKm / (111 * Math.cos(lat * Math.PI / 180))) * Math.sin(labelAngle)

      const label = ds.entities.add({
        id: `shake-lbl-${ring.mmi}`,
        position: Cesium.Cartesian3.fromDegrees(labelLng, labelLat, 10),
        label: {
          text: `MMI ${ring.mmi}\n${ring.radiusKm.toFixed(0)} km`,
          font: "10px JetBrains Mono, monospace",
          fillColor: cesiumColor,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 2,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          horizontalOrigin: Cesium.HorizontalOrigin.LEFT,
          pixelOffset: new Cesium.Cartesian2(4, 0),
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.0, 3e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(5e4, 1.0, 5e6, 0.0),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._shakeMapEntities.push(label)
    })

    this._requestRender()
  }

  GlobeController.prototype._fetchShakeMapInfra = async function(lat, lng, mag, depth) {
    const maxRadiusKm = this._mmiRadius(mag, depth, 4)
    if (maxRadiusKm <= 0) return

    const dlat = maxRadiusKm / 111
    const dlng = maxRadiusKm / (111 * Math.cos(lat * Math.PI / 180))
    const bounds = `north=${(lat + dlat).toFixed(4)}&south=${(lat - dlat).toFixed(4)}&east=${(lng + dlng).toFixed(4)}&west=${(lng - dlng).toFixed(4)}`

    const infraPanel = this.detailContentTarget.querySelector("[data-globe-shakemap-infra]")
    if (!infraPanel) return
    infraPanel.style.display = ""
    infraPanel.innerHTML = '<div style="font:400 10px var(--gt-mono);color:#888;padding:8px 0;">Loading nearby infrastructure...</div>'

    try {
      const [plantsResp, cablesResp] = await Promise.all([
        fetch(`/api/power_plants?${bounds}&limit=50`),
        fetch(`/api/submarine_cables?${bounds}`),
      ])

      let html = '<div class="shakemap-infra-title"><i class="fa-solid fa-building"></i> INFRASTRUCTURE IN SHAKE ZONE</div>'
      let hasContent = false

      if (plantsResp.ok) {
        const plants = await plantsResp.json()
        const plantList = Array.isArray(plants) ? plants : (plants.power_plants || [])
        if (plantList.length > 0) {
          hasContent = true
          const nuclear = plantList.filter(p => p.primary_fuel === "Nuclear" || p.fuel === "Nuclear")
          html += `<div class="shakemap-infra-row">`
          html += `<span class="shakemap-infra-count">${plantList.length}</span> power plant${plantList.length > 1 ? "s" : ""}`
          if (nuclear.length > 0) html += ` <span class="shakemap-infra-warn">(${nuclear.length} NUCLEAR)</span>`
          html += `</div>`
          plantList.slice(0, 5).forEach(p => {
            const fuel = p.primary_fuel || p.fuel || "Unknown"
            const cap = p.capacity_mw || p.capacity || 0
            const isNuclear = fuel === "Nuclear"
            html += `<div class="shakemap-infra-item${isNuclear ? " shakemap-infra-item--nuclear" : ""}">`
            html += `<span class="shakemap-infra-fuel">${this._fuelEmoji(fuel)}</span>`
            html += `<span class="shakemap-infra-name">${this._escapeHtml(p.name || "Unknown")}</span>`
            html += `<span class="shakemap-infra-cap">${cap > 0 ? cap + " MW" : ""}</span>`
            html += `</div>`
          })
          if (plantList.length > 5) html += `<div class="shakemap-infra-more">+${plantList.length - 5} more</div>`
        }
      }

      if (cablesResp.ok) {
        const cablesData = await cablesResp.json()
        const cables = Array.isArray(cablesData) ? cablesData : (cablesData.cables || [])
        if (cables.length > 0) {
          hasContent = true
          html += `<div class="shakemap-infra-row" style="margin-top:8px;">`
          html += `<span class="shakemap-infra-count">${cables.length}</span> submarine cable${cables.length > 1 ? "s" : ""}`
          html += `</div>`
          cables.slice(0, 5).forEach(c => {
            html += `<div class="shakemap-infra-item">`
            html += `<span class="shakemap-infra-fuel" style="color:#00bcd4;">⚡</span>`
            html += `<span class="shakemap-infra-name">${this._escapeHtml(c.name || "Unknown cable")}</span>`
            html += `</div>`
          })
          if (cables.length > 5) html += `<div class="shakemap-infra-more">+${cables.length - 5} more</div>`
        }
      }

      infraPanel.innerHTML = hasContent ? html : ""
      if (!hasContent) infraPanel.style.display = "none"
    } catch (e) {
      console.warn("ShakeMap infra fetch failed:", e)
      infraPanel.style.display = "none"
    }
  }

  GlobeController.prototype._fuelEmoji = function(fuel) {
    const map = {
      Nuclear: "☢️", Coal: "🪨", Gas: "🔥", Oil: "🛢️", Hydro: "💧",
      Solar: "☀️", Wind: "💨", Biomass: "🌿", Geothermal: "♨️",
    }
    return map[fuel] || "⚡"
  }

  GlobeController.prototype._clearShakeMap = function() {
    if (!this._shakeMapEntities?.length) return
    const ds = this._ds["events"]
    if (ds) this._shakeMapEntities.forEach(e => ds.entities.remove(e))
    this._shakeMapEntities = []
    this._shakeMapEqId = null
    this._requestRender()
  }

  Object.defineProperty(GlobeController.prototype, "eonetCategoryIcons", {
    configurable: true,
    get: function() {
      return {
        wildfires: { icon: "fire", color: "#ff5722" },
        volcanoes: { icon: "volcano", color: "#e53935" },
        severeStorms: { icon: "hurricane", color: "#5c6bc0" },
        seaLakeIce: { icon: "snowflake", color: "#4fc3f7" },
        floods: { icon: "water", color: "#29b6f6" },
        drought: { icon: "sun", color: "#ffb300" },
        dustHaze: { icon: "smog", color: "#8d6e63" },
        earthquakes: { icon: "house-crack", color: "#ff7043" },
        landslides: { icon: "hill-rockslide", color: "#795548" },
        snow: { icon: "snowflake", color: "#e0e0e0" },
        tempExtremes: { icon: "temperature-high", color: "#ff8f00" },
        waterColor: { icon: "droplet", color: "#26c6da" },
        manmade: { icon: "industry", color: "#78909c" },
      }
    },
  })

  GlobeController.prototype.fetchNaturalEvents = async function() {
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

  GlobeController.prototype.renderNaturalEvents = function() {
    const Cesium = window.Cesium
    this._clearNaturalEventEntities()
    const dataSource = this.getEventsDataSource()

    dataSource.entities.suspendEvents()
    this._naturalEventData.forEach(ev => {
      if (this.hasActiveFilter() && !this.pointPassesFilter(ev.lat, ev.lng)) return

      const catInfo = this.eonetCategoryIcons[ev.categoryId] || { icon: "circle-exclamation", color: "#78909c" }
      const color = Cesium.Color.fromCssColorString(catInfo.color)

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
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._naturalEventEntities.push(ring)

      const entity = dataSource.entities.add({
        id: `eonet-${ev.id}`,
        position: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 10),
        point: {
          pixelSize: 8,
          color: color.withAlpha(0.9),
          outlineColor: color.withAlpha(0.35),
          outlineWidth: 3,
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: ev.title.length > 30 ? ev.title.substring(0, 28) + "…" : ev.title,
          font: LABEL_DEFAULTS.font,
          fillColor: Cesium.Color.WHITE.withAlpha(0.9),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: LABEL_DEFAULTS.pixelOffsetAbove(),
          scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
          translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
        },
      })
      this._naturalEventEntities.push(entity)
    })
    dataSource.entities.resumeEvents()
  }

  GlobeController.prototype._clearNaturalEventEntities = function() {
    const ds = this._ds["events"]
    if (ds) {
      ds.entities.suspendEvents()
      this._naturalEventEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._naturalEventEntities = []
  }

  GlobeController.prototype.showNaturalEventDetail = function(ev) {
    const catInfo = this.eonetCategoryIcons[ev.categoryId] || { icon: "circle-exclamation", color: "#78909c" }
    this.detailContentTarget.innerHTML = renderNaturalEventDetailHtml(this, ev, catInfo)
    this.detailPanelTarget.style.display = ""

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 500000),
      duration: 1.5,
    })
  }
}
