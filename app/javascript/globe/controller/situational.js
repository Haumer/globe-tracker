import { getDataSource, createAirportIcon, cachedColor, LABEL_DEFAULTS } from "../utils"

export function applySituationalMethods(GlobeController) {
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
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: OurAirports / FAA</div>
    `
    this.detailPanelTarget.style.display = ""

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(ap.lng, ap.lat, 200000),
      duration: 1.5,
    })
  }

  // ── Events (Earthquakes + NASA EONET) ────────────────────

  GlobeController.prototype.getEventsDataSource = function() { return getDataSource(this.viewer, this._ds, "events") }

  GlobeController.prototype.getWebcamsDataSource = function() {
    const dataSource = getDataSource(this.viewer, this._ds, "webcams")
    dataSource.show = this.camerasVisible
    return dataSource
  }

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
      }, 300000) // refresh every 5 min
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
      // Size and color by magnitude
      const t = Math.min(Math.max((mag - 2.5) / 5.5, 0), 1) // 2.5–8.0 range
      const pixelSize = 6 + t * 14
      const pulseScale = 2 + t * 4

      let color
      if (mag < 3) color = cachedColor("#66bb6a")
      else if (mag < 4) color = cachedColor("#ffa726")
      else if (mag < 5) color = cachedColor("#ff7043")
      else if (mag < 6) color = cachedColor("#ef5350")
      else color = cachedColor("#d50000")

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
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._earthquakeEntities.push(ring)

      // Center point
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
    const date = new Date(eq.time)
    const ago = this._timeAgo(date)
    const alertBadge = eq.alert ? `<span class="event-alert event-alert-${eq.alert}">${eq.alert.toUpperCase()}</span>` : ""
    const tsunamiBadge = eq.tsunami ? `<span class="event-alert event-alert-tsunami">TSUNAMI</span>` : ""

    const shakeMapBtn = eq.mag >= 4.0
      ? `<button class="detail-track-btn" style="background:rgba(255,112,67,0.15);border-color:rgba(255,112,67,0.3);color:#ff7043;" data-action="click->globe#toggleShakeMap" data-eq-lat="${eq.lat}" data-eq-lng="${eq.lng}" data-eq-mag="${eq.mag}" data-eq-depth="${eq.depth}" data-eq-id="${eq.id}">
          <i class="fa-solid fa-bullseye" style="margin-right:4px;"></i>ShakeMap Intensity
        </button>`
      : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign">M${eq.mag.toFixed(1)} Earthquake</div>
      <div class="detail-country">${this._escapeHtml(eq.title)}</div>
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
      ${shakeMapBtn}
      ${typeof eq.url === "string" && /^https?:\/\//i.test(eq.url) ? `<a href="${this._safeUrl(eq.url)}" target="_blank" rel="noopener" class="detail-track-btn">View on USGS</a>` : ""}
      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${eq.lat}" data-lng="${eq.lng}">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
      </button>
      ${this._connectionsPlaceholder()}
      <div class="shakemap-infra" data-globe-shakemap-infra style="display:none;"></div>
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: USGS Earthquake Hazards Program</div>
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("earthquake", eq.lat, eq.lng)

    // Fly to earthquake
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(eq.lng, eq.lat, 500000),
      duration: 1.5,
    })
  }

  // ── ShakeMap Intensity Visualization ──

  // MMI color scale (Modified Mercalli Intensity)
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

  // Wald et al. (1999) IPE: compute distance (km) at which MMI drops to a given level
  // MMI = 3.66 + 1.08*M - 1.60*log10(R) - 0.0048*R
  // Solved iteratively for R given MMI and M
  GlobeController.prototype._mmiRadius = function(mag, depth, targetMmi) {
    // Use simplified Atkinson & Wald (2007) for shallow crustal events
    // MMI = c0 + c1*M + c2*ln(R) + c3*R  where R = sqrt(d^2 + h^2)
    // Coefficients for active tectonic regions:
    const c0 = 2.085, c1 = 1.428, c2 = -1.402, c3 = 0.0, h = Math.max(depth, 5)
    // Solve: targetMmi = c0 + c1*M + c2*ln(sqrt(dist^2 + h^2))
    // c2*ln(sqrt(dist^2+h^2)) = targetMmi - c0 - c1*M
    // ln(sqrt(dist^2+h^2)) = (targetMmi - c0 - c1*M) / c2
    // sqrt(dist^2+h^2) = exp((targetMmi - c0 - c1*M) / c2)
    const rhs = (targetMmi - c0 - c1 * mag) / c2
    const R = Math.exp(rhs) // hypocentral distance in km
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

    // Toggle off if same earthquake
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

    // Compute rings from highest intensity outward
    const maxMmi = Math.min(Math.round(1.5 * mag - 1), 10)
    const rings = []

    for (let mmi = maxMmi; mmi >= 2; mmi--) {
      const radiusKm = this._mmiRadius(mag, depth, mmi)
      if (radiusKm <= 0 || radiusKm > 1500) continue
      const info = this._mmiColors[mmi]
      if (!info) continue
      rings.push({ mmi, radiusKm, color: info.color, label: info.label })
    }

    // Render from outermost to innermost (so inner rings draw on top)
    rings.reverse().forEach((ring, idx) => {
      const cesiumColor = Cesium.Color.fromCssColorString(ring.color)
      const radiusM = ring.radiusKm * 1000

      // Filled ellipse
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

      // Label at edge of ring
      const labelAngle = Math.PI / 4 // 45° northeast
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
    const maxRadiusKm = this._mmiRadius(mag, depth, 4) // MMI IV = felt
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

  // ── NASA EONET Natural Events ──

  Object.defineProperty(GlobeController.prototype, "eonetCategoryIcons", {
    configurable: true,
    get: function() {
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
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._naturalEventEntities.push(ring)

      // Center point
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
    const date = ev.date ? new Date(ev.date) : null
    const ago = date ? this._timeAgo(date) : "—"
    const magStr = ev.magnitudeValue ? `${ev.magnitudeValue} ${ev.magnitudeUnit || ""}` : "—"
    const sourceLinks = (ev.sources || [])
      .filter(s => typeof s.url === "string" && /^https?:\/\//i.test(s.url))
      .map(s => `<a href="${this._safeUrl(s.url)}" target="_blank" rel="noopener" class="event-source-link">${this._escapeHtml(s.id)}</a>`)
      .join(" ")

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign"><i class="fa-solid fa-${catInfo.icon}" style="color: ${catInfo.color};"></i> ${this._escapeHtml(ev.categoryTitle)}</div>
      <div class="detail-country">${this._escapeHtml(ev.title)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Category</span>
          <span class="detail-value">${this._escapeHtml(ev.categoryTitle)}</span>
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
      ${typeof ev.link === "string" && /^https?:\/\//i.test(ev.link) ? `<a href="${this._safeUrl(ev.link)}" target="_blank" rel="noopener" class="detail-track-btn">View on NASA EONET</a>` : ""}
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

  GlobeController.prototype._extractWindyUrl = function(field, prop = "link") {
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

  GlobeController.prototype.toggleCameras = function() {
    this.camerasVisible = this.hasCamerasToggleTarget && this.camerasToggleTarget.checked
    if (this.camerasVisible) {
      this.getWebcamsDataSource().show = true
      this.fetchWebcams()
      this._showRightPanel("cameras")
      // Re-fetch when camera moves significantly
      if (!this._webcamMoveHandler) {
        this._webcamMoveHandler = () => {
          if (this.camerasVisible) this._maybeRefetchWebcams()
        }
        this.viewer.camera.moveEnd.addEventListener(this._webcamMoveHandler)
      }
    } else {
      this._webcamFetchToken += 1
      this._clearWebcamEntities()
      this._webcamData = []
      const dataSource = this._ds["webcams"]
      if (dataSource) dataSource.show = false
      if (this._syncRightPanels) this._syncRightPanels()
    }
    this._updateStats()
    this._requestRender()
    this._savePrefs()
  }

  GlobeController.prototype._maybeRefetchWebcams = function() {
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

  GlobeController.prototype._getViewCenter = function() {
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

  GlobeController.prototype._getViewportBbox = function() {
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

    // Try globe pick first (works when globe is visible)
    if (this.viewer.scene.globe.show) {
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
    }

    // Fallback: estimate bbox from camera position + height (works with Google tiles)
    if (hits < 2) {
      const carto = this.viewer.camera.positionCartographic
      const lat = Cesium.Math.toDegrees(carto.latitude)
      const lng = Cesium.Math.toDegrees(carto.longitude)
      const heightKm = carto.height / 1000
      const spanDeg = Math.min(Math.max(heightKm / 111, 0.1), 30)
      return {
        north: lat + spanDeg,
        south: lat - spanDeg,
        east: lng + spanDeg / Math.max(Math.cos(lat * Math.PI / 180), 0.01),
        west: lng - spanDeg / Math.max(Math.cos(lat * Math.PI / 180), 0.01),
      }
    }

    return { north: maxLat, south: minLat, east: maxLng, west: minLng }
  }

  GlobeController.prototype._buildWebcamFetchPlan = function(center) {
    const viewport = this._getViewportBbox()
    const filterBounds = this.hasActiveFilter() ? this.getFilterBounds() : null

    let north, south, east, west
    if (viewport) {
      north = viewport.north; south = viewport.south
      east = viewport.east; west = viewport.west
    } else {
      const spanDeg = Math.min(Math.max(center.height / 111000, 0.5), 30)
      north = center.lat + spanDeg; south = center.lat - spanDeg
      east = center.lng + spanDeg; west = center.lng - spanDeg
    }

    // Clamp to filter bounds so we don't fetch outside selected countries
    if (filterBounds) {
      north = Math.min(north, filterBounds.lamax + 0.15)
      south = Math.max(south, filterBounds.lamin - 0.15)
      east = Math.min(east, filterBounds.lomax + 0.15)
      west = Math.max(west, filterBounds.lomin - 0.15)
    }

    const latPad = Math.max((north - south) * 0.15, 0.25)
    const lngPad = Math.max((east - west) * 0.15, 0.25)

    return {
      query: [
        `north=${Math.min(north + latPad, 85).toFixed(4)}`,
        `south=${Math.max(south - latPad, -85).toFixed(4)}`,
        `east=${Math.min(east + lngPad, 180).toFixed(4)}`,
        `west=${Math.max(west - lngPad, -180).toFixed(4)}`,
      ].join("&"),
      limit: center.height > 1500000 ? 150 : 100,
    }
  }

  GlobeController.prototype.fetchWebcams = async function() {
    if (!this.camerasVisible) return
    const center = this._getViewCenter()
    if (!center) return
    const fetchId = ++this._webcamFetchToken
    const plan = this._buildWebcamFetchPlan(center)
    const url = `/api/webcams?${plan.query}&limit=${plan.limit}`

    this._toast("Loading cameras...")

    try {
      const resp = await fetch(url)
      if (fetchId !== this._webcamFetchToken) return
      if (resp.ok) {
        const data = await resp.json()
        if (fetchId !== this._webcamFetchToken) return
        const cams = data.webcams || []

        // Replace data with new viewport's cameras (don't keep stale ones from old viewport)
        this._webcamData = cams.map(w => this._normalizeWebcam(w)).filter(w =>
          w.lat != null && w.lng != null && Number.isFinite(w.lat) && Number.isFinite(w.lng)
        )
        this.renderWebcams()
        this._updateStats()
        if (this._syncRightPanels) this._syncRightPanels()

        // If the server says cameras are stale, a background job is refreshing.
        // Re-fetch after delays to pick up newly fetched cameras.
        if (data.stale && fetchId === this._webcamFetchToken) {
          const retryDelays = [8000, 20000]
          retryDelays.forEach(delay => {
            setTimeout(() => {
              if (fetchId === this._webcamFetchToken && this.camerasVisible) {
                this._refetchWebcamsQuiet(url, fetchId)
              }
            }, delay)
          })
        }
      }
    } catch (e) { console.warn("Webcam fetch failed:", e) }

    if (fetchId === this._webcamFetchToken) {
      this._webcamLastFetchCenter = center
      if (this._syncRightPanels) this._syncRightPanels()
      this._toastHide()
    }
  }

  // Silent re-fetch after background job populates fresh cameras
  GlobeController.prototype._refetchWebcamsQuiet = async function(url, fetchId) {
    try {
      const resp = await fetch(url)
      if (fetchId !== this._webcamFetchToken || !resp.ok) return
      const data = await resp.json()
      if (fetchId !== this._webcamFetchToken) return
      const cams = data.webcams || []
      if (cams.length > 0) {
        // Merge new cameras into existing set (background job may have found more)
        const newNormalized = cams.map(w => this._normalizeWebcam(w)).filter(w =>
          w.lat != null && w.lng != null && Number.isFinite(w.lat) && Number.isFinite(w.lng)
        )
        const existingIds = new Set(this._webcamData.map(w => w.id))
        const added = newNormalized.filter(w => !existingIds.has(w.id))
        if (added.length > 0) {
          this._webcamData = [...this._webcamData, ...added]
        }
        this.renderWebcams()
        this._updateStats()
        if (this._syncRightPanels) this._syncRightPanels()
      }
    } catch (e) { /* silent */ }
  }

  GlobeController.prototype._normalizeWebcam = function(w) {
    return {
      id: w.webcamId || w.id,
      title: w.title,
      source: w.source || "windy",
      live: w.live || false,
      lat: w.location?.latitude,
      lng: w.location?.longitude,
      city: w.location?.city,
      region: w.location?.region,
      country: w.location?.country,
      thumbnail: w.images?.current?.preview || w.images?.daylight?.preview,
      thumbnailIcon: w.images?.current?.icon || w.images?.daylight?.icon,
      playerLink: this._extractWindyUrl(w.player?.live) || this._extractWindyUrl(w.player?.day) || (typeof w.url === "string" ? w.url : null),
      videoId: w.videoId || null,
      channelTitle: w.channelTitle || null,
      lastUpdated: w.lastUpdatedOn,
      viewCount: w.viewCount,
    }
  }

  GlobeController.prototype.renderWebcams = function() {
    const Cesium = window.Cesium
    this._clearWebcamEntities()
    const dataSource = this.getWebcamsDataSource()
    dataSource.show = this.camerasVisible
    if (!this.camerasVisible) {
      this._requestRender()
      return
    }
    this._webcamEntityMap.clear()
    const visibleCams = this._webcamData.filter(w => !this.hasActiveFilter() || this.pointPassesFilter(w.lat, w.lng))

    // Default height offset above ground (meters)
    const CAM_HEIGHT_OFFSET = 25

    dataSource.entities.suspendEvents()
    visibleCams.forEach(w => {
      const realtime = w.source === "youtube" || w.source === "nycdot"
      const icon = realtime
        ? (this._webcamIconRT || (this._webcamIconRT = this._makeWebcamIcon("#ff4444")))
        : w.live
          ? (this._webcamIconLive || (this._webcamIconLive = this._makeWebcamIcon("#4caf50")))
          : (this._webcamIcon || (this._webcamIcon = this._makeWebcamIcon("#29b6f6")))
      const labelPrefix = w.source === "nycdot" ? "🚦 " : w.source === "youtube" ? "▶ " : ""
      const entity = dataSource.entities.add({
        id: `cam-${w.id}`,
        position: Cesium.Cartesian3.fromDegrees(w.lng, w.lat, CAM_HEIGHT_OFFSET),
        properties: {
          webcamId: w.id,
        },
        billboard: {
          image: icon,
          scale: 0.7,
          scaleByDistance: new Cesium.NearFarScalar(500, 1.2, 5e6, 0.4),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          heightReference: Cesium.HeightReference.NONE,
        },
        label: {
          text: labelPrefix + (w.title.length > 25 ? w.title.substring(0, 23) + "…" : w.title),
          font: "12px JetBrains Mono, sans-serif",
          fillColor: Cesium.Color.WHITE.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.6),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, -14),
          scaleByDistance: new Cesium.NearFarScalar(500, 1, 3e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(500, 1, 1.5e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          heightReference: Cesium.HeightReference.NONE,
        },
      })
      this._webcamEntities.push(entity)
      this._webcamEntityMap.set(entity.id, w)
    })
    dataSource.entities.resumeEvents()

    this._requestRender()
    this._renderCamFeed()

    // Sample actual ground height from terrain/3D tiles and reposition cameras
    if (visibleCams.length > 0 && this.viewer.scene.sampleHeightMostDetailed) {
      const cartographics = visibleCams.map(w =>
        Cesium.Cartographic.fromDegrees(w.lng, w.lat)
      )
      this.viewer.scene.sampleHeightMostDetailed(cartographics).then(updated => {
        updated.forEach((carto, i) => {
          const entity = this._webcamEntities[i]
          if (!entity) return
          const groundHeight = carto.height || 0
          entity.position = Cesium.Cartesian3.fromDegrees(
            Cesium.Math.toDegrees(carto.longitude),
            Cesium.Math.toDegrees(carto.latitude),
            groundHeight + CAM_HEIGHT_OFFSET
          )
        })
        this._requestRender()
      }).catch(() => {})
    }
  }

  GlobeController.prototype._renderCamFeed = function() {
    if (!this.hasCamFeedListTarget) return
    const search = this.hasCamFeedSearchTarget ? this.camFeedSearchTarget.value.toLowerCase().trim() : ""
    const cams = this._webcamData.filter(w => {
      if (search && !(w.title || "").toLowerCase().includes(search) &&
          !(w.city || "").toLowerCase().includes(search) &&
          !(w.country || "").toLowerCase().includes(search)) return false
      return true
    })

    if (this.hasCamFeedCountTarget) {
      this.camFeedCountTarget.textContent = `${cams.length} camera${cams.length !== 1 ? "s" : ""}`
    }

    if (cams.length === 0) {
      this.camFeedListTarget.innerHTML = '<div style="padding:24px 14px;text-align:center;color:var(--gt-text-dim);font:500 11px var(--gt-mono);">No cameras found</div>'
      return
    }

    const html = cams.map((cam, idx) => {
      const sourceColors = { youtube: "#ff4444", nycdot: "#ff6d00", windy: "#29b6f6" }
      const barColor = sourceColors[cam.source] || "#29b6f6"
      const sourceLabel = { windy: "Windy", nycdot: "NYC DOT", youtube: "YouTube" }[cam.source] || cam.source
      const location = [cam.city, cam.country].filter(Boolean).join(", ")
      const isRealtime = cam.source === "youtube" || cam.source === "nycdot"
      const badgeBg = isRealtime ? "#ff4444" : cam.live ? "#4caf50" : "#666"
      const badgeText = isRealtime ? "LIVE" : cam.live ? "PERIODIC" : "TIMELAPSE"
      const title = this._escapeHtml((cam.title || "").length > 40 ? cam.title.substring(0, 38) + "…" : (cam.title || "Untitled"))
      const thumbHtml = cam.thumbnailIcon
        ? `<img class="cf-card-thumb" src="${cam.thumbnailIcon}" alt="" loading="lazy">`
        : ""

      return `<div class="cf-card" data-action="click->globe#focusCamFeedItem" data-cam-idx="${idx}">
        <div class="cf-card-bar" style="background:${barColor};"></div>
        <div class="cf-card-body">
          <div class="cf-card-title">${title}</div>
          <div class="cf-card-meta">
            <span class="cf-card-source">${sourceLabel}</span>
            ${location ? `<span style="color:var(--gt-text-dim);font:500 9px var(--gt-mono);">&middot;</span><span class="cf-card-location">${this._escapeHtml(location)}</span>` : ""}
            <span class="cf-card-badge" style="background:${badgeBg};color:#fff;">${badgeText}</span>
          </div>
        </div>
        ${thumbHtml}
      </div>`
    }).join("")

    this.camFeedListTarget.innerHTML = html
  }

  GlobeController.prototype.filterCamFeed = function() {
    this._renderCamFeed()
  }

  GlobeController.prototype.closeCamFeed = function() {
    if (this._syncRightPanels) this._syncRightPanels()
  }

  // ── Unified Right Panel ─────────────────────────────────

  GlobeController.prototype._syncRightPanels = function() {
    // Determine which tabs should be visible based on active layers/data
    const hasEntities = this.flightsVisible || this.shipsVisible || this.satellitesVisible
    const hasNews = this.newsVisible && this._newsData?.length > 0
    const hasThreats = !!this._threatsActive
    const hasCameras = this.camerasVisible && this._webcamData?.length > 0
    const hasAlerts = this.signedInValue && this._alertData?.length > 0
    const hasInsights = this._insightsData?.length > 0
    const hasSituations = this._conflictPulseZones?.length > 0

    // Show/hide tab buttons
    if (this.hasRpTabEntitiesTarget) this.rpTabEntitiesTarget.style.display = hasEntities ? "" : "none"
    if (this.hasRpTabNewsTarget) this.rpTabNewsTarget.style.display = hasNews ? "" : "none"
    if (this.hasRpTabThreatsTarget) this.rpTabThreatsTarget.style.display = hasThreats ? "" : "none"
    if (this.hasRpTabSituationsTarget) this.rpTabSituationsTarget.style.display = hasSituations ? "" : "none"
    if (this.hasRpTabCamerasTarget) this.rpTabCamerasTarget.style.display = hasCameras ? "" : "none"
    if (this.hasRpTabAlertsTarget) this.rpTabAlertsTarget.style.display = hasAlerts ? "" : "none"
    if (this.hasRpTabInsightsTarget) this.rpTabInsightsTarget.style.display = hasInsights ? "" : "none"

    // Respect user's close action — don't auto-show
    if (this._rightPanelUserClosed) {
      this._repositionDetailStack(12)
      return
    }

    const anyTabVisible = hasEntities || hasNews || hasThreats || hasSituations || hasCameras || hasAlerts || hasInsights
    if (!anyTabVisible) {
      if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = "none"
      this._repositionDetailStack(12)
      return
    }

    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = ""

    // If current active tab is now hidden, switch to first visible tab
    const activePane = this.hasRightPanelTarget && this.rightPanelTarget.querySelector(".rp-pane--active")
    const activePaneKey = activePane?.dataset.rpPane
    const activeTabHidden = (activePaneKey === "entities" && !hasEntities) ||
                            (activePaneKey === "news" && !hasNews) ||
                            (activePaneKey === "threats" && !hasThreats) ||
                            (activePaneKey === "situations" && !hasSituations) ||
                            (activePaneKey === "cameras" && !hasCameras) ||
                            (activePaneKey === "alerts" && !hasAlerts) ||
                            (activePaneKey === "insights" && !hasInsights)

    if (activeTabHidden || !activePaneKey) {
      const firstVisible = hasSituations ? "situations" : hasEntities ? "entities" : hasNews ? "news" : hasInsights ? "insights" : hasThreats ? "threats" : hasCameras ? "cameras" : "alerts"
      this._activateRightTab(firstVisible)
    }

    this._repositionDetailStack(372)
  }

  GlobeController.prototype._repositionDetailStack = function(panelWidth) {
    if (this._isMobile && this._isMobile()) return
    const detailRight = panelWidth > 12 ? panelWidth + 12 : 12
    const detailStack = document.getElementById("detail-stack")
    if (detailStack) detailStack.style.right = `${detailRight}px`
  }

  GlobeController.prototype.switchRightTab = function(event) {
    const tab = event.currentTarget.dataset.rpTab
    this._activateRightTab(tab)
  }

  GlobeController.prototype._activateRightTab = function(tabKey) {
    if (!this.hasRightPanelTarget) return
    // Update tab buttons
    this.rightPanelTarget.querySelectorAll(".rp-tab").forEach(t => t.classList.remove("active"))
    const btn = this.rightPanelTarget.querySelector(`.rp-tab[data-rp-tab="${tabKey}"]`)
    if (btn) btn.classList.add("active")
    // Update panes
    this.rightPanelTarget.querySelectorAll(".rp-pane").forEach(p => p.classList.remove("rp-pane--active"))
    const pane = this.rightPanelTarget.querySelector(`.rp-pane[data-rp-pane="${tabKey}"]`)
    if (pane) pane.classList.add("rp-pane--active")
  }

  GlobeController.prototype._showRightPanel = function(tabKey) {
    this._rightPanelUserClosed = false
    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = ""
    this._activateRightTab(tabKey)
    this._syncRightPanels()
    this._syncPanelToggle(true)
  }

  GlobeController.prototype.closeRightPanel = function() {
    this._rightPanelUserClosed = true
    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = "none"
    this._repositionDetailStack(12)
    this._syncPanelToggle(false)
    this._savePrefs()
  }

  GlobeController.prototype._syncPanelToggle = function(active) {
    const toggle = this.element?.querySelector(".stat-panel-toggle")
    if (toggle) toggle.classList.toggle("active", active)
  }

  GlobeController.prototype.focusCamFeedItem = function(event) {
    const idx = parseInt(event.currentTarget.dataset.camIdx)
    const cam = this._webcamData[idx]
    if (!cam) return
    this.showWebcamDetail(cam)
  }

  GlobeController.prototype._clearWebcamEntities = function() {
    const ds = this._ds["webcams"]
    if (ds) {
      ds.entities.suspendEvents()
      this._webcamEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._webcamEntities = []
    this._webcamEntityMap.clear()
    this._requestRender()
  }



  GlobeController.prototype.showWebcamDetail = function(cam) {
    // Stop any existing auto-refresh and clean up YouTube error listener
    if (this._webcamRefreshInterval) { clearInterval(this._webcamRefreshInterval); this._webcamRefreshInterval = null }
    if (this._ytMessageCleanup) { this._ytMessageCleanup(); this._ytMessageCleanup = null }

    const updated = cam.lastUpdated ? this._timeAgo(new Date(cam.lastUpdated)) : "—"
    const location = [cam.city, cam.region, cam.country].filter(Boolean).join(", ")
    const sourceLabel = { windy: "Windy", nycdot: "NYC DOT", youtube: "YouTube Live" }[cam.source] || cam.source
    const isRealtime = cam.source === "youtube" || cam.source === "nycdot"
    const liveBadge = isRealtime
      ? '<span style="background:#ff4444;color:#fff;font:700 8px var(--gt-mono);padding:1px 5px;border-radius:2px;letter-spacing:1px;margin-left:6px;">LIVE</span>'
      : cam.live
        ? '<span style="background:#4caf50;color:#fff;font:700 8px var(--gt-mono);padding:1px 5px;border-radius:2px;letter-spacing:1px;margin-left:6px;">PERIODIC</span>'
        : '<span style="background:#666;color:#ccc;font:700 8px var(--gt-mono);padding:1px 5px;border-radius:2px;letter-spacing:1px;margin-left:6px;">TIMELAPSE</span>'

    // For DOT cameras, add cache-busting timestamp for auto-refresh
    const rawThumbUrl = cam.thumbnail ? `${cam.thumbnail}${cam.source === "nycdot" ? "?t=" + Date.now() : ""}` : null
    const thumbUrl = rawThumbUrl && /^https?:\/\//i.test(rawThumbUrl) ? rawThumbUrl : null

    const rawWatchUrl = cam.source === "youtube" && cam.videoId
      ? `https://www.youtube.com/watch?v=${encodeURIComponent(cam.videoId)}`
      : cam.source === "nycdot"
        ? `https://webcams.nyctmc.org/map`
        : (typeof cam.playerLink === "string" && /^https:\/\//i.test(cam.playerLink) ? cam.playerLink : `https://www.windy.com/webcams/${encodeURIComponent(cam.id)}`)
    const watchUrl = this._safeUrl(rawWatchUrl)

    let thumbHtml
    if (cam.source === "youtube" && cam.videoId) {
      const safeVideoId = encodeURIComponent(cam.videoId)
      const ytThumb = (cam.thumbnail && /^https?:\/\//i.test(cam.thumbnail)) ? cam.thumbnail : `https://img.youtube.com/vi/${safeVideoId}/hqdefault.jpg`
      thumbHtml = `<div class="webcam-thumb" style="position:relative;">
        <iframe id="webcam-detail-iframe" src="https://www.youtube.com/embed/${safeVideoId}?autoplay=1&mute=1&enablejsapi=1&origin=${encodeURIComponent(window.location.origin)}" style="width:100%;aspect-ratio:16/9;border:none;border-radius:4px;" allow="autoplay; encrypted-media" allowfullscreen></iframe>
        <div id="webcam-yt-fallback" style="display:none;position:relative;">
          <img src="${ytThumb}" alt="${this._escapeHtml(cam.title)}" style="width:100%;border-radius:4px;">
          <span style="position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);background:rgba(0,0,0,0.7);color:#ff6b6b;font:500 11px var(--gt-mono);padding:6px 12px;border-radius:4px;">Stream unavailable</span>
        </div>
      </div>`
      // Listen for YouTube player errors via postMessage (enablejsapi=1 makes YT send error events)
      const showFallback = () => {
        const iframe = document.getElementById("webcam-detail-iframe")
        const fallback = document.getElementById("webcam-yt-fallback")
        if (iframe) iframe.style.display = "none"
        if (fallback) fallback.style.display = "block"
      }
      const onYtMessage = (e) => {
        if (typeof e.data !== "string") return
        try {
          const msg = JSON.parse(e.data)
          // YT sends {event:"onError",info:<code>} for unavailable/removed videos
          if (msg.event === "onError") { showFallback(); window.removeEventListener("message", onYtMessage) }
        } catch { /* not a YT message */ }
      }
      window.addEventListener("message", onYtMessage)
      // Also send "listening" command after iframe loads so YT starts posting events
      setTimeout(() => {
        const iframe = document.getElementById("webcam-detail-iframe")
        if (iframe?.contentWindow) {
          iframe.contentWindow.postMessage(JSON.stringify({ event: "listening", id: 1 }), "https://www.youtube.com")
        }
      }, 1500)
      this._ytMessageCleanup = () => window.removeEventListener("message", onYtMessage)
    } else if (thumbUrl) {
      // Show preview image — auto-refreshes for live cameras
      thumbHtml = `<div class="webcam-thumb" style="position:relative;">
        <img id="webcam-detail-img" src="${thumbUrl}${thumbUrl.includes('?') ? '&' : '?'}t=${Date.now()}" alt="${this._escapeHtml(cam.title)}" style="width:100%;border-radius:4px;transition:opacity 0.3s;">
        <span style="position:absolute;top:6px;left:6px;background:rgba(0,0,0,0.6);color:#ff4444;font:700 9px var(--gt-mono);padding:2px 6px;border-radius:3px;letter-spacing:0.5px;">● LIVE</span>
      </div>`
    } else {
      thumbHtml = ""
    }

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign"><i class="fa-solid fa-video" style="color: ${cam.live ? '#4caf50' : '#29b6f6'};"></i> ${sourceLabel}${liveBadge}</div>
      <div class="detail-country">${this._escapeHtml(cam.title)}</div>
      ${thumbHtml}
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Location</span>
          <span class="detail-value">${this._escapeHtml(location) || "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Updated</span>
          <span class="detail-value">${updated}</span>
        </div>
        ${cam.channelTitle ? `<div class="detail-field">
          <span class="detail-label">Channel</span>
          <span class="detail-value">${this._escapeHtml(cam.channelTitle)}</span>
        </div>` : ""}
        ${cam.viewCount ? `<div class="detail-field">
          <span class="detail-label">Views</span>
          <span class="detail-value">${cam.viewCount.toLocaleString()}</span>
        </div>` : ""}
        <div class="detail-field">
          <span class="detail-label">Coordinates</span>
          <span class="detail-value">${cam.lat.toFixed(3)}°, ${cam.lng.toFixed(3)}°</span>
        </div>
      </div>
      <a href="${watchUrl}" target="_blank" rel="noopener" class="detail-track-btn"><i class="fa-solid fa-${cam.playerLink ? 'play' : 'arrow-up-right-from-square'}"></i> ${cam.playerLink ? 'Watch Live' : 'View Source'}</a>
    `
    this.detailPanelTarget.style.display = ""

    // Auto-refresh camera preview images (Windy updates ~30s, DOT ~5s)
    const refreshable = (cam.source === "nycdot" || cam.source === "windy") && cam.thumbnail
    if (refreshable) {
      const interval = cam.source === "nycdot" ? 5000 : 15000
      this._webcamRefreshInterval = setInterval(() => {
        const img = document.getElementById("webcam-detail-img")
        if (img) img.src = `${cam.thumbnail}?t=${Date.now()}`
      }, interval)
    }

    if (this.viewer?.camera && Number.isFinite(cam.lng) && Number.isFinite(cam.lat)) {
      try {
        const Cesium = window.Cesium
        this.viewer.camera.flyTo({
          destination: Cesium.Cartesian3.fromDegrees(cam.lng, cam.lat, 50000),
          duration: 1.5,
        })
      } catch (error) {
        console.warn("Webcam fly-to failed:", error)
      }
    }
  }

  // ── Ships ────────────────────────────────────────────────

}
