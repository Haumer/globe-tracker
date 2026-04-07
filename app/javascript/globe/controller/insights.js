import { getDataSource } from "globe/utils"
import { INSIGHT_SEVERITY_COLORS, INSIGHT_TYPE_ICONS, renderInsightDetailHtml, renderInsightFeedHtml } from "globe/controller/insight_presenters"

export function applyInsightsMethods(GlobeController) {
  GlobeController.prototype._shouldRenderInsightMarker = function(insight) {
    const type = `${insight?.type || ""}`
    const downstreamTypes = new Set([
      "chokepoint_market_stress",
      "country_chokepoint_dependency",
      "supply_chain_vulnerability",
    ])

    if (downstreamTypes.has(type)) return true

    // Keep layer-derivative insights in feed/context, but don't paint them on the globe
    // when a dedicated layer is already showing the same phenomenon.
    if (type.startsWith("fire_")) return false

    if (this.situationsVisible && type === "conflict_pulse") {
      return false
    }

    if (this.chokepointsVisible && type === "chokepoint_disruption") {
      return false
    }

    return true
  }

  GlobeController.prototype.toggleInsights = function() {
    this.insightsVisible = this.hasInsightsToggleTarget && this.insightsToggleTarget.checked
    if (this.insightsVisible) {
      this._startInsightPolling()
    } else {
      this._stopInsightPolling({ clearData: true })
    }
    this._updateStats()
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._startInsightPolling = function() {
    if (this._insightPollInterval) clearInterval(this._insightPollInterval)
    if (!this.insightsVisible) return
    this._fetchInsights()
    this._insightPollInterval = setInterval(() => this._fetchInsights(), 5 * 60 * 1000)
  }

  GlobeController.prototype._stopInsightPolling = function({ clearData = false } = {}) {
    if (this._insightPollInterval) {
      clearInterval(this._insightPollInterval)
      this._insightPollInterval = null
    }
    this._insightFetchToken += 1
    this._clearInsightEntities()
    if (clearData) {
      this._insightsData = []
      this._insightSnapshotStatus = null
      this._renderInsightFeed()
      if (this._syncRightPanels) this._syncRightPanels()
    }
  }

  GlobeController.prototype._clearInsightEntities = function() {
    const ds = this._ds["insights"]
    if (ds && this._insightEntities?.length) {
      ds.entities.suspendEvents()
      this._insightEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._insightEntities = []
    this._requestRender()
  }

  GlobeController.prototype._fetchInsights = async function() {
    if (!this.insightsVisible) return
    const fetchToken = ++this._insightFetchToken
    try {
      const resp = await fetch("/api/insights")
      if (fetchToken !== this._insightFetchToken || !this.insightsVisible) return
      if (!resp.ok) return
      const data = await resp.json()
      if (fetchToken !== this._insightFetchToken || !this.insightsVisible) return
      this._insightsData = (data.insights || []).map((insight, idx) => ({ ...insight, _idx: idx }))
      this._insightSnapshotStatus = data.snapshot_status || "ready"
      this._renderInsightMarkers()
      this._renderInsightFeed()
      this._markFresh("insights")
      // Show insights tab if we have data
      if ((this._insightsData.length > 0 || this._insightSnapshotStatus) && this.hasRpTabInsightsTarget) {
        this.rpTabInsightsTarget.style.display = ""
      }
      if (this._syncRightPanels) this._syncRightPanels()
    } catch (e) {
      console.warn("Insights fetch failed:", e)
    }
  }

  GlobeController.prototype._renderInsightMarkers = function() {
    if (!this.insightsVisible) {
      this._clearInsightEntities()
      return
    }
    const Cesium = window.Cesium
    const ds = getDataSource(this.viewer, this._ds, "insights")

    // Remove old entities
    for (const e of this._insightEntities) ds.entities.remove(e)
    this._insightEntities = []

    if (!this._insightsData.length) return

    const severityColors = Object.fromEntries(
      Object.entries(INSIGHT_SEVERITY_COLORS).map(([severity, color]) => [
        severity,
        Cesium.Color.fromCssColorString(color),
      ])
    )

    this._insightsData.forEach((insight, idx) => {
      if (insight.lat == null || insight.lng == null) return
      if (!this._shouldRenderInsightMarker(insight)) return
      const color = severityColors[insight.severity] || severityColors.medium
      const icon = INSIGHT_TYPE_ICONS[insight.type] || "\u26A0"

      // Pulsing ring
      const ring = ds.entities.add({
        id: `insight-ring-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(insight.lng, insight.lat),
        ellipse: {
          semiMajorAxis: insight.severity === "critical" ? 80000 : 50000,
          semiMinorAxis: insight.severity === "critical" ? 80000 : 50000,
          material: color.withAlpha(0.15),
          outline: true,
          outlineColor: color.withAlpha(0.6),
          outlineWidth: 2,
          height: 0,
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._insightEntities.push(ring)

      // Label
      const label = ds.entities.add({
        id: `insight-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(insight.lng, insight.lat),
        billboard: {
          image: this._makeInsightIcon(icon, color.toCssColorString()),
          width: 28,
          height: 28,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: insight.title.length > 40 ? insight.title.slice(0, 37) + "..." : insight.title,
          font: "11px 'JetBrains Mono', monospace",
          fillColor: Cesium.Color.WHITE,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 2,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -22),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.0, 5e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1.0, 8e6, 0.0),
        },
      })
      this._insightEntities.push(label)
    })

    this._requestRender()
  }

  GlobeController.prototype._makeInsightIcon = function(icon, color) {
    const key = `insight-${icon}-${color}`
    if (this._iconCache?.[key]) return this._iconCache[key]
    if (!this._iconCache) this._iconCache = {}

    const size = 28
    const canvas = document.createElement("canvas")
    canvas.width = size; canvas.height = size
    const ctx = canvas.getContext("2d")

    // Circle background
    ctx.beginPath()
    ctx.arc(size / 2, size / 2, size / 2 - 1, 0, Math.PI * 2)
    ctx.fillStyle = "rgba(0,0,0,0.7)"
    ctx.fill()
    ctx.strokeStyle = color
    ctx.lineWidth = 2
    ctx.stroke()

    // Icon text
    ctx.font = "14px sans-serif"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = color
    ctx.fillText(icon, size / 2, size / 2)

    const url = canvas.toDataURL()
    this._iconCache[key] = url
    return url
  }

  GlobeController.prototype._insightIndex = function(insight) {
    if (Number.isInteger(insight?._idx)) return insight._idx
    return (this._insightsData || []).findIndex(candidate => candidate === insight)
  }

  GlobeController.prototype._affectedInsightEntities = function(insight) {
    const entities = insight?.entities || {}
    const affected = []
    const appendNode = node => {
      if (!node?.kind || !node?.id) return
      if (affected.some(entry => entry.kind === node.kind && entry.id === node.id)) return
      affected.push({
        kind: node.kind,
        id: node.id,
        label: node.label || node.name || node.id,
        icon: node.kind === "commodity" ? "fa-chart-line" : "fa-circle-nodes",
      })
    }

    appendNode(entities.primary_node)
    appendNode(entities.secondary_node)

    if (entities.flight?.icao24 || entities.flight?.callsign) {
      const flightLabel = entities.flight.callsign || entities.flight.icao24 || "Affected flight"
      const squawkLabel = entities.flight.squawk ? ` · ${entities.flight.squawk}` : ""
      affected.push({
        kind: "flight",
        label: `${flightLabel}${squawkLabel}`,
        icon: "fa-plane",
      })
    }

    if (entities.ship?.mmsi) {
      affected.push({
        kind: "ship",
        label: entities.ship.name || entities.ship.mmsi || "Affected ship",
        icon: "fa-ship",
      })
    }

    if (entities.chokepoint?.name) {
      affected.push({
        kind: "chokepoint",
        label: entities.chokepoint.name,
        icon: "fa-anchor",
      })
    }

    return affected
  }

  GlobeController.prototype._affectedInsightActionLabel = function(affectedEntities) {
    if (affectedEntities.length !== 1) return "Show affected entities"

    return {
      entity: "Show affected node",
      commodity: "Show affected commodity",
      flight: "Show affected flight",
      ship: "Show affected ship",
      chokepoint: "Show affected node",
    }[affectedEntities[0].kind] || "Show affected entity"
  }

  GlobeController.prototype._normalizeInsightFlightDetail = function(flight) {
    if (!flight?.icao24) return null

    const lat = flight.latitude
    const lng = flight.longitude
    const alt = flight.altitude || 0

    return {
      id: flight.icao24,
      callsign: (flight.callsign || flight.icao24 || "").trim(),
      latitude: lat,
      longitude: lng,
      altitude: alt,
      currentLat: lat,
      currentLng: lng,
      currentAlt: alt,
      heading: flight.heading || 0,
      speed: flight.speed || 0,
      verticalRate: flight.vertical_rate || 0,
      onGround: flight.on_ground,
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
    }
  }

  GlobeController.prototype._findLoadedFlightByInsightRef = function(flightRef) {
    if (!flightRef) return null

    if (flightRef.icao24 && this.flightData.has(flightRef.icao24)) {
      return this.flightData.get(flightRef.icao24)
    }

    const callsign = (flightRef.callsign || "").trim().toUpperCase()
    if (!callsign) return null

    for (const flight of this.flightData.values()) {
      if ((flight.callsign || "").trim().toUpperCase() === callsign) return flight
    }

    return null
  }

  GlobeController.prototype._focusInsightFlight = function(flightId, flight) {
    const resolvedId = flight?.id || flightId
    const loadedFlight = resolvedId ? this.flightData.get(resolvedId) : null
    const focusFlight = loadedFlight || flight
    if (!focusFlight) return false

    if (loadedFlight && !this.selectedFlights.has(resolvedId)) {
      this.toggleFlightSelection(resolvedId)
    }

    this._focusedSelection = { type: "flight", id: resolvedId }
    this._renderSelectionTray()

    const lat = focusFlight.currentLat ?? focusFlight.latitude
    const lng = focusFlight.currentLng ?? focusFlight.longitude
    this._flyToCoordinates?.(lng, lat, 200000, { duration: 1.0 })

    this.showDetail(resolvedId, focusFlight)
    return true
  }

  GlobeController.prototype._focusInsightShip = function(ship) {
    if (!ship) return false

    const shipId = `${ship.mmsi}`
    if (!this.selectedShips.has(shipId)) this.toggleShipSelection(shipId)

    this._focusedSelection = { type: "ship", id: shipId }
    this._renderSelectionTray()

    const lat = ship.currentLat ?? ship.latitude
    const lng = ship.currentLng ?? ship.longitude
    this._flyToCoordinates?.(lng, lat, 100000, { duration: 1.0 })

    this._showShipLikeDetail?.(ship)
    return true
  }

  GlobeController.prototype._flyToInsightTarget = function(lat, lng, height = 350000, duration = 1.1) {
    return this._flyToCoordinatesAsync
      ? this._flyToCoordinatesAsync(lng, lat, height, duration)
      : Promise.resolve(false)
  }

  GlobeController.prototype._fetchInsightFlightRecord = async function(identifier) {
    if (!identifier) return null

    try {
      const response = await fetch(`/api/flights/${encodeURIComponent(identifier)}`)
      if (!response.ok) return null
      const flight = await response.json()
      return flight?.icao24 ? flight : null
    } catch (_error) {
      return null
    }
  }

  GlobeController.prototype._revealInsightFlight = async function(insight) {
    const flightRef = insight?.entities?.flight
    const flightIdentifier = flightRef?.icao24 || flightRef?.callsign
    if (!flightIdentifier) return false

    if (this._ensureContextLayerVisible) this._ensureContextLayerVisible("flights")

    let flight = this._findLoadedFlightByInsightRef(flightRef)
    if (!flight && Number.isFinite(insight?.lat) && Number.isFinite(insight?.lng)) {
      await this._flyToInsightTarget(insight.lat, insight.lng, 280000, 1.1)
      if (typeof this.fetchFlights === "function") await this.fetchFlights()
      flight = this._findLoadedFlightByInsightRef(flightRef)
    }

    if (flight) return this._focusInsightFlight(flight.id || flight.icao24 || flightIdentifier, flight)

    const fetchedFlight = await this._fetchInsightFlightRecord(flightRef.icao24 || flightRef.callsign)
    if (fetchedFlight && typeof this.upsertFlightRecord === "function") {
      const upsertedFlight = this.upsertFlightRecord(fetchedFlight)
      if (upsertedFlight) return this._focusInsightFlight(upsertedFlight.id, upsertedFlight)
    }

    const fallbackFlight = this._normalizeInsightFlightDetail(fetchedFlight)
    if (fallbackFlight) return this._focusInsightFlight(fallbackFlight.id, fallbackFlight)

    this._toast(`Unable to load affected flight ${flightRef.callsign || flightRef.icao24}`, "error")
    return false
  }

  GlobeController.prototype._revealInsightShip = async function(insight) {
    const shipRef = insight?.entities?.ship
    const shipId = shipRef?.mmsi
    if (!shipId) return false

    if (this._ensureContextLayerVisible) this._ensureContextLayerVisible("ships")

    let ship = this._resolveShipRecord?.(shipId)
    if (!ship && Number.isFinite(insight?.lat) && Number.isFinite(insight?.lng)) {
      await this._flyToInsightTarget(insight.lat, insight.lng, 180000, 1.1)
      if (typeof this.fetchShips === "function") await this.fetchShips()
      if (!ship && typeof this.fetchNavalVessels === "function") {
        const priorNavalState = this.navalVesselsVisible
        if (!priorNavalState) this.navalVesselsVisible = true
        await this.fetchNavalVessels()
        if (!priorNavalState) {
          this.navalVesselsVisible = false
          this._clearNavalVesselEntities?.()
        }
      }
      ship = this._resolveShipRecord?.(shipId)
    }

    if (!ship) {
      this._toast(`Unable to load affected ship ${shipRef.name || shipId}`, "error")
      return false
    }

    return this._focusInsightShip(ship)
  }

  GlobeController.prototype._revealAffectedInsightEntity = async function(insight, entityKind) {
    switch (entityKind) {
      case "flight":
        return this._revealInsightFlight(insight)
      case "ship":
        return this._revealInsightShip(insight)
      case "chokepoint": {
        const chokepointName = insight?.entities?.chokepoint?.name
        if (!chokepointName) return false
        const chokepoint = this._findChokepointById?.(chokepointName)
        if (!chokepoint) {
          this._focusContextNode?.({ kind: "chokepoint", id: chokepointName }, { title: chokepointName })
          return false
        }
        if (Number.isFinite(chokepoint.lat) && Number.isFinite(chokepoint.lng)) {
          await this._flyToInsightTarget(chokepoint.lat, chokepoint.lng, 450000, 1.0)
        }
        this.showChokepointDetail?.(chokepoint)
        return true
      }
      case "entity":
      case "commodity": {
        const nodes = [insight?.entities?.primary_node, insight?.entities?.secondary_node].filter(Boolean)
        const node = nodes.find(candidate => candidate.kind === entityKind)
        if (!node?.id) return false
        if (Number.isFinite(insight?.lat) && Number.isFinite(insight?.lng)) {
          await this._flyToInsightTarget(insight.lat, insight.lng, 450000, 1.0)
        }
        this._focusContextNode?.({ kind: entityKind, id: node.id }, { title: node.label || node.id, lat: insight?.lat, lng: insight?.lng })
        return true
      }
      default:
        return false
    }
  }

  GlobeController.prototype.showAffectedInsightEntities = async function(event) {
    event.preventDefault()
    event.stopPropagation()

    const idx = Number.parseInt(event.currentTarget.dataset.insightIdx, 10)
    const insight = this._insightsData?.[idx]
    if (!insight) return

    this.showInsightDetail(insight)

    const affectedEntities = this._affectedInsightEntities(insight)
    if (!affectedEntities.length) return

    const revealed = await this._revealAffectedInsightEntity(insight, affectedEntities[0].kind)
    if (revealed && affectedEntities.length > 1) {
      this._toast("Showing the first affected entity. Use the detail panel for the rest.")
    }
  }

  GlobeController.prototype.focusAffectedInsightEntity = async function(event) {
    event.preventDefault()
    event.stopPropagation()

    const idx = Number.parseInt(event.currentTarget.dataset.insightIdx, 10)
    const insight = this._insightsData?.[idx]
    const entityKind = event.currentTarget.dataset.entityKind
    if (!insight || !entityKind) return

    this.showInsightDetail(insight)
    await this._revealAffectedInsightEntity(insight, entityKind)
  }

  GlobeController.prototype._renderInsightFeed = function() {
    if (!this.hasInsightFeedContentTarget) return
    if (!this.insightsVisible) {
      if (this.hasInsightFeedCountTarget) this.insightFeedCountTarget.textContent = ""
      this.insightFeedContentTarget.innerHTML = ""
      return
    }
    const insights = this._insightsData || []
    const snapshotStatus = this._insightSnapshotStatus || "pending"

    if (this.hasInsightFeedCountTarget) {
      const base = `${insights.length} insight${insights.length !== 1 ? "s" : ""}`
      const suffix = snapshotStatus === "ready" ? "" : ` · ${this._statusLabel(snapshotStatus, "snapshot")}`
      this.insightFeedCountTarget.textContent = `${base}${suffix}`
    }

    if (insights.length === 0) {
      const emptyLabel = {
        pending: "Insight snapshot pending. Correlations appear after the stored layers finish updating.",
        stale: "No stored insights in the latest snapshot.",
        error: "Insight snapshot unavailable.",
      }[snapshotStatus] || "No cross-layer correlations detected. Insights appear when multiple data layers overlap geographically."
      this.insightFeedContentTarget.innerHTML = `<div class="insight-empty">${this._escapeHtml(emptyLabel)}</div>`
      return
    }

    this.insightFeedContentTarget.innerHTML = renderInsightFeedHtml(this, insights, snapshotStatus)
  }

  GlobeController.prototype.focusInsight = function(event) {
    const idx = parseInt(event.currentTarget.dataset.insightIdx)
    const insight = this._insightsData?.[idx]
    if (!insight) return

    // Show insight detail panel
    this.showInsightDetail(insight)

    // Fly camera if location is available
    if (insight.lat != null && insight.lng != null) {
      this._flyToCoordinates?.(insight.lng, insight.lat, 500000, { duration: 1.5 })
    }
  }

  GlobeController.prototype.showInsightDetail = function(insight) {
    if (this._buildInsightContext && this._setSelectedContext) {
      this._setSelectedContext(this._buildInsightContext(insight))
    }

    this.detailContentTarget.innerHTML = renderInsightDetailHtml(this, insight)
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype.toggleInsightsFeed = function() {
    if (this.insightsVisible && this._insightsData?.length > 0) {
      this._showRightPanel("insights")
    }
  }

  // ── Intelligence Brief ──────────────────────────────────

  GlobeController.prototype.loadBrief = async function() {
    const container = document.getElementById("intelligence-brief")
    if (!container) return

    // Toggle visibility
    if (container.style.display !== "none") {
      container.style.display = "none"
      return
    }

    container.style.display = ""
    container.innerHTML = `<div style="font:400 11px 'JetBrains Mono',monospace;color:rgba(200,210,225,0.4);padding:12px 0;">Generating intelligence brief...</div>`

    try {
      const resp = await fetch("/api/brief")
      if (resp.status === 403) {
        container.innerHTML = `<div style="color:rgba(255,152,0,0.75);font:400 11px monospace;">Brief is currently internal-only.</div>`
        return
      }
      if (!resp.ok) { container.innerHTML = `<div style="color:#ef5350;font:400 11px monospace;">Failed to load brief.</div>`; return }
      const data = await resp.json()

      if (data.status === "generating") {
        container.innerHTML = `<div style="font:400 11px 'JetBrains Mono',monospace;color:rgba(255,152,0,0.6);padding:12px 0;"><i class="fa-solid fa-spinner fa-spin" style="margin-right:6px;"></i>${data.message}</div>`
        // Retry in 15 seconds
        setTimeout(() => this.loadBrief(), 15000)
        return
      }

      const brief = data.brief || "No brief available."
      const generatedAt = data.generated_at ? new Date(data.generated_at).toLocaleString() : ""
      const ctx = data.context_summary || {}

      // Format the brief text — convert section headers to styled spans
      const formatted = this._escapeHtml(brief)
        .replace(/^(CRITICAL|HIGH|NOTABLE|CROSS-LAYER CONNECTIONS|MARKET IMPACT)/gm,
          '<span style="display:block;font:700 11px \'JetBrains Mono\',monospace;color:#ff9800;letter-spacing:1px;margin:14px 0 6px;padding-top:8px;border-top:1px solid rgba(255,255,255,0.06);">$1</span>')
        .replace(/\n- /g, '\n<span style="color:rgba(255,152,0,0.4);margin-right:4px;">▸</span>')
        .replace(/\n/g, '<br>')

      container.innerHTML = `
        <div style="font:400 11px/1.7 'DM Sans',sans-serif;color:rgba(200,210,225,0.75);">
          ${formatted}
        </div>
        <div style="font:400 9px 'JetBrains Mono',monospace;color:rgba(200,210,225,0.2);margin-top:12px;padding-top:8px;border-top:1px solid rgba(255,255,255,0.04);">
          Generated ${generatedAt} · ${ctx.conflict_zones || 0} zones · ${ctx.earthquakes || 0} quakes · ${ctx.news_articles || 0} articles
        </div>
      `
    } catch (e) {
      container.innerHTML = `<div style="color:#ef5350;font:400 11px monospace;">Error: ${e.message}</div>`
    }
  }

}
