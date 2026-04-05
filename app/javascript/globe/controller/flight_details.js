export function applyFlightDetailMethods(GlobeController) {
  GlobeController.prototype.showDetail = function(id, data) {
    this._focusedSelection = { type: "flight", id }
    this._renderSelectionTray()
    this._clearFlightRoute()
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
      ${isEmergency ? `<div class="detail-emergency-banner">${squawkLabels[data.squawk] || this._escapeHtml((data.emergency || "EMERGENCY").toUpperCase())}</div>` : ""}
      <div class="detail-callsign">${this._escapeHtml(callsign || id)}</div>
      <div class="detail-country">${this._escapeHtml(data.originCountry || "Unknown")}</div>
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
          <span class="detail-value" style="font-size:12px; opacity:0.7;">${this._escapeHtml(id)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Status</span>
          <span class="detail-value">${data.onGround ? "On Ground" : "Airborne"}</span>
        </div>
        ${data.registration ? `<div class="detail-field">
          <span class="detail-label">Reg</span>
          <span class="detail-value">${this._escapeHtml(data.registration)}</span>
        </div>` : ""}
        ${data.aircraftType ? `<div class="detail-field">
          <span class="detail-label">Type</span>
          <span class="detail-value">${this._escapeHtml(data.aircraftType)}</span>
        </div>` : ""}
        ${data.category ? `<div class="detail-field">
          <span class="detail-label">Category</span>
          <span class="detail-value">${this._escapeHtml(data.category)}</span>
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
        <a href="https://www.flightradar24.com/${encodeURIComponent(callsign)}" target="_blank" rel="noopener">FR24</a>
        <a href="https://www.flightaware.com/live/flight/${encodeURIComponent(callsign)}" target="_blank" rel="noopener">FlightAware</a>
        <a href="https://globe.adsbexchange.com/?icao=${encodeURIComponent(id)}" target="_blank" rel="noopener">ADS-B</a>
      </div>
      <div style="display:flex;gap:6px;align-items:center;">
        <button class="detail-track-btn ${isTracking ? "tracking" : ""}" data-flight-id="${id}" style="flex:1;">
          ${isTracking ? "Stop Tracking" : "Track Flight"}
        </button>
        ${isTracking ? `<button class="detail-track-btn" id="tracking-height-btn" style="flex:0;white-space:nowrap;">${this._trackingHeightLabels[this._trackingHeightIdx]}</button>` : ""}
      </div>
      ${this.signedInValue ? `<button class="detail-watch-btn" data-action="click->globe#createWatch"
        data-watch-type="entity"
        data-watch-name="Watch ${this._escapeHtml(callsign || id)}"
        data-watch-conditions='${JSON.stringify({ entity_type: "flight", identifier: callsign || id, match: "callsign_exact" })}'>
        <i class="fa-solid fa-eye"></i> Watch
      </button>` : ""}
      ${this.signedInValue ? `<button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showFlightHistory" data-flight-icao="${id}">
        <i class="fa-solid fa-clock-rotate-left" style="margin-right:4px;"></i>Flight History (24h)
      </button>` : ""}
      ${this._connectionsPlaceholder()}
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: OpenSky Network / ADS-B Exchange</div>
    `

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

    this._fetchConnections("flight", data.currentLat, data.currentLng, {
      squawk: data.squawk || "",
      origin_country: data.originCountry || "",
    })

    const cached = this._routeCache && this._routeCache[callsign]
    const routeEl = document.getElementById("detail-route")
    if (cached && routeEl) {
      routeEl.innerHTML = this._renderFlightRouteDetail(cached)
      if (cached.origin && cached.dest) {
        this._drawFlightRoute(callsign, cached.origin, cached.dest)
      }
      const cachedExpiresAt = this._parseDateValue(cached.expiresAt)
      if (cachedExpiresAt && cachedExpiresAt.getTime() <= Date.now()) {
        this.fetchRoute(callsign)
      }
    } else if (callsign) {
      this.fetchRoute(callsign)
    }
  }

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
    this._fetchingRouteFor = callsign

    try {
      const response = await fetch(`/api/flights/${encodeURIComponent(callsign)}`)
      if (this._fetchingRouteFor !== callsign) return

      const el = document.getElementById("detail-route")

      if (!response.ok) {
        console.warn("Route API error:", response.status)
        if (el) el.innerHTML = this._renderFlightRouteDetail({ status: "failed" })
        return
      }

      const data = await response.json()
      const routeStatus = data.route_status || "unavailable"
      const routePayload = data.route || {}
      const routeStops = Array.isArray(routePayload.route) ? routePayload.route : []

      if (routeStatus !== "available" || routeStops.length < 2) {
        if (routeStatus === "available") console.warn("No route data:", data)
        if (el) {
          el.innerHTML = this._renderFlightRouteDetail({
            status: routeStatus === "available" ? "unavailable" : routeStatus,
            fetchedAt: data.route_fetched_at,
            expiresAt: data.route_expires_at,
            error: data.route_error,
          })
        }
        return
      }

      const originIcao = routeStops[0]
      const destIcao = routeStops[routeStops.length - 1]
      const origin = this._getAirport(originIcao)
      const dest = this._getAirport(destIcao)

      const originLabel = origin ? `${origin.name} (${originIcao})` : originIcao
      const destLabel = dest ? `${dest.name} (${destIcao})` : destIcao

      if (!this._routeCache) this._routeCache = {}
      this._routeCache[callsign] = {
        status: routeStatus,
        originIcao,
        destIcao,
        origin,
        dest,
        originLabel,
        destLabel,
        fetchedAt: data.route_fetched_at,
        expiresAt: data.route_expires_at,
        operatorIata: routePayload.operator_iata,
        flightNumber: routePayload.flight_number,
      }

      if (el) {
        el.innerHTML = this._renderFlightRouteDetail(this._routeCache[callsign])
      }

      if (origin && dest) {
        this._drawFlightRoute(callsign, origin, dest)
      }
    } catch (e) {
      console.warn("Route fetch failed:", e)
      const el = document.getElementById("detail-route")
      if (el) el.innerHTML = this._renderFlightRouteDetail({ status: "failed" })
    }
  }

  GlobeController.prototype._renderFlightRouteDetail = function(route) {
    const status = route?.status || "pending"
    const meta = this._cacheMeta(route?.fetchedAt, route?.expiresAt)

    if (status !== "available") {
      const statusLabel = {
        pending: "Route lookup queued",
        failed: "Route unavailable",
        unavailable: "Route unavailable",
      }[status] || "Route unavailable"
      const errorLabel = route?.error ? ` · ${String(route.error).replace(/_/g, " ")}` : ""
      return `
        ${this._statusChip(status, this._statusLabel(status, "route"))}
        <div style="margin-top:6px;">
          <span class="route-unavailable">${this._escapeHtml(statusLabel + errorLabel)}</span>
        </div>
        ${meta ? `<div style="margin-top:4px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.45);">${this._escapeHtml(meta)}</div>` : ""}
      `
    }

    const operatorMeta = [route.operatorIata, route.flightNumber].filter(Boolean).join(" · ")
    return `
      <div>
        <span class="route-airport">${this._escapeHtml(route.originLabel || route.originIcao || "Unknown")}</span>
        <span class="route-arrow">→</span>
        <span class="route-airport">${this._escapeHtml(route.destLabel || route.destIcao || "Unknown")}</span>
      </div>
      <div style="margin-top:6px;display:flex;flex-wrap:wrap;gap:4px;align-items:center;">
        ${this._statusChip(status, "stored route")}
        ${operatorMeta ? `<span class="detail-chip" style="background:rgba(79,195,247,0.12);color:#4fc3f7;">${this._escapeHtml(operatorMeta)}</span>` : ""}
      </div>
      ${meta ? `<div style="margin-top:4px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.45);">${this._escapeHtml(meta)}</div>` : ""}
    `
  }

  GlobeController.prototype._drawFlightRoute = function(callsign, origin, dest) {
    const Cesium = window.Cesium
    const dataSource = this.getFlightsDataSource()

    this._clearFlightRoute()

    this._flightRouteEntities = []

    const points = this._greatCirclePoints(origin.lat, origin.lng, dest.lat, dest.lng, 80)
    const positions = points.map(p => Cesium.Cartesian3.fromDegrees(p.lng, p.lat, 0))

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

      const first = data.route[0]
      const startE = ds.entities.add({
        id: `flt-history-start-${icao}`,
        position: Cesium.Cartesian3.fromDegrees(first.lng, first.lat, first.alt || 0),
        point: { pixelSize: 6, color: Cesium.Color.fromCssColorString("#ce93d8"), outlineColor: Cesium.Color.WHITE, outlineWidth: 1 },
        label: {
          text: `${data.callsign || icao} (${new Date(first.t * 1000).toISOString().slice(11, 16)} UTC)`,
          font: "10px 'JetBrains Mono', monospace",
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

  GlobeController.prototype.closeDetail = function(event) {
    const explicitClose = event?.currentTarget?.classList?.contains("anchor-close") ||
      event?.currentTarget?.classList?.contains("detail-close")

    if (this._anchoredDetailDismissGuardActive?.({ explicit: explicitClose })) {
      if (this.hasDetailPanelTarget) this.detailPanelTarget.style.display = "none"
      return
    }

    const closedAnchoredDetail = this.closeAnchoredDetail?.({ explicit: explicitClose })
    if (closedAnchoredDetail === false) {
      if (this.hasDetailPanelTarget) this.detailPanelTarget.style.display = "none"
      return
    }

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
    if (this._webcamRefreshInterval) {
      clearInterval(this._webcamRefreshInterval)
      this._webcamRefreshInterval = null
    }
    if (this._ytMessageCleanup) {
      this._ytMessageCleanup()
      this._ytMessageCleanup = null
    }
  }
}
