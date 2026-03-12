import { getDataSource } from "../utils"

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

    const civilColor = Cesium.Color.fromCssColorString("#ffd54f")
    const milColor = Cesium.Color.fromCssColorString("#ef5350")

    for (const [icao, ap] of entries) {
      const isMil = ap.military
      const color = isMil ? milColor : civilColor

      const entity = dataSource.entities.add({
        id: `airport-${icao}`,
        position: Cesium.Cartesian3.fromDegrees(ap.lng, ap.lat, 100),
        point: {
          pixelSize: isMil ? 5 : 6,
          color: color.withAlpha(0.9),
          outlineColor: color.withAlpha(0.35),
          outlineWidth: 4,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.2, 1e7, 0.4),
        },
        label: {
          text: icao,
          font: "12px JetBrains Mono, monospace",
          fillColor: color.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.8),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          pixelOffset: new Cesium.Cartesian2(0, 10),
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1, 5e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0),
        },
      })
      this._airportEntities.push(entity)
    }
  }

  GlobeController.prototype._clearAirportEntities = function() {
    const ds = this._ds["airports"]
    if (ds) this._airportEntities.forEach(e => ds.entities.remove(e))
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
    this._configureWebcamClustering(dataSource)
    return dataSource
  }

  GlobeController.prototype._configureWebcamClustering = function(dataSource) {
    if (this._webcamClusteringReady) return

    const Cesium = window.Cesium
    const clustering = dataSource.clustering
    clustering.enabled = true
    clustering.pixelRange = 32
    clustering.minimumClusterSize = 2
    clustering.clusterBillboards = false
    clustering.clusterLabels = true
    clustering.clusterPoints = true

    clustering.clusterEvent.addEventListener((clusteredEntities, cluster) => {
      const clusterId = { kind: "webcam-cluster", clusteredEntities }
      const size = clusteredEntities.length >= 50 ? 34 : clusteredEntities.length >= 15 ? 30 : 26

      cluster.billboard.show = false
      cluster.billboard.id = clusterId

      cluster.point.show = true
      cluster.point.id = clusterId
      cluster.point.pixelSize = size
      cluster.point.color = Cesium.Color.fromCssColorString("#ef6c00").withAlpha(0.92)
      cluster.point.outlineColor = Cesium.Color.WHITE.withAlpha(0.95)
      cluster.point.outlineWidth = 3
      cluster.point.disableDepthTestDistance = Number.POSITIVE_INFINITY

      cluster.label.show = true
      cluster.label.id = clusterId
      cluster.label.text = String(clusteredEntities.length)
      cluster.label.font = "700 13px JetBrains Mono, monospace"
      cluster.label.fillColor = Cesium.Color.WHITE
      cluster.label.outlineColor = Cesium.Color.BLACK.withAlpha(0.9)
      cluster.label.outlineWidth = 4
      cluster.label.style = Cesium.LabelStyle.FILL_AND_OUTLINE
      cluster.label.horizontalOrigin = Cesium.HorizontalOrigin.CENTER
      cluster.label.verticalOrigin = Cesium.VerticalOrigin.CENTER
      cluster.label.pixelOffset = new Cesium.Cartesian2(0, 0)
      cluster.label.disableDepthTestDistance = Number.POSITIVE_INFINITY
    })

    this._webcamClusteringReady = true
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

    this._earthquakeData.forEach(eq => {
      if (this.hasActiveFilter() && !this.pointPassesFilter(eq.lat, eq.lng)) return

      const mag = eq.mag || 0
      // Size and color by magnitude
      const t = Math.min(Math.max((mag - 2.5) / 5.5, 0), 1) // 2.5–8.0 range
      const pixelSize = 6 + t * 14
      const pulseScale = 2 + t * 4

      let color
      if (mag < 3) color = Cesium.Color.fromCssColorString("#66bb6a")
      else if (mag < 4) color = Cesium.Color.fromCssColorString("#ffa726")
      else if (mag < 5) color = Cesium.Color.fromCssColorString("#ff7043")
      else if (mag < 6) color = Cesium.Color.fromCssColorString("#ef5350")
      else color = Cesium.Color.fromCssColorString("#d50000")

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
        },
      })
      this._earthquakeEntities.push(ring)

      // Center point
      const entity = dataSource.entities.add({
        id: `eq-${eq.id}`,
        position: Cesium.Cartesian3.fromDegrees(eq.lng, eq.lat, 0),
        point: {
          pixelSize,
          color: color.withAlpha(0.85),
          outlineColor: color.withAlpha(0.4),
          outlineWidth: pulseScale,
        },
        label: {
          text: `M${mag.toFixed(1)}`,
          font: "13px JetBrains Mono, monospace",
          fillColor: Cesium.Color.WHITE.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.7),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, -pixelSize - 4),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 5e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0),
        },
      })
      this._earthquakeEntities.push(entity)
    })
  }

  GlobeController.prototype._clearEarthquakeEntities = function() {
    const ds = this._ds["events"]
    if (ds) this._earthquakeEntities.forEach(e => ds.entities.remove(e))
    this._earthquakeEntities = []
  }

  GlobeController.prototype.showEarthquakeDetail = function(eq) {
    const date = new Date(eq.time)
    const ago = this._timeAgo(date)
    const alertBadge = eq.alert ? `<span class="event-alert event-alert-${eq.alert}">${eq.alert.toUpperCase()}</span>` : ""
    const tsunamiBadge = eq.tsunami ? `<span class="event-alert event-alert-tsunami">TSUNAMI</span>` : ""

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign">M${eq.mag.toFixed(1)} Earthquake</div>
      <div class="detail-country">${eq.title}</div>
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
      ${typeof eq.url === "string" && eq.url.startsWith("http") ? `<a href="${eq.url}" target="_blank" rel="noopener" class="detail-track-btn">View on USGS</a>` : ""}
      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${eq.lat}" data-lng="${eq.lng}">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
      </button>
    `
    this.detailPanelTarget.style.display = ""

    // Fly to earthquake
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(eq.lng, eq.lat, 500000),
      duration: 1.5,
    })
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
        },
      })
      this._naturalEventEntities.push(ring)

      // Center point
      const entity = dataSource.entities.add({
        id: `eonet-${ev.id}`,
        position: Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 0),
        point: {
          pixelSize: 8,
          color: color.withAlpha(0.9),
          outlineColor: color.withAlpha(0.35),
          outlineWidth: 3,
        },
        label: {
          text: ev.title.length > 30 ? ev.title.substring(0, 28) + "…" : ev.title,
          font: "12px JetBrains Mono, monospace",
          fillColor: Cesium.Color.WHITE.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.7),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, -14),
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1, 5e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(5e4, 1, 8e6, 0),
        },
      })
      this._naturalEventEntities.push(entity)
    })
  }

  GlobeController.prototype._clearNaturalEventEntities = function() {
    const ds = this._ds["events"]
    if (ds) this._naturalEventEntities.forEach(e => ds.entities.remove(e))
    this._naturalEventEntities = []
  }

  GlobeController.prototype.showNaturalEventDetail = function(ev) {
    const catInfo = this.eonetCategoryIcons[ev.categoryId] || { icon: "circle-exclamation", color: "#78909c" }
    const date = ev.date ? new Date(ev.date) : null
    const ago = date ? this._timeAgo(date) : "—"
    const magStr = ev.magnitudeValue ? `${ev.magnitudeValue} ${ev.magnitudeUnit || ""}` : "—"
    const sourceLinks = (ev.sources || [])
      .filter(s => typeof s.url === "string" && s.url.startsWith("http"))
      .map(s => `<a href="${s.url}" target="_blank" rel="noopener" class="event-source-link">${s.id}</a>`)
      .join(" ")

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign"><i class="fa-solid fa-${catInfo.icon}" style="color: ${catInfo.color};"></i> ${ev.categoryTitle}</div>
      <div class="detail-country">${ev.title}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Category</span>
          <span class="detail-value">${ev.categoryTitle}</span>
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
      ${typeof ev.link === "string" && ev.link.startsWith("http") ? `<a href="${ev.link}" target="_blank" rel="noopener" class="detail-track-btn">View on NASA EONET</a>` : ""}
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
    if (this.hasActiveFilter()) {
      const bounds = this.getFilterBounds()
      if (bounds) {
        const latPad = Math.max((bounds.lamax - bounds.lamin) * 0.1, 0.15)
        const lngPad = Math.max((bounds.lomax - bounds.lomin) * 0.1, 0.15)
        const wideFilter = (bounds.lamax - bounds.lamin) > 8 || (bounds.lomax - bounds.lomin) > 8
        return {
          query: [
            `north=${Math.min(bounds.lamax + latPad, 85).toFixed(4)}`,
            `south=${Math.max(bounds.lamin - latPad, -85).toFixed(4)}`,
            `east=${Math.min(bounds.lomax + lngPad, 180).toFixed(4)}`,
            `west=${Math.max(bounds.lomin - lngPad, -180).toFixed(4)}`,
          ].join("&"),
          realtimeLimit: wideFilter ? 35 : 25,
          windyLimit: wideFilter ? 90 : 70,
        }
      }
    }

    const bbox = this._getViewportBbox()

    if (bbox && center.height > 300000) {
      const latPad = Math.max((bbox.north - bbox.south) * 0.15, 0.25)
      const lngPad = Math.max((bbox.east - bbox.west) * 0.15, 0.25)
      const wideView = center.height > 1500000
      return {
        query: [
          `north=${Math.min(bbox.north + latPad, 85).toFixed(4)}`,
          `south=${Math.max(bbox.south - latPad, -85).toFixed(4)}`,
          `east=${Math.min(bbox.east + lngPad, 180).toFixed(4)}`,
          `west=${Math.max(bbox.west - lngPad, -180).toFixed(4)}`,
        ].join("&"),
        realtimeLimit: wideView ? 40 : 30,
        windyLimit: wideView ? 100 : 80,
      }
    }

    const radiusKm = Math.min(Math.max(Math.round(center.height / 5000), 20), 100)
    return {
      query: `lat=${center.lat.toFixed(4)}&lng=${center.lng.toFixed(4)}&radius=${radiusKm}`,
      realtimeLimit: 20,
      windyLimit: 50,
    }
  }

  GlobeController.prototype.fetchWebcams = async function() {
    if (!this.camerasVisible) return
    const center = this._getViewCenter()
    if (!center) return
    const fetchId = ++this._webcamFetchToken
    const plan = this._buildWebcamFetchPlan(center)
    const baseUrl = `/api/webcams?${plan.query}`

    // Replace stale webcams when the viewport changes materially.
    this._webcamData = []
    this.renderWebcams()

    this._toast("Loading live cameras...")

    // Phase 1: fetch real-time sources first (YouTube + NYC DOT).
    try {
      const rtResp = await fetch(`${baseUrl}&sources=youtube,nycdot&limit=${plan.realtimeLimit}`)
      if (fetchId !== this._webcamFetchToken) return
      if (rtResp.ok) {
        const rtData = await rtResp.json()
        if (fetchId !== this._webcamFetchToken) return
        const rtCams = rtData.webcams || []
        if (rtCams.length > 0) {
          this._mergeWebcams(rtCams)
          this.renderWebcams()
          this._updateStats()
        }
      }
    } catch (e) { console.warn("Real-time webcam fetch failed:", e) }

    // Phase 2: fetch Windy (periodic/timelapse) using a broader limit.
    this._toast("Loading more cameras...")
    try {
      const wResp = await fetch(`${baseUrl}&sources=windy&limit=${plan.windyLimit}`)
      if (fetchId !== this._webcamFetchToken) return
      if (wResp.ok) {
        const wData = await wResp.json()
        if (fetchId !== this._webcamFetchToken) return
        const wCams = wData.webcams || []
        if (wCams.length > 0) {
          this._mergeWebcams(wCams)
          this.renderWebcams()
          this._updateStats()
        }
      }
    } catch (e) { console.warn("Windy webcam fetch failed:", e) }

    if (fetchId === this._webcamFetchToken) {
      this._webcamLastFetchCenter = center
      this._toastHide()
    }
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
      playerUrl: this._extractWindyUrl(w.player?.day, "embed") || this._extractWindyUrl(w.player?.live, "embed"),
      playerLink: this._extractWindyUrl(w.player?.day) || this._extractWindyUrl(w.player?.live) || (typeof w.url === "string" ? w.url : null),
      videoId: w.videoId || null,
      channelTitle: w.channelTitle || null,
      lastUpdated: w.lastUpdatedOn,
      viewCount: w.viewCount,
    }
  }

  GlobeController.prototype._mergeWebcams = function(raw) {
    const newCams = raw.map(w => this._normalizeWebcam(w)).filter(w =>
      w.lat != null && w.lng != null && Number.isFinite(w.lat) && Number.isFinite(w.lng)
    )
    const existingIds = new Set(this._webcamData.map(w => w.id))
    const added = newCams.filter(w => !existingIds.has(w.id))
    this._webcamData = [...this._webcamData, ...added]
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
    dataSource.clustering.enabled = visibleCams.length >= 25

    visibleCams.forEach(w => {
      const realtime = w.source === "youtube" || w.source === "nycdot"
      const icon = realtime
        ? (this._webcamIconRT || (this._webcamIconRT = this._makeWebcamIcon("#ff4444")))
        : w.live
          ? (this._webcamIconLive || (this._webcamIconLive = this._makeWebcamIcon("#4caf50")))
          : (this._webcamIcon || (this._webcamIcon = this._makeWebcamIcon("#29b6f6")))
      const labelPrefix = w.source === "nycdot" ? "🚦 " : w.source === "youtube" ? "▶ " : ""
      const pointColor = realtime
        ? Cesium.Color.fromCssColorString("#ff4444")
        : w.live
          ? Cesium.Color.fromCssColorString("#4caf50")
          : Cesium.Color.fromCssColorString("#29b6f6")
      const entity = dataSource.entities.add({
        id: `cam-${w.id}`,
        position: Cesium.Cartesian3.fromDegrees(w.lng, w.lat, 300),
        properties: {
          webcamId: w.id,
        },
        point: {
          pixelSize: realtime ? 9 : 8,
          color: pointColor.withAlpha(0.9),
          outlineColor: Cesium.Color.WHITE.withAlpha(0.85),
          outlineWidth: 2,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.1, 1e7, 0.45),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          heightReference: Cesium.HeightReference.NONE,
        },
        billboard: {
          image: icon,
          scale: 0.7,
          scaleByDistance: new Cesium.NearFarScalar(500, 1.2, 5e6, 0.4),
          distanceDisplayCondition: new Cesium.DistanceDisplayCondition(0, 6e6),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          heightReference: Cesium.HeightReference.NONE,
        },
        label: {
          text: labelPrefix + (w.title.length > 25 ? w.title.substring(0, 23) + "…" : w.title),
          font: "12px JetBrains Mono, monospace",
          fillColor: Cesium.Color.WHITE.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.6),
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          pixelOffset: new Cesium.Cartesian2(0, -14),
          scaleByDistance: new Cesium.NearFarScalar(500, 1, 3e6, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(500, 1, 1.5e6, 0),
          distanceDisplayCondition: new Cesium.DistanceDisplayCondition(0, 1200000),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          heightReference: Cesium.HeightReference.NONE,
        },
      })
      this._webcamEntities.push(entity)
      this._webcamEntityMap.set(entity.id, w)
    })

    this._requestRender()
  }

  GlobeController.prototype._clearWebcamEntities = function() {
    const ds = this._ds["webcams"]
    if (ds) this._webcamEntities.forEach(e => ds.entities.remove(e))
    this._webcamEntities = []
    this._webcamEntityMap.clear()
    this._requestRender()
  }

  GlobeController.prototype.zoomToWebcamCluster = function(clusteredEntities) {
    const Cesium = window.Cesium
    const positions = []

    for (const entity of clusteredEntities) {
      const position = entity.position?.getValue?.(Cesium.JulianDate.now())
      if (position) positions.push(position)
    }

    if (positions.length === 0) return

    try {
      const sphere = Cesium.BoundingSphere.fromPoints(positions)
      this.viewer.camera.flyToBoundingSphere(sphere, {
        duration: 1.2,
        offset: new Cesium.HeadingPitchRange(0, -0.9, Math.max(sphere.radius * 2.5, 15000)),
      })
    } catch (error) {
      console.warn("Webcam cluster zoom failed:", error)
    }
  }

  GlobeController.prototype.showWebcamDetail = function(cam) {
    // Stop any existing auto-refresh
    if (this._webcamRefreshInterval) { clearInterval(this._webcamRefreshInterval); this._webcamRefreshInterval = null }

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
    const thumbUrl = cam.thumbnail ? `${cam.thumbnail}${cam.source === "nycdot" ? "?t=" + Date.now() : ""}` : null

    const watchUrl = cam.source === "youtube" && cam.videoId
      ? `https://www.youtube.com/watch?v=${cam.videoId}`
      : cam.source === "nycdot"
        ? `https://webcams.nyctmc.org/map`
        : (typeof cam.playerLink === "string" && cam.playerLink.startsWith("http") ? cam.playerLink : `https://www.windy.com/webcams/${cam.id}`)

    let thumbHtml
    if (cam.source === "youtube" && cam.videoId && thumbUrl) {
      thumbHtml = `<a class="webcam-thumb" href="${watchUrl}" target="_blank" rel="noopener" style="position:relative;display:block;">
        <img id="webcam-detail-img" src="${thumbUrl}" alt="${this._escapeHtml(cam.title)}" loading="lazy" style="width:100%;border-radius:4px;">
        <span class="detail-track-btn" style="position:absolute;left:12px;bottom:12px;margin:0;">
          <i class="fa-solid fa-play"></i> Watch on YouTube
        </span>
      </a>`
    } else if (cam.source === "youtube" && cam.videoId) {
      thumbHtml = `<a class="webcam-thumb detail-track-btn" href="${watchUrl}" target="_blank" rel="noopener">
        <i class="fa-solid fa-play"></i> Watch on YouTube
      </a>`
    } else if (thumbUrl) {
      thumbHtml = `<div class="webcam-thumb"><img id="webcam-detail-img" src="${thumbUrl}" alt="${this._escapeHtml(cam.title)}" loading="lazy" style="width:100%;border-radius:4px;"></div>`
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
      <a href="${watchUrl}" target="_blank" rel="noopener" class="detail-track-btn"><i class="fa-solid fa-play"></i> Watch Live</a>
    `
    this.detailPanelTarget.style.display = ""

    // Auto-refresh DOT camera images every 5 seconds
    if (cam.source === "nycdot" && cam.thumbnail) {
      this._webcamRefreshInterval = setInterval(() => {
        const img = document.getElementById("webcam-detail-img")
        if (img) img.src = `${cam.thumbnail}?t=${Date.now()}`
      }, 5000)
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
