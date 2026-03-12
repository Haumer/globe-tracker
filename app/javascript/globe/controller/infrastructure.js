import { findCountryAtPoint, getDataSource, haversineDistance } from "../utils"

export function applyInfrastructureMethods(GlobeController) {
  GlobeController.prototype.getGpsJammingDataSource = function() { return getDataSource(this.viewer, this._ds, "gpsJamming") }

  GlobeController.prototype.toggleGpsJamming = function() {
    this.gpsJammingVisible = this.hasGpsJammingToggleTarget && this.gpsJammingToggleTarget.checked
    if (this.gpsJammingVisible) {
      this.fetchGpsJamming()
      this._gpsJammingInterval = setInterval(() => this.fetchGpsJamming(), 60000)
    } else {
      if (this._gpsJammingInterval) { clearInterval(this._gpsJammingInterval); this._gpsJammingInterval = null }
      this._clearGpsJammingEntities()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchGpsJamming = async function() {
    if (this._timelineActive) return
    this._toast("Loading GPS jamming...")
    try {
      const resp = await fetch("/api/gps_jamming")
      if (!resp.ok) return
      const cells = await resp.json()
      this._renderGpsJamming(cells)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch GPS jamming data:", e)
    }
  }

  GlobeController.prototype._renderGpsJamming = function(cells) {
    this._clearGpsJammingEntities()
    const dataSource = this.getGpsJammingDataSource()
    const Cesium = window.Cesium

    if (cells.length === 0) return

    const colors = {
      low: Cesium.Color.fromCssColorString("rgba(255, 152, 0, 0.25)"),
      medium: Cesium.Color.fromCssColorString("rgba(255, 87, 34, 0.45)"),
      high: Cesium.Color.fromCssColorString("rgba(244, 67, 54, 0.55)")
    }
    const outlines = {
      low: Cesium.Color.fromCssColorString("rgba(255, 152, 0, 0.5)"),
      medium: Cesium.Color.fromCssColorString("rgba(255, 87, 34, 0.8)"),
      high: Cesium.Color.fromCssColorString("rgba(244, 67, 54, 0.9)")
    }

    const hexRadius = 0.5 // degrees — matches backend HEX_SIZE for flush tiling

    cells.forEach(cell => {
      const hexPoints = this._hexVertices(cell.lat, cell.lng, hexRadius)
      const positions = hexPoints.map(p => Cesium.Cartesian3.fromDegrees(p[1], p[0]))

      const hexEntity = dataSource.entities.add({
        id: `jam-${cell.lat}-${cell.lng}`,
        polygon: {
          hierarchy: new Cesium.PolygonHierarchy(positions),
          material: colors[cell.level] || colors.medium,
          outline: true,
          outlineColor: outlines[cell.level] || outlines.medium,
          outlineWidth: 2,
          height: 0,
        },
        description: `<div style="font-family: 'DM Sans', sans-serif;">
          <div style="font-size: 15px; font-weight: 600; margin-bottom: 6px;">GPS Interference</div>
          <div style="font-size: 13px; color: ${cell.level === 'high' ? '#f44336' : '#ffc107'}; font-weight: 600; margin-bottom: 4px;">${cell.level.toUpperCase()} — ${cell.pct}%</div>
          <div style="font-size: 12px; color: #aaa;">${cell.bad} of ${cell.total} aircraft with degraded accuracy</div>
          <div style="font-size: 11px; color: #666; margin-top: 6px;">NACp ≤ 6 indicates GPS jamming or spoofing</div>
        </div>`,
      })
      this._gpsJammingEntities.push(hexEntity)

      // Label only for medium/high
      if (cell.level !== "low") {
        const labelEntity = dataSource.entities.add({
          id: `jam-lbl-${cell.lat}-${cell.lng}`,
          position: Cesium.Cartesian3.fromDegrees(cell.lng, cell.lat, 200),
          label: {
            text: `⚠ ${cell.pct}%`,
            font: "13px DM Sans, sans-serif",
            fillColor: cell.level === "high" ? Cesium.Color.fromCssColorString("#ff5252") : Cesium.Color.fromCssColorString("#ffd54f"),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.CENTER,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
            scaleByDistance: new Cesium.NearFarScalar(1e5, 1.0, 8e6, 0.4),
          },
        })
        this._gpsJammingEntities.push(labelEntity)
      }
    })
  }

  // Generate 6 vertices of a flat-top hexagon at (lat, lng) with given radius in degrees.
  // Corrects longitude for latitude so hexagons appear regular on the globe.

  GlobeController.prototype._hexVertices = function(lat, lng, radius) {
    const vertices = []
    const cosLat = Math.cos(lat * Math.PI / 180)
    const lngR = cosLat > 0.01 ? radius / cosLat : radius
    for (let i = 0; i < 6; i++) {
      const angle = (Math.PI / 3) * i  // flat-top: 0°, 60°, 120°...
      vertices.push([
        lat + radius * Math.sin(angle),
        lng + lngR * Math.cos(angle),
      ])
    }
    return vertices
  }

  GlobeController.prototype._clearGpsJammingEntities = function() {
    const ds = this.getGpsJammingDataSource()
    this._gpsJammingEntities.forEach(e => ds.entities.remove(e))
    this._gpsJammingEntities = []
  }

  // ── Submarine Cables ──────────────────────────────────────

  GlobeController.prototype.getCablesDataSource = function() { return getDataSource(this.viewer, this._ds, "cables") }

  GlobeController.prototype.toggleCables = function() {
    this.cablesVisible = this.hasCablesToggleTarget && this.cablesToggleTarget.checked
    if (this.cablesVisible) {
      this.fetchCables()
    } else {
      this._clearCableEntities()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchCables = async function() {
    this._toast("Loading submarine cables...")
    try {
      const resp = await fetch("/api/submarine_cables")
      if (!resp.ok) return
      const data = await resp.json()
      const hasData = (data.cables?.length || 0) > 0 || (data.landingPoints?.length || 0) > 0
      this._handleBackgroundRefresh(resp, "submarine-cables", hasData, () => {
        if (this.cablesVisible) this.fetchCables()
      })
      this._renderCables(data.cables, data.landingPoints)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch submarine cables:", e)
    }
  }

  GlobeController.prototype._renderCables = function(cables, landingPoints) {
    this._clearCableEntities()
    const Cesium = window.Cesium
    const dataSource = this.getCablesDataSource()

    // Render cable polylines
    cables.forEach(cable => {
      const color = Cesium.Color.fromCssColorString(cable.color || "#00bcd4").withAlpha(0.6)
      const coords = cable.coordinates || []

      // Each cable may have multiple segments (array of arrays of [lng, lat])
      coords.forEach((segment, si) => {
        if (!Array.isArray(segment) || segment.length < 2) return
        const positions = segment.map(pt => {
          if (Array.isArray(pt) && pt.length >= 2) {
            return Cesium.Cartesian3.fromDegrees(pt[0], pt[1], -50)
          }
          return null
        }).filter(p => p !== null)

        if (positions.length < 2) return

        const entity = dataSource.entities.add({
          id: `cable-${cable.id}-${si}`,
          polyline: {
            positions,
            width: 1.5,
            material: new Cesium.PolylineGlowMaterialProperty({
              glowPower: 0.15,
              color,
            }),
            clampToGround: false,
          },
          properties: {
            cableName: cable.name,
            cableId: cable.id,
          },
        })
        this._cableEntities.push(entity)
      })
    })

    // Render landing points
    if (landingPoints) {
      landingPoints.forEach(lp => {
        const entity = dataSource.entities.add({
          id: `landing-${lp.id}`,
          position: Cesium.Cartesian3.fromDegrees(lp.lng, lp.lat, 0),
          point: {
            pixelSize: 4,
            color: Cesium.Color.fromCssColorString("#00e5ff").withAlpha(0.9),
            outlineColor: Cesium.Color.fromCssColorString("#00838f").withAlpha(0.5),
            outlineWidth: 1,
            scaleByDistance: new Cesium.NearFarScalar(5e4, 1.2, 5e6, 0.3),
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          },
          label: {
            text: lp.name || "",
            font: "10px JetBrains Mono, monospace",
            fillColor: Cesium.Color.fromCssColorString("#80deea").withAlpha(0.8),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 2,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: new Cesium.Cartesian2(0, -10),
            scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 2e6, 0),
            translucencyByDistance: new Cesium.NearFarScalar(1e4, 1.0, 3e6, 0),
          },
        })
        this._landingPointEntities.push(entity)
      })
    }

    // Cross-layer: highlight landing points in attacked countries
    if (this.trafficVisible && this._attackedCountries?.size) {
      this._refreshCableAttackHighlights()
    }
  }

  GlobeController.prototype._clearCableEntities = function() {
    const ds = this.getCablesDataSource()
    this._cableEntities.forEach(e => ds.entities.remove(e))
    this._cableEntities = []
    this._landingPointEntities.forEach(e => ds.entities.remove(e))
    this._landingPointEntities = []
  }

  GlobeController.prototype._refreshCableAttackHighlights = function() {
    this._clearCableAttackHighlights()
    if (!this.trafficVisible || !this._attackedCountries?.size || !this._landingPointEntities.length) return
    if (!this._countryFeatures.length) return // need borders data for country lookup

    const Cesium = window.Cesium
    const dataSource = this.getCablesDataSource()
    this._cableAttackEntities = []

    this._landingPointEntities.forEach(e => {
      const pos = e.position?.getValue(Cesium.JulianDate.now())
      if (!pos) return
      const carto = Cesium.Cartographic.fromCartesian(pos)
      const lat = Cesium.Math.toDegrees(carto.latitude)
      const lng = Cesium.Math.toDegrees(carto.longitude)
      const country = findCountryAtPoint(this._countryFeatures, lat, lng)
      const code = country?.properties?.ISO_A2 || country?.properties?.iso_a2
      if (!code || !this._attackedCountries.has(code)) return

      const ring = dataSource.entities.add({
        id: `cable-atk-${e.id}`,
        position: Cesium.Cartesian3.fromDegrees(lng, lat, 0),
        point: {
          pixelSize: 8,
          color: Cesium.Color.RED.withAlpha(0.8),
          outlineColor: Cesium.Color.RED.withAlpha(0.3),
          outlineWidth: 4,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.4, 5e6, 0.4),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
      })
      this._cableAttackEntities.push(ring)
    })
  }

  GlobeController.prototype._clearCableAttackHighlights = function() {
    if (!this._cableAttackEntities) return
    const ds = this._ds["cables"]
    if (ds) {
      this._cableAttackEntities.forEach(e => ds.entities.remove(e))
    }
    this._cableAttackEntities = []
  }

  // ── Internet Outages ─────────────────────────────────────

  GlobeController.prototype.getOutagesDataSource = function() { return getDataSource(this.viewer, this._ds, "outages") }

  GlobeController.prototype.toggleOutages = function() {
    this.outagesVisible = this.hasOutagesToggleTarget && this.outagesToggleTarget.checked
    if (this.outagesVisible) {
      this.fetchOutages()
      this._outageInterval = setInterval(() => this.fetchOutages(), 300000) // 5min
    } else {
      if (this._outageInterval) clearInterval(this._outageInterval)
      this._clearOutageEntities()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchOutages = async function() {
    if (this._timelineActive) return
    this._toast("Loading outages...")
    try {
      const resp = await fetch("/api/internet_outages")
      if (!resp.ok) return
      const data = await resp.json()
      const hasData = (data.summary?.length || 0) > 0 || (data.events?.length || 0) > 0
      this._handleBackgroundRefresh(resp, "internet-outages", hasData, () => {
        if (this.outagesVisible && !this._timelineActive) this.fetchOutages()
      })
      this._outageData = data.summary || []
      this._renderOutages(data)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch internet outages:", e)
    }
  }

  GlobeController.prototype._renderOutages = function(data) {
    this._clearOutageEntities()
    const Cesium = window.Cesium
    const dataSource = this.getOutagesDataSource()

    const levelColors = {
      critical: "#e040fb",
      severe: "#f44336",
      moderate: "#ff9800",
      minor: "#ffc107",
    }

    // Country centroids for rendering (ISO-2 to approx lat/lng)
    const countryCentroids = {
      AD:[42.5,1.5],AE:[24,54],AF:[33,65],AG:[17.1,-61.8],AL:[41,20],AM:[40,45],AO:[-12.5,18.5],AR:[-34,-64],AT:[47.5,13.5],AU:[-25,135],AW:[12.5,-70],AZ:[40.5,47.5],BA:[44,18],BB:[13.2,-59.5],BD:[24,90],BE:[50.8,4],BF:[13,-1.5],BG:[43,25],BH:[26,50.6],BI:[-3.5,30],BJ:[9.5,2.25],BM:[32.3,-64.8],BN:[4.5,114.7],BO:[-17,-65],BR:[-10,-55],BS:[25,-77.4],BT:[27.5,90.5],BW:[-22,24],BY:[53,28],BZ:[17.2,-88.5],CA:[60,-95],CD:[-2.5,23.5],CF:[7,21],CG:[-1,15],CH:[47,8],CI:[8,-5.5],CL:[-30,-71],CM:[6,12],CN:[35,105],CO:[4,-72],CR:[10,-84],CU:[22,-80],CV:[16,-24],CW:[12.2,-69],CY:[35,33],CZ:[49.75,15.5],DE:[51,9],DJ:[11.5,43],DK:[56,10],DO:[19,-70.7],DZ:[28,3],EC:[-2,-77.5],EE:[59,26],EG:[27,30],ER:[15,39],ES:[40,-4],ET:[8,38],FI:[64,26],FJ:[-18,179],FO:[62,-7],FR:[46,2],GA:[-1,11.8],GB:[54,-2],GD:[12.1,-61.7],GE:[42,43.5],GF:[4,-53],GG:[49.5,-2.5],GH:[8,-1.2],GI:[36.1,-5.4],GM:[13.5,-16.5],GN:[11,-10],GP:[16.3,-61.5],GQ:[2,10],GR:[39,22],GT:[15.5,-90.3],GU:[13.4,144.8],GW:[12,-15],GY:[5,-59],HK:[22.3,114.2],HN:[15,-86.5],HR:[45.2,15.5],HT:[19,-72.3],HU:[47,20],ID:[-5,120],IE:[53,-8],IL:[31.5,34.8],IM:[54.2,-4.5],IN:[20,77],IQ:[33,44],IR:[32,53],IS:[65,-18],IT:[42.8,12.8],JE:[49.2,-2.1],JM:[18.1,-77.3],JO:[31,36],JP:[36,138],KE:[1,38],KG:[41,75],KH:[12.5,105],KP:[40,127],KR:[37,128],KW:[29.5,47.8],KY:[19.3,-81.3],KZ:[48,68],LA:[18,105],LB:[33.8,35.8],LC:[13.9,-61],LI:[47.2,9.6],LK:[7,81],LR:[6.5,-9.5],LS:[-29.5,28.5],LT:[56,24],LU:[49.8,6.2],LV:[57,25],LY:[25,17],MA:[32,-5],MC:[43.7,7.4],MD:[47,29],ME:[42.5,19.3],MG:[-20,47],MK:[41.5,22],ML:[17,-4],MM:[22,98],MN:[46,105],MO:[22.2,113.5],MQ:[14.6,-61],MR:[20,-12],MT:[35.9,14.4],MU:[-20.3,57.6],MV:[3.2,73],MW:[-13.5,34],MX:[23,-102],MY:[2.5,112.5],MZ:[-18.3,35],NA:[-22,17],NC:[-22.3,166.5],NE:[16,8],NG:[10,8],NI:[13,-85],NL:[52.5,5.8],NO:[62,10],NP:[28,84],NZ:[-42,174],OM:[21,57],PA:[9,-80],PE:[-10,-76],PF:[-17.7,-149.4],PG:[-6,147],PH:[13,122],PK:[30,70],PL:[52,20],PR:[18.2,-66.5],PS:[31.9,35.2],PT:[39.5,-8],PY:[-23,-58],QA:[25.5,51.3],RE:[-21.1,55.5],RO:[46,25],RS:[44,21],RU:[60,100],RW:[-2,30],SA:[25,45],SC:[-4.7,55.5],SD:[16,30],SE:[62,15],SG:[1.4,103.8],SI:[46.1,14.8],SK:[48.7,19.5],SL:[8.5,-11.8],SN:[14,-14],SO:[6,46],SR:[4,-56],SS:[7,30],SV:[13.8,-88.9],SY:[35,38],SZ:[-26.5,31.5],TD:[15,19],TG:[8,1.2],TH:[15,100],TJ:[39,71],TL:[-8.5,126],TM:[40,60],TN:[34,9],TR:[39,35],TT:[10.5,-61.3],TW:[23.5,121],TZ:[-6,35],UA:[49,32],UG:[1,32],US:[38,-97],UY:[-33,-56],UZ:[41,64],VC:[13.3,-61.2],VE:[8,-66],VG:[18.4,-64.6],VI:[18.3,-64.9],VN:[16,108],XK:[42.6,21],YE:[15,48],ZA:[-29,24],ZM:[-15,30],ZW:[-20,30],
    }

    const summaries = data.summary || []
    summaries.forEach(s => {
      const centroid = countryCentroids[s.code]
      if (!centroid) return

      const color = levelColors[s.level] || "#ffc107"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const intensity = Math.min(s.score / 100, 1)
      const pixelSize = 8 + intensity * 16

      // Pulsing ring for outage area
      const ring = dataSource.entities.add({
        id: `outage-ring-${s.code}`,
        position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 0),
        ellipse: {
          semiMinorAxis: 50000 + intensity * 300000,
          semiMajorAxis: 50000 + intensity * 300000,
          material: cesiumColor.withAlpha(0.06 + intensity * 0.08),
          outline: true,
          outlineColor: cesiumColor.withAlpha(0.2),
          outlineWidth: 1,
          height: 0,
        },
      })
      this._outageEntities.push(ring)

      // Center marker
      const entity = dataSource.entities.add({
        id: `outage-${s.code}`,
        position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 0),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(0.85),
          outlineColor: cesiumColor.withAlpha(0.4),
          outlineWidth: 3,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.5),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
        label: {
          text: `${s.code} ▼${s.score}`,
          font: "bold 12px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -18),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1.0, 1e7, 0),
        },
      })
      this._outageEntities.push(entity)
    })
  }

  GlobeController.prototype._clearOutageEntities = function() {
    const ds = this.getOutagesDataSource()
    this._outageEntities.forEach(e => ds.entities.remove(e))
    this._outageEntities = []
  }

  GlobeController.prototype.showOutageDetail = function(code) {
    const s = this._outageData.find(o => o.code === code)
    if (!s) return

    const levelColors = { critical: "#e040fb", severe: "#f44336", moderate: "#ff9800", minor: "#ffc107" }
    const color = levelColors[s.level] || "#ffc107"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-wifi" style="margin-right:6px;"></i>Internet Outage
      </div>
      <div class="detail-country">${this._escapeHtml(s.name || s.code)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Severity</span>
          <span class="detail-value" style="color:${color};">${s.level.toUpperCase()}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Score</span>
          <span class="detail-value">${s.score}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Country</span>
          <span class="detail-value">${s.code}</span>
        </div>
      </div>
      <a href="https://ioda.inetintel.cc.gatech.edu/country/${s.code}" target="_blank" rel="noopener" class="detail-track-btn">View on IODA →</a>
    `
    this.detailPanelTarget.style.display = ""
  }

  // ── Power Plants ────────────────────────────────────────────

  GlobeController.prototype.getPowerPlantsDataSource = function() { return getDataSource(this.viewer, this._ds, "power-plants") }

  GlobeController.prototype.togglePowerPlants = function() {
    this.powerPlantsVisible = this.hasPowerPlantsToggleTarget && this.powerPlantsToggleTarget.checked
    if (this.powerPlantsVisible) {
      this._ensurePowerPlantData().then(() => { this.renderPowerPlants(); this._updateThreatsPanel() })
      if (!this._ppCameraCb) {
        this._ppCameraCb = () => { if (this.powerPlantsVisible) this.renderPowerPlants() }
        this.viewer.camera.moveEnd.addEventListener(this._ppCameraCb)
      }
    } else {
      this._clearPowerPlantEntities()
      if (this._ppCameraCb) { this.viewer.camera.moveEnd.removeEventListener(this._ppCameraCb); this._ppCameraCb = null }
      if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = "none"
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._ensurePowerPlantData = async function() {
    if (this._powerPlantAll) return // already loaded
    this._toast("Loading power plants...")
    try {
      const resp = await fetch("/api/power_plants")
      if (!resp.ok) return
      const raw = await resp.json()
      // API returns arrays: [id, lat, lng, fuel, capacity, name, country_code]
      this._powerPlantAll = raw.map(r => ({
        id: r[0], lat: r[1], lng: r[2], fuel: r[3],
        capacity: r[4], name: r[5], country: r[6],
      }))
      console.log(`[PowerPlants] Loaded ${this._powerPlantAll.length} plants`)
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch power plants:", e)
    }
  }

  GlobeController.prototype.renderPowerPlants = function() {
    this._clearPowerPlantEntities()
    if (!this._powerPlantAll) return

    const Cesium = window.Cesium
    const dataSource = this.getPowerPlantsDataSource()
    const bounds = this.getViewportBounds()

    const fuelColors = {
      Coal: "#616161", Gas: "#ff9800", Oil: "#795548", Nuclear: "#fdd835",
      Hydro: "#42a5f5", Solar: "#ffca28", Wind: "#80cbc4", Biomass: "#8bc34a",
      Geothermal: "#e64a19", Waste: "#9e9e9e", Petcoke: "#424242",
      Cogeneration: "#ab47bc", Storage: "#00bcd4", Other: "#78909c",
    }

    // Filter to viewport, already sorted by capacity desc from API
    let visible = this._powerPlantAll
    if (bounds) {
      visible = visible.filter(p =>
        p.lat >= bounds.lamin && p.lat <= bounds.lamax &&
        p.lng >= bounds.lomin && p.lng <= bounds.lomax
      )
    }
    if (this.hasActiveFilter()) {
      visible = visible.filter(p => this.pointPassesFilter(p.lat, p.lng))
    }
    // Cap at 1500 entities for performance (largest first)
    visible = visible.slice(0, 1500)

    dataSource.entities.suspendEvents()
    visible.forEach(p => {
      const color = fuelColors[p.fuel] || "#78909c"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const cap = p.capacity || 1
      const pixelSize = Math.min(4 + Math.sqrt(cap) * 0.5, 18)

      const entity = dataSource.entities.add({
        id: `pp-${p.id}`,
        position: Cesium.Cartesian3.fromDegrees(p.lng, p.lat, 0),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(0.85),
          outlineColor: cesiumColor.withAlpha(0.3),
          outlineWidth: 1,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 8e6, 0.3),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
        label: {
          text: p.name,
          font: "12px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, -10),
          scaleByDistance: new Cesium.NearFarScalar(5e3, 1, 2e5, 0),
          translucencyByDistance: new Cesium.NearFarScalar(5e3, 1.0, 2e5, 0),
        },
      })
      this._powerPlantEntities.push(entity)

      // Cross-layer: attack warning ring if this country is under cyber attack
      if (this.trafficVisible && this._attackedCountries?.has(p.country)) {
        const atkRing = dataSource.entities.add({
          id: `pp-atk-${p.id}`,
          position: Cesium.Cartesian3.fromDegrees(p.lng, p.lat, 0),
          ellipse: {
            semiMinorAxis: 20000 + (p.capacity || 1) * 5,
            semiMajorAxis: 20000 + (p.capacity || 1) * 5,
            material: Cesium.Color.RED.withAlpha(0.06),
            outline: true,
            outlineColor: Cesium.Color.RED.withAlpha(0.35),
            outlineWidth: 1,
            height: 0,
          },
        })
        this._powerPlantEntities.push(atkRing)
      }
    })
    dataSource.entities.resumeEvents(); this._requestRender()
    this._powerPlantData = visible // for click lookups
  }

  GlobeController.prototype._clearPowerPlantEntities = function() {
    const ds = this._ds["power-plants"]
    if (ds) {
      ds.entities.suspendEvents()
      this._powerPlantEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents(); this._requestRender()
    }
    this._powerPlantEntities = []
  }

  GlobeController.prototype._updateThreatsPanel = function() {
    if (!this.hasThreatsContentTarget) return
    const attacked = this._attackedCountries
    if (!attacked?.size || !this._powerPlantAll?.length) {
      if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = "none"
      return
    }

    // Find all power plants in attacked countries
    const threatened = this._powerPlantAll
      .filter(p => attacked.has(p.country))
      .sort((a, b) => (b.capacity || 0) - (a.capacity || 0))
      .slice(0, 200)

    if (!threatened.length) {
      if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = "none"
      return
    }

    if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = ""
    if (this.hasThreatsCountTarget) {
      this.threatsCountTarget.textContent = `${threatened.length} target${threatened.length !== 1 ? "s" : ""}`
    }

    const pairs = this._trafficData?.attack_pairs || []
    const fuelColors = {
      Coal: "#616161", Gas: "#ff9800", Oil: "#795548", Nuclear: "#fdd835",
      Hydro: "#42a5f5", Solar: "#ffca28", Wind: "#80cbc4", Biomass: "#8bc34a",
      Geothermal: "#e64a19", Other: "#78909c",
    }

    // Group by country
    const byCountry = {}
    threatened.forEach(p => {
      if (!byCountry[p.country]) byCountry[p.country] = []
      byCountry[p.country].push(p)
    })

    const html = Object.entries(byCountry).map(([country, plants]) => {
      const countryAttacks = pairs.filter(p => p.target === country)
      const totalPct = countryAttacks.reduce((s, p) => s + (p.pct || 0), 0).toFixed(1)
      const origins = countryAttacks.map(p => p.origin_name || p.origin).join(", ")

      const plantRows = plants.slice(0, 15).map(p => {
        const color = fuelColors[p.fuel] || "#78909c"
        return `<div class="th-plant" data-action="click->globe#focusThreat" data-lat="${p.lat}" data-lng="${p.lng}" data-pp-id="${p.id}">
          <span class="th-fuel" style="color:${color}"><i class="fa-solid fa-bolt"></i></span>
          <span class="th-name">${this._escapeHtml(p.name)}</span>
          <span class="th-cap">${p.capacity ? p.capacity.toLocaleString() + " MW" : ""}</span>
          <span class="th-type" style="background:${color}20;color:${color}">${p.fuel}</span>
        </div>`
      }).join("")

      const moreCount = plants.length > 15 ? `<div class="th-more">+ ${plants.length - 15} more</div>` : ""

      return `<div class="th-country">
        <div class="th-country-header">
          <span class="th-country-name">${this._escapeHtml(country)}</span>
          <span class="th-attack-pct">${totalPct}% DDoS</span>
        </div>
        <div class="th-origins">from ${this._escapeHtml(origins)}</div>
        <div class="th-plants">${plantRows}${moreCount}</div>
      </div>`
    }).join("")

    this.threatsContentTarget.innerHTML = html
  }

  GlobeController.prototype.closeThreats = function() {
    if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = "none"
  }

  GlobeController.prototype.focusThreat = function(event) {
    const lat = parseFloat(event.currentTarget.dataset.lat)
    const lng = parseFloat(event.currentTarget.dataset.lng)
    if (isNaN(lat) || isNaN(lng)) return
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, 500000),
      duration: 1.0,
    })
    // Show detail if we have the plant data
    const ppId = event.currentTarget.dataset.ppId
    const pp = this._powerPlantData?.find(p => String(p.id) === ppId) ||
               this._powerPlantAll?.find(p => String(p.id) === ppId)
    if (pp) this.showPowerPlantDetail(pp)
  }

  GlobeController.prototype.showPowerPlantDetail = function(pp) {
    const fuelColors = {
      Coal: "#616161", Gas: "#ff9800", Oil: "#795548", Nuclear: "#fdd835",
      Hydro: "#42a5f5", Solar: "#ffca28", Wind: "#80cbc4", Biomass: "#8bc34a",
      Geothermal: "#e64a19", Other: "#78909c",
    }
    const color = fuelColors[pp.fuel] || "#78909c"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-plug" style="margin-right:6px;"></i>${this._escapeHtml(pp.name)}
      </div>
      <div class="detail-country">${this._escapeHtml(pp.country || "Unknown")}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Fuel</span>
          <span class="detail-value" style="color:${color};">${pp.fuel || "Unknown"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Capacity</span>
          <span class="detail-value">${pp.capacity ? pp.capacity.toLocaleString() + " MW" : "—"}</span>
        </div>
      </div>
      ${this.trafficVisible && this._attackedCountries?.has(pp.country) ? `
        <div style="margin-top:10px;padding:6px 8px;background:rgba(244,67,54,0.1);border:1px solid rgba(244,67,54,0.3);border-radius:4px;">
          <div style="font:600 9px var(--gt-mono);color:#f44336;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">⚠ CYBER ATTACK TARGET</div>
          ${(this._trafficData?.attack_pairs || []).filter(p => p.target === pp.country).map(p =>
            `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">${this._escapeHtml(p.origin_name)} → ${p.pct?.toFixed(1)}%</div>`
          ).join("")}
        </div>
      ` : ""}
    `
    this.detailPanelTarget.style.display = ""
  }

  // ── Conflict Events ───────────────────────────────────────────

  GlobeController.prototype.getConflictsDataSource = function() { return getDataSource(this.viewer, this._ds, "conflicts") }

  GlobeController.prototype.toggleConflicts = function() {
    this.conflictsVisible = this.hasConflictsToggleTarget && this.conflictsToggleTarget.checked
    if (this.conflictsVisible) {
      this.fetchConflicts()
    } else {
      this._clearConflictEntities()
      this._conflictData = []
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchConflicts = async function() {
    if (this._timelineActive) return
    this._toast("Loading conflicts...")
    try {
      const resp = await fetch("/api/conflict_events")
      if (!resp.ok) return
      this._conflictData = await resp.json()
      this._handleBackgroundRefresh(resp, "conflict-events", this._conflictData.length > 0, () => {
        if (this.conflictsVisible && !this._timelineActive) this.fetchConflicts()
      })
      this.renderConflicts()
      this._updateStats()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch conflict events:", e)
    }
  }

  GlobeController.prototype.renderConflicts = function() {
    this._clearConflictEntities()
    const Cesium = window.Cesium
    const dataSource = this.getConflictsDataSource()

    const typeColors = {
      1: "#f44336", // state-based
      2: "#ff9800", // non-state
      3: "#e040fb", // one-sided
    }

    this._conflictData.forEach(c => {
      if (this.hasActiveFilter() && !this.pointPassesFilter(c.lat, c.lng)) return

      const color = typeColors[c.type] || "#f44336"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const deaths = c.deaths || 0
      const pixelSize = Math.min(5 + Math.sqrt(deaths) * 2, 22)

      // Impact ring for higher-casualty events
      if (deaths >= 5) {
        const ring = dataSource.entities.add({
          id: `conf-ring-${c.id}`,
          position: Cesium.Cartesian3.fromDegrees(c.lng, c.lat, 0),
          ellipse: {
            semiMinorAxis: 5000 + deaths * 800,
            semiMajorAxis: 5000 + deaths * 800,
            material: cesiumColor.withAlpha(0.06),
            outline: true,
            outlineColor: cesiumColor.withAlpha(0.2),
            outlineWidth: 1,
            height: 0,
          },
        })
        this._conflictEntities.push(ring)
      }

      const entity = dataSource.entities.add({
        id: `conf-${c.id}`,
        position: Cesium.Cartesian3.fromDegrees(c.lng, c.lat, 0),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(0.85),
          outlineColor: cesiumColor.withAlpha(0.4),
          outlineWidth: 2,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 8e6, 0.4),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
        label: {
          text: `${c.conflict || c.country}`,
          font: "12px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, -12),
          scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 3e6, 0),
          translucencyByDistance: new Cesium.NearFarScalar(1e4, 1.0, 3e6, 0),
        },
      })
      this._conflictEntities.push(entity)
    })
  }

  GlobeController.prototype._clearConflictEntities = function() {
    const ds = this._ds["conflicts"]
    if (ds) this._conflictEntities.forEach(e => ds.entities.remove(e))
    this._conflictEntities = []
  }

  GlobeController.prototype.showConflictDetail = function(c) {
    const typeColors = { 1: "#f44336", 2: "#ff9800", 3: "#e040fb" }
    const color = typeColors[c.type] || "#f44336"
    const totalDeaths = c.deaths || 0

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-crosshairs" style="margin-right:6px;"></i>${this._escapeHtml(c.conflict || "Conflict Event")}
      </div>
      <div class="detail-country">${this._escapeHtml(c.country || "")} — ${this._escapeHtml(c.type_label)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Side A</span>
          <span class="detail-value" style="font-size:11px;">${this._escapeHtml(c.side_a || "—")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Side B</span>
          <span class="detail-value" style="font-size:11px;">${this._escapeHtml(c.side_b || "—")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Deaths</span>
          <span class="detail-value" style="color:${color};">${totalDeaths}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Civilian</span>
          <span class="detail-value">${c.deaths_civilians || 0}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Date</span>
          <span class="detail-value">${c.date_start || "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Location</span>
          <span class="detail-value" style="font-size:10px;">${this._escapeHtml(c.location || "—")}</span>
        </div>
      </div>
      ${c.headline ? `<div style="margin-top:8px;font:400 10px var(--gt-mono);color:var(--gt-text-dim);line-height:1.4;">${this._escapeHtml(c.headline)}</div>` : ""}
      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${c.lat}" data-lng="${c.lng}">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
      </button>
    `
    this.detailPanelTarget.style.display = ""
  }

  // ── Satellite-to-Ground Visibility ─────────────────────────

  GlobeController.prototype.getNotamsDataSource = function() { return getDataSource(this.viewer, this._ds, "notams") }

  GlobeController.prototype.toggleNotams = function() {
    this.notamsVisible = this.hasNotamsToggleTarget && this.notamsToggleTarget.checked
    if (this.notamsVisible) {
      this.fetchNotams()
      if (!this._notamCameraCb) {
        this._notamCameraCb = () => { if (this.notamsVisible) this.fetchNotams() }
        this.viewer.camera.moveEnd.addEventListener(this._notamCameraCb)
      }
    } else {
      this._clearNotamEntities()
      if (this._notamCameraCb) { this.viewer.camera.moveEnd.removeEventListener(this._notamCameraCb); this._notamCameraCb = null }
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchNotams = async function() {
    this._toast("Loading NOTAMs...")
    try {
      const bounds = this.getViewportBounds()
      let url = "/api/notams"
      if (bounds) {
        url += `?lamin=${bounds.lamin.toFixed(2)}&lamax=${bounds.lamax.toFixed(2)}&lomin=${bounds.lomin.toFixed(2)}&lomax=${bounds.lomax.toFixed(2)}`
      }
      const resp = await fetch(url)
      if (!resp.ok) return
      this._notamData = await resp.json()
      this.renderNotams()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch NOTAMs:", e)
    }
  }

  GlobeController.prototype.renderNotams = function() {
    this._clearNotamEntities()
    if (!this._notamData || this._notamData.length === 0) return

    const Cesium = window.Cesium
    const dataSource = this.getNotamsDataSource()
    dataSource.entities.suspendEvents()

    const reasonColors = {
      "VIP Movement": "#ff1744",
      "White House": "#ff1744",
      "US Capitol": "#ff1744",
      "Washington DC SFRA": "#ff5252",
      "Washington DC FRZ": "#ff1744",
      "Camp David": "#ff1744",
      "Wildfire": "#ff6d00",
      "Space Operations": "#7c4dff",
      "Sporting Event": "#00c853",
      "Security": "#ff9100",
      "Restricted Area": "#d50000",
      "Hazard": "#ffab00",
      "TFR": "#ef5350",
      "Nuclear Facility": "#ffea00",
      "Government": "#ff1744",
      "Military": "#d50000",
      "Conflict Zone": "#ff3d00",
      "Environmental": "#00e676",
      "Danger": "#ff6d00",
      "Prohibited": "#d50000",
      "Warning": "#ffab00",
    }

    this._notamData.forEach((n) => {
      const color = reasonColors[n.reason] || "#ef5350"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const radius = n.radius_m || 5556

      const altLow = (n.alt_low_ft || 0) * 0.3048
      const altHigh = Math.min((n.alt_high_ft || 18000) * 0.3048, 60000)

      const ellipse = dataSource.entities.add({
        id: `notam-${n.id}`,
        position: Cesium.Cartesian3.fromDegrees(n.lng, n.lat, 0),
        ellipse: {
          semiMinorAxis: radius,
          semiMajorAxis: radius,
          height: altLow,
          extrudedHeight: altHigh,
          material: cesiumColor.withAlpha(0.08),
          outline: true,
          outlineColor: cesiumColor.withAlpha(0.4),
          outlineWidth: 1,
        },
      })
      this._notamEntities.push(ellipse)

      const label = dataSource.entities.add({
        id: `notam-lbl-${n.id}`,
        position: Cesium.Cartesian3.fromDegrees(n.lng, n.lat, altHigh + 500),
        label: {
          text: `⛔ ${n.reason}`,
          font: "bold 11px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 4,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 5e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(1e4, 1.0, 5e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._notamEntities.push(label)
    })
    dataSource.entities.resumeEvents(); this._requestRender()

    this._checkFlightNotamProximity()
  }

  GlobeController.prototype._clearNotamEntities = function() {
    const ds = this._ds["notams"]
    if (ds) {
      ds.entities.suspendEvents()
      this._notamEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents(); this._requestRender()
    }
    this._notamEntities = []
    this._clearFlightNotamWarnings()
  }

  GlobeController.prototype._checkFlightNotamProximity = function() {
    if (!this.notamsVisible || !this._notamData?.length) return
    this._clearFlightNotamWarnings()

    const Cesium = window.Cesium
    const dataSource = this.getNotamsDataSource()
    this._notamFlightWarnings = []

    this.flightData.forEach((f, icao24) => {
      if (!f.latitude || !f.longitude) return

      for (const n of this._notamData) {
        const dist = haversineDistance(
          { lat: f.latitude, lng: f.longitude },
          { lat: n.lat, lng: n.lng }
        )
        const proximityThreshold = (n.radius_m || 5556) * 1.5

        if (dist <= proximityThreshold) {
          const warningEntity = dataSource.entities.add({
            id: `notam-warn-${icao24}`,
            position: Cesium.Cartesian3.fromDegrees(f.longitude, f.latitude, (f.baro_altitude || 0)),
            ellipse: {
              semiMinorAxis: 8000,
              semiMajorAxis: 8000,
              material: Cesium.Color.RED.withAlpha(0.15),
              outline: true,
              outlineColor: Cesium.Color.RED.withAlpha(0.6),
              outlineWidth: 2,
              height: (f.baro_altitude || 0) - 500,
              extrudedHeight: (f.baro_altitude || 0) + 500,
            },
          })
          this._notamFlightWarnings.push(warningEntity)
          break
        }
      }
    })
  }

  GlobeController.prototype._clearFlightNotamWarnings = function() {
    if (!this._notamFlightWarnings) return
    const ds = this._ds["notams"]
    if (ds) {
      this._notamFlightWarnings.forEach(e => ds.entities.remove(e))
    }
    this._notamFlightWarnings = []
  }

  GlobeController.prototype.showNotamDetail = function(n) {
    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#ef5350;">
        <i class="fa-solid fa-ban" style="margin-right:6px;"></i>${this._escapeHtml(n.reason)}
      </div>
      <div class="detail-country">${this._escapeHtml(n.id)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Radius</span>
          <span class="detail-value">${n.radius_nm} NM (${(n.radius_m / 1000).toFixed(1)} km)</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Altitude</span>
          <span class="detail-value">${n.alt_low_ft?.toLocaleString() || 'SFC'} – ${n.alt_high_ft?.toLocaleString()} ft</span>
        </div>
        ${n.effective_start ? `<div class="detail-field">
          <span class="detail-label">Effective</span>
          <span class="detail-value" style="font-size:9px;">${n.effective_start}</span>
        </div>` : ""}
      </div>
      <div style="margin-top:8px;font:400 10px var(--gt-mono);color:var(--gt-text-dim);line-height:1.4;">${this._escapeHtml(n.text)}</div>
    `
    this.detailPanelTarget.style.display = ""
  }
  // ── Internet Traffic (Cloudflare Radar) ─────────────────────

  GlobeController.prototype.getTrafficDataSource = function() { return getDataSource(this.viewer, this._ds, "traffic") }

  GlobeController.prototype.toggleTraffic = function() {
    this.trafficVisible = this.hasTrafficToggleTarget && this.trafficToggleTarget.checked
    if (this.trafficVisible) {
      this.fetchTraffic()
      if (this.hasTrafficArcControlsTarget) this.trafficArcControlsTarget.style.display = ""
    } else {
      this._clearTrafficEntities()
      this._trafficData = null
      if (this.hasTrafficArcControlsTarget) this.trafficArcControlsTarget.style.display = "none"
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.toggleTrafficArcs = function() {
    this.trafficArcsVisible = this.hasTrafficArcsToggleTarget && this.trafficArcsToggleTarget.checked
    if (!this.trafficArcsVisible) {
      this.trafficBlobsVisible = false
      if (this.hasTrafficBlobsToggleTarget) this.trafficBlobsToggleTarget.checked = false
      this._clearTrafficEntities()
      if (this._trafficData) this.renderTraffic()
    } else if (this._trafficData) {
      this._clearTrafficEntities()
      this.renderTraffic()
    }
  }

  GlobeController.prototype.toggleTrafficBlobs = function() {
    this.trafficBlobsVisible = this.hasTrafficBlobsToggleTarget && this.trafficBlobsToggleTarget.checked
    if (this.trafficBlobsVisible && !this.trafficArcsVisible) {
      this.trafficBlobsVisible = false
      if (this.hasTrafficBlobsToggleTarget) this.trafficBlobsToggleTarget.checked = false
      return
    }
    if (!this.trafficBlobsVisible) {
      this._stopTrafficBlobAnim()
      this._removeTrafficBlobEntities()
    } else if (this._trafficData) {
      this._clearTrafficEntities()
      this.renderTraffic()
    }
  }

  GlobeController.prototype.fetchTraffic = async function() {
    if (this._timelineActive) return
    this._toast("Loading internet traffic...")
    try {
      console.log("[Traffic] Fetching /api/internet_traffic ...")
      const resp = await fetch("/api/internet_traffic")
      console.log("[Traffic] Response status:", resp.status)
      if (!resp.ok) {
        console.warn("[Traffic] Non-OK response:", resp.status, resp.statusText)
        return
      }
      this._trafficData = await resp.json()
      const hasData = (this._trafficData.traffic?.length || 0) > 0 || (this._trafficData.attack_pairs?.length || 0) > 0
      this._handleBackgroundRefresh(resp, "internet-traffic", hasData, () => {
        if (this.trafficVisible && !this._timelineActive) this.fetchTraffic()
      })
      console.log("[Traffic] Got data:", this._trafficData.traffic?.length, "countries,", this._trafficData.attack_pairs?.length, "attack pairs")
      this.renderTraffic()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch internet traffic:", e)
    }
  }

  GlobeController.prototype.renderTraffic = function() {
    this._clearTrafficEntities()
    if (!this._trafficData) return

    const Cesium = window.Cesium
    const dataSource = this.getTrafficDataSource()
    dataSource.entities.suspendEvents()

    // Reuse outage country centroids (ISO-2 → [lat, lng])
    const CC = {
      AD:[42.5,1.5],AE:[24,54],AF:[33,65],AG:[17.1,-61.8],AL:[41,20],AM:[40,45],AO:[-12.5,18.5],AR:[-34,-64],AT:[47.5,13.5],AU:[-25,135],AW:[12.5,-70],AZ:[40.5,47.5],BA:[44,18],BB:[13.2,-59.5],BD:[24,90],BE:[50.8,4],BF:[13,-1.5],BG:[43,25],BH:[26,50.6],BI:[-3.5,30],BJ:[9.5,2.25],BM:[32.3,-64.8],BN:[4.5,114.7],BO:[-17,-65],BR:[-10,-55],BS:[25,-77.4],BT:[27.5,90.5],BW:[-22,24],BY:[53,28],BZ:[17.2,-88.5],CA:[60,-95],CD:[-2.5,23.5],CF:[7,21],CG:[-1,15],CH:[47,8],CI:[8,-5.5],CL:[-30,-71],CM:[6,12],CN:[35,105],CO:[4,-72],CR:[10,-84],CU:[22,-80],CV:[16,-24],CW:[12.2,-69],CY:[35,33],CZ:[49.75,15.5],DE:[51,9],DJ:[11.5,43],DK:[56,10],DO:[19,-70.7],DZ:[28,3],EC:[-2,-77.5],EE:[59,26],EG:[27,30],ER:[15,39],ES:[40,-4],ET:[8,38],FI:[64,26],FJ:[-18,179],FO:[62,-7],FR:[46,2],GA:[-1,11.8],GB:[54,-2],GD:[12.1,-61.7],GE:[42,43.5],GF:[4,-53],GG:[49.5,-2.5],GH:[8,-1.2],GI:[36.1,-5.4],GM:[13.5,-16.5],GN:[11,-10],GP:[16.3,-61.5],GQ:[2,10],GR:[39,22],GT:[15.5,-90.3],GU:[13.4,144.8],GW:[12,-15],GY:[5,-59],HK:[22.3,114.2],HN:[15,-86.5],HR:[45.2,15.5],HT:[19,-72.3],HU:[47,20],ID:[-5,120],IE:[53,-8],IL:[31.5,34.8],IM:[54.2,-4.5],IN:[20,77],IQ:[33,44],IR:[32,53],IS:[65,-18],IT:[42.8,12.8],JE:[49.2,-2.1],JM:[18.1,-77.3],JO:[31,36],JP:[36,138],KE:[1,38],KG:[41,75],KH:[12.5,105],KP:[40,127],KR:[37,128],KW:[29.5,47.8],KY:[19.3,-81.3],KZ:[48,68],LA:[18,105],LB:[33.8,35.8],LC:[13.9,-61],LI:[47.2,9.6],LK:[7,81],LR:[6.5,-9.5],LS:[-29.5,28.5],LT:[56,24],LU:[49.8,6.2],LV:[57,25],LY:[25,17],MA:[32,-5],MC:[43.7,7.4],MD:[47,29],ME:[42.5,19.3],MG:[-20,47],MK:[41.5,22],ML:[17,-4],MM:[22,98],MN:[46,105],MO:[22.2,113.5],MQ:[14.6,-61],MR:[20,-12],MT:[35.9,14.4],MU:[-20.3,57.6],MV:[3.2,73],MW:[-13.5,34],MX:[23,-102],MY:[2.5,112.5],MZ:[-18.3,35],NA:[-22,17],NC:[-22.3,166.5],NE:[16,8],NG:[10,8],NI:[13,-85],NL:[52.5,5.8],NO:[62,10],NP:[28,84],NZ:[-42,174],OM:[21,57],PA:[9,-80],PE:[-10,-76],PF:[-17.7,-149.4],PG:[-6,147],PH:[13,122],PK:[30,70],PL:[52,20],PR:[18.2,-66.5],PS:[31.9,35.2],PT:[39.5,-8],PY:[-23,-58],QA:[25.5,51.3],RE:[-21.1,55.5],RO:[46,25],RS:[44,21],RU:[60,100],RW:[-2,30],SA:[25,45],SC:[-4.7,55.5],SD:[16,30],SE:[62,15],SG:[1.4,103.8],SI:[46.1,14.8],SK:[48.7,19.5],SL:[8.5,-11.8],SN:[14,-14],SO:[6,46],SR:[4,-56],SS:[7,30],SV:[13.8,-88.9],SY:[35,38],SZ:[-26.5,31.5],TD:[15,19],TG:[8,1.2],TH:[15,100],TJ:[39,71],TL:[-8.5,126],TM:[40,60],TN:[34,9],TR:[39,35],TT:[10.5,-61.3],TW:[23.5,121],TZ:[-6,35],UA:[49,32],UG:[1,32],US:[38,-97],UY:[-33,-56],UZ:[41,64],VC:[13.3,-61.2],VE:[8,-66],VG:[18.4,-64.6],VI:[18.3,-64.9],VN:[16,108],XK:[42.6,21],YE:[15,48],ZA:[-29,24],ZM:[-15,30],ZW:[-20,30],
    }

    const traffic = this._trafficData.traffic || []
    const maxTraffic = traffic.length > 0 ? Math.max(...traffic.map(t => t.traffic || 0)) : 1

    // Traffic volume markers (blue-green gradient)
    traffic.forEach(t => {
      const centroid = CC[t.code]
      if (!centroid || !t.traffic) return

      const intensity = t.traffic / maxTraffic
      const pixelSize = 6 + intensity * 20
      // Blue (low) → green (high)
      const r = Math.round(30 * (1 - intensity))
      const g = Math.round(200 + 55 * intensity)
      const b = Math.round(220 * (1 - intensity) + 80)
      const color = Cesium.Color.fromBytes(r, g, b, 200)

      const entity = dataSource.entities.add({
        id: `traf-${t.code}`,
        position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 0),
        point: {
          pixelSize,
          color,
          outlineColor: color.withAlpha(0.3),
          outlineWidth: 3,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.5),
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
        },
        label: {
          text: `${t.code} ${t.traffic.toFixed(1)}%`,
          font: "12px JetBrains Mono, monospace",
          fillColor: color.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, -14),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1.0, 1e7, 0),
        },
      })
      this._trafficEntities.push(entity)

      // Attack indicator ring (red) if country is attack target
      if (t.attack_target > 0.5) {
        const atkIntensity = Math.min(t.attack_target / 20, 1)
        const atkColor = Cesium.Color.fromCssColorString("#f44336")
        const ring = dataSource.entities.add({
          id: `traf-atk-${t.code}`,
          position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 0),
          ellipse: {
            semiMinorAxis: 50000 + atkIntensity * 250000,
            semiMajorAxis: 50000 + atkIntensity * 250000,
            material: atkColor.withAlpha(0.06 + atkIntensity * 0.06),
            outline: true,
            outlineColor: atkColor.withAlpha(0.2 + atkIntensity * 0.2),
            outlineWidth: 1,
            height: 0,
          },
        })
        this._trafficEntities.push(ring)
      }
    })

    // DDoS attack arcs (origin → target) with labels and directional arrows
    const pairs = this._trafficData.attack_pairs || []

    // Build set of attacked country codes for cross-layer correlation
    this._attackedCountries = new Set()
    pairs.forEach(p => { if (p.pct > 0.5) this._attackedCountries.add(p.target) })

    // Re-render infra layers if visible to show attack highlighting
    if (this.powerPlantsVisible) this.renderPowerPlants()
    if (this.cablesVisible) this._refreshCableAttackHighlights()
    this._updateThreatsPanel()

    if (!this.trafficArcsVisible) {
      dataSource.entities.resumeEvents(); this._requestRender()
      return
    }

    pairs.forEach((p, idx) => {
      const originC = CC[p.origin]
      const targetC = CC[p.target]
      if (!originC || !targetC) return

      const pct = p.pct || 1
      const arcWidth = Math.max(2, pct * 0.4)
      const arcAlpha = Math.min(0.3 + pct * 0.02, 0.8)

      // Build a raised geodesic arc with multiple segments for smooth curve
      const oLat = originC[0] * Math.PI / 180, oLng = originC[1] * Math.PI / 180
      const tLat = targetC[0] * Math.PI / 180, tLng = targetC[1] * Math.PI / 180
      const SEGS = 40
      const arcPositions = []
      for (let i = 0; i <= SEGS; i++) {
        const f = i / SEGS
        // Spherical interpolation (SLERP on the sphere surface)
        const d = Math.acos(Math.sin(oLat)*Math.sin(tLat) + Math.cos(oLat)*Math.cos(tLat)*Math.cos(tLng-oLng))
        if (d < 0.001) break // same point
        const A = Math.sin((1-f)*d)/Math.sin(d)
        const B = Math.sin(f*d)/Math.sin(d)
        const x = A*Math.cos(oLat)*Math.cos(oLng) + B*Math.cos(tLat)*Math.cos(tLng)
        const y = A*Math.cos(oLat)*Math.sin(oLng) + B*Math.cos(tLat)*Math.sin(tLng)
        const z = A*Math.sin(oLat) + B*Math.sin(tLat)
        const lat = Math.atan2(z, Math.sqrt(x*x+y*y)) * 180/Math.PI
        const lng = Math.atan2(y, x) * 180/Math.PI
        // Raise the arc in the middle (parabolic lift)
        const lift = Math.sin(f * Math.PI) * (200000 + d * 1500000)
        arcPositions.push(Cesium.Cartesian3.fromDegrees(lng, lat, lift))
      }
      if (arcPositions.length < 2) return

      // Arc line — dimmer base trail
      const arcColor = Cesium.Color.fromCssColorString("#f44336").withAlpha(arcAlpha * 0.5)
      const arc = dataSource.entities.add({
        id: `traf-arc-${idx}`,
        polyline: {
          positions: arcPositions,
          width: arcWidth,
          material: new Cesium.PolylineGlowMaterialProperty({
            glowPower: 0.15,
            color: arcColor,
          }),
        },
      })
      this._trafficEntities.push(arc)

      // Animated attack blobs — 1 to 4 based on severity, staggered along path
      if (this.trafficBlobsVisible) {
        const blobCount = Math.min(4, Math.max(1, Math.ceil(pct / 5)))
        const speed = 0.3 + Math.min(pct * 0.01, 0.4) // 0.3–0.7 full-path per second
        const blobSize = Math.max(7, Math.min(16, 5 + pct * 0.3))
        const blobColor = Cesium.Color.fromCssColorString("#ff1744")
        const glowColor = Cesium.Color.fromCssColorString("#ff5252")

        for (let b = 0; b < blobCount; b++) {
          const blob = dataSource.entities.add({
            id: `traf-blob-${idx}-${b}`,
            position: arcPositions[0],
            point: {
              pixelSize: blobSize,
              color: blobColor.withAlpha(0.9),
              outlineColor: glowColor.withAlpha(0.4),
              outlineWidth: 3,
              disableDepthTestDistance: Number.POSITIVE_INFINITY,
              scaleByDistance: new Cesium.NearFarScalar(5e5, 1.2, 1e7, 0.4),
            },
          })
          this._trafficEntities.push(blob)
          // Store animation metadata on the entity for the RAF loop
          blob._blobArc = arcPositions
          blob._blobPhase = b / blobCount
          blob._blobSpeed = speed
        }
      }

      // Label at midpoint of arc
      const midPos = arcPositions[Math.floor(SEGS / 2)]
      const label = dataSource.entities.add({
        id: `traf-lbl-${idx}`,
        position: midPos,
        label: {
          text: `${p.origin} → ${p.target}  ${pct.toFixed(1)}%`,
          font: "11px JetBrains Mono, monospace",
          fillColor: Cesium.Color.fromCssColorString("#ff8a80"),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 4,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, -6),
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1, 1.2e7, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1.5e7, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._trafficEntities.push(label)
    })
    dataSource.entities.resumeEvents(); this._requestRender()

    // Blob animation is handled by the consolidated animate() loop
  }

  // Blob animation is now handled by the consolidated animate() loop

  GlobeController.prototype._clearTrafficEntities = function() {
    this._stopTrafficBlobAnim()
    const ds = this._ds["traffic"]
    if (ds) {
      ds.entities.suspendEvents()
      this._trafficEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents(); this._requestRender()
    }
    this._trafficEntities = []
    this._attackedCountries = null
    this._clearCableAttackHighlights()
    if (this.hasThreatsPanelTarget) this.threatsPanelTarget.style.display = "none"
  }

  GlobeController.prototype._stopTrafficBlobAnim = function() {
    if (this._trafficBlobRaf) {
      cancelAnimationFrame(this._trafficBlobRaf)
      this._trafficBlobRaf = null
    }
  }

  GlobeController.prototype._removeTrafficBlobEntities = function() {
    const ds = this._ds["traffic"]
    if (!ds) return
    const kept = []
    ds.entities.suspendEvents()
    for (const e of this._trafficEntities) {
      if (e._blobArc) {
        ds.entities.remove(e)
      } else {
        kept.push(e)
      }
    }
    ds.entities.resumeEvents(); this._requestRender()
    this._trafficEntities = kept
  }

  GlobeController.prototype.showTrafficDetail = function(code) {
    if (!this._trafficData) return
    const t = this._trafficData.traffic?.find(x => x.code === code)
    if (!t) return

    const pairs = this._trafficData.attack_pairs || []
    const inbound = pairs.filter(p => p.target === code)
    const outbound = pairs.filter(p => p.origin === code)

    let attackHtml = ""
    if (inbound.length > 0) {
      attackHtml += `<div style="margin-top:8px;font:500 9px var(--gt-mono);color:#f44336;letter-spacing:1px;text-transform:uppercase;">Attacks targeting</div>`
      attackHtml += inbound.map(p => `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">${this._escapeHtml(p.origin_name)} → ${p.pct?.toFixed(1)}%</div>`).join("")
    }
    if (outbound.length > 0) {
      attackHtml += `<div style="margin-top:8px;font:500 9px var(--gt-mono);color:#ff9800;letter-spacing:1px;text-transform:uppercase;">Attacks originating</div>`
      attackHtml += outbound.map(p => `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">→ ${this._escapeHtml(p.target_name)} ${p.pct?.toFixed(1)}%</div>`).join("")
    }

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#69f0ae;">
        <i class="fa-solid fa-globe" style="margin-right:6px;"></i>Internet Traffic
      </div>
      <div class="detail-country">${this._escapeHtml(t.name || t.code)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Traffic Share</span>
          <span class="detail-value" style="color:#69f0ae;">${t.traffic?.toFixed(2)}%</span>
        </div>
        ${t.attack_target > 0 ? `<div class="detail-field">
          <span class="detail-label">Attack Target</span>
          <span class="detail-value" style="color:#f44336;">${t.attack_target?.toFixed(2)}%</span>
        </div>` : ""}
        ${t.attack_origin > 0 ? `<div class="detail-field">
          <span class="detail-label">Attack Origin</span>
          <span class="detail-value" style="color:#ff9800;">${t.attack_origin?.toFixed(2)}%</span>
        </div>` : ""}
      </div>
      ${attackHtml}
      ${this._trafficData.recorded_at ? `<div style="margin-top:8px;font:400 9px var(--gt-mono);color:var(--gt-text-dim);">Updated: ${new Date(this._trafficData.recorded_at).toLocaleString()}</div>` : ""}
    `
    this.detailPanelTarget.style.display = ""
  }

  // ── Unified Timeline ─────────────────────────────────────────

}
