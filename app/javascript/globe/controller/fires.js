import { getDataSource, cachedColor } from "../utils"

const FIRE_CLUSTER_HEIGHT_TIERS = [
  { minHeight: 16_000_000, cellSize: 7.0 },
  { minHeight: 10_000_000, cellSize: 5.0 },
  { minHeight: 6_000_000, cellSize: 3.2 },
  { minHeight: 3_000_000, cellSize: 1.75 },
]

const FIRE_CLUSTER_MIN_POINTS = 40
const FIRE_DENSE_CLUSTER_THRESHOLDS = [
  { minHeight: 2_000_000, minVisible: 96, cellSize: 1.1 },
  { minHeight: 1_200_000, minVisible: 60, cellSize: 0.75 },
  { minHeight: 750_000, minVisible: 40, cellSize: 0.45 },
]
const FIRE_RAW_RENDER_TIERS = [
  { minHeight: 12_000_000, maxPoints: 70, cellSize: 1.25 },
  { minHeight: 6_000_000, maxPoints: 90, cellSize: 0.8 },
  { minHeight: 3_000_000, maxPoints: 110, cellSize: 0.5 },
  { minHeight: 1_500_000, maxPoints: 130, cellSize: 0.3 },
  { minHeight: 750_000, maxPoints: 160, cellSize: 0.18 },
  { minHeight: 0, maxPoints: 220, cellSize: 0.1 },
]

export function applyFiresMethods(GlobeController) {

  GlobeController.prototype.getFiresDataSource = function() { return getDataSource(this.viewer, this._ds, "fires") }

  GlobeController.prototype.toggleFireHotspots = function() {
    this.fireHotspotsVisible = this.hasFireHotspotsToggleTarget && this.fireHotspotsToggleTarget.checked
    this.fireClustersVisible = !this.hasFireClustersToggleTarget || this.fireClustersToggleTarget.checked
    if (this.fireHotspotsVisible) {
      this.fetchFireHotspots()
    } else {
      this._fireHotspotFetchToken += 1
      this._clearFireHotspotEntities()
      this._fireHotspotData = []
      this._fireHotspotClusterData = []
    }
    this._startFiresRefresh()
    this._updateStats()
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.toggleFireClusters = function() {
    this.fireClustersVisible = !this.hasFireClustersToggleTarget || this.fireClustersToggleTarget.checked
    if (this.fireHotspotsVisible && this._fireHotspotData.length > 0) this.renderFireHotspots()
    this._savePrefs()
  }

  GlobeController.prototype._startFiresRefresh = function() {
    if (this._firesInterval) clearInterval(this._firesInterval)
    if (this.fireHotspotsVisible) {
      this._firesInterval = setInterval(() => {
        if (this.fireHotspotsVisible && !this._timelineActive) this.fetchFireHotspots()
      }, 600000) // refresh every 10 min
    }
  }

  GlobeController.prototype.fetchFireHotspots = async function() {
    if (this._timelineActive) return
    const fetchToken = ++this._fireHotspotFetchToken
    this._toast("Loading fire hotspots...")
    try {
      const resp = await fetch("/api/fire_hotspots")
      if (fetchToken !== this._fireHotspotFetchToken || !this.fireHotspotsVisible) {
        this._toastHide()
        return
      }
      if (!resp.ok) {
        this._toastHide()
        return
      }
      const raw = await resp.json()
      if (fetchToken !== this._fireHotspotFetchToken || !this.fireHotspotsVisible) {
        this._toastHide()
        return
      }
      // API returns arrays: [id, lat, lng, brightness, confidence, satellite, instrument, frp, daynight, time, strike]
      this._fireHotspotData = raw.map(r => ({
        id: r[0], lat: r[1], lng: r[2], brightness: r[3],
        confidence: r[4], satellite: r[5], instrument: r[6],
        frp: r[7], daynight: r[8], time: r[9], strike: r[10] === 1,
      }))
      this._fireHotspotClusterData = []
      this._handleBackgroundRefresh(resp, "fire-hotspots", this._fireHotspotData.length > 0, () => {
        if (this.fireHotspotsVisible && !this._timelineActive) this.fetchFireHotspots()
      })
      this.renderFireHotspots()
      this._markFresh("fireHotspots")
      this._updateStats()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch fire hotspots:", e)
      this._toastHide()
    }
  }

  GlobeController.prototype.renderFireHotspots = function() {
    if (!this.fireHotspotsVisible) {
      this._clearFireHotspotEntities()
      this._fireHotspotClusterData = []
      return
    }
    this._clearFireHotspotEntities()
    this._fireHotspotClusterData = []
    const bounds = this.getViewportBounds()
    const visibleHotspots = []

    this._fireHotspotData.forEach(f => {
      if (bounds && (f.lat < bounds.lamin || f.lat > bounds.lamax || f.lng < bounds.lomin || f.lng > bounds.lomax)) return
      if (this.hasActiveFilter && this.hasActiveFilter() && !this.pointPassesFilter(f.lat, f.lng)) return
      visibleHotspots.push(f)
    })

    if (visibleHotspots.length === 0) {
      this._requestRender()
      return
    }

    const dataSource = this.getFiresDataSource()
    const clusterCellSize = this.fireClustersVisible ? this._fireClusterCellSize(visibleHotspots.length) : 0
    const useClusters = clusterCellSize > 0 && visibleHotspots.length >= FIRE_CLUSTER_MIN_POINTS
    const hotspotsToRender = useClusters
      ? visibleHotspots
      : this._selectFireHotspotsForRender(visibleHotspots)

    dataSource.entities.suspendEvents()
    if (useClusters) {
      this._fireHotspotClusterData = this._clusterFireHotspots(visibleHotspots, clusterCellSize)
      this._fireHotspotClusterData.forEach(cluster => this._renderFireCluster(dataSource, cluster))
    } else {
      hotspotsToRender.forEach(f => this._renderFireHotspot(dataSource, f))
    }
    dataSource.entities.resumeEvents()

    this._requestRender()
  }

  GlobeController.prototype._clearFireHotspotEntities = function() {
    const ds = this._ds["fires"]
    if (ds) {
      ds.entities.suspendEvents()
      this._fireHotspotEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
      this._requestRender()
    }
    this._fireHotspotEntities = []
  }

  GlobeController.prototype._fireClusterCellSize = function(visibleCount = 0) {
    const height = this.viewer?.camera?.positionCartographic?.height || 0
    const hasFilter = this.hasActiveFilter && this.hasActiveFilter()

    if (hasFilter) {
      if (height >= 14_000_000) return 4.0
      if (height >= 8_000_000) return 2.5
      if (height >= 4_000_000) return 1.25
      const denseTier = FIRE_DENSE_CLUSTER_THRESHOLDS.find(entry =>
        height >= entry.minHeight && visibleCount >= entry.minVisible
      )
      return denseTier ? denseTier.cellSize : 0
    }

    const tier = FIRE_CLUSTER_HEIGHT_TIERS.find(entry => height >= entry.minHeight)
    if (tier) return tier.cellSize

    const denseTier = FIRE_DENSE_CLUSTER_THRESHOLDS.find(entry =>
      height >= entry.minHeight && visibleCount >= entry.minVisible
    )
    return denseTier ? denseTier.cellSize : 0
  }

  GlobeController.prototype._selectFireHotspotsForRender = function(hotspots) {
    const { cellSize, maxPoints } = this._fireRawRenderConfig()
    return this._thinFireHotspots(hotspots, cellSize).slice(0, maxPoints)
  }

  GlobeController.prototype._fireRawRenderConfig = function() {
    const height = this.viewer?.camera?.positionCartographic?.height || 0
    const hasFilter = this.hasActiveFilter && this.hasActiveFilter()
    const tier = FIRE_RAW_RENDER_TIERS.find(entry => height >= entry.minHeight) || FIRE_RAW_RENDER_TIERS[FIRE_RAW_RENDER_TIERS.length - 1]

    if (!hasFilter) return tier

    return {
      cellSize: Math.max(0.05, tier.cellSize * 0.65),
      maxPoints: Math.round(tier.maxPoints * 1.35),
    }
  }

  GlobeController.prototype._thinFireHotspots = function(hotspots, cellSize) {
    const ranked = [...hotspots].sort((a, b) => this._firePriorityScore(b) - this._firePriorityScore(a))
    if (!cellSize || ranked.length <= 1) return ranked

    const cells = new Map()
    ranked.forEach(f => {
      const row = Math.floor((f.lat + 90) / cellSize)
      const col = Math.floor((f.lng + 180) / cellSize)
      const key = `${row}:${col}`
      if (!cells.has(key)) cells.set(key, f)
    })

    return [...cells.values()]
  }

  GlobeController.prototype._renderFireHotspot = function(dataSource, f) {
    const Cesium = window.Cesium
    const frp = f.frp || 1
    const color = this._fireHotspotColor(f)
    const pixelSize = f.strike
      ? Math.min(4 + Math.sqrt(frp) * 0.36, 8)
      : Math.min(1.75 + Math.sqrt(frp) * 0.2, 4.8)

    if (this._isHighConfidenceFire(f) && frp > 60) {
      const ring = dataSource.entities.add({
        id: `fire-ring-${f.id}`,
        position: Cesium.Cartesian3.fromDegrees(f.lng, f.lat, 0),
        ellipse: {
          semiMinorAxis: Math.min(900 + frp * 14, 3600),
          semiMajorAxis: Math.min(900 + frp * 14, 3600),
          material: color.withAlpha(0.025),
          outline: true,
          outlineColor: color.withAlpha(0.08),
          outlineWidth: 0.5,
          height: 0,
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._fireHotspotEntities.push(ring)
    }

    const entity = dataSource.entities.add({
      id: `fire-${f.id}`,
      position: Cesium.Cartesian3.fromDegrees(f.lng, f.lat, 10),
      point: {
        pixelSize,
        color: color.withAlpha(0.72),
        outlineColor: color.withAlpha(0.12),
        outlineWidth: 0.6,
        scaleByDistance: new Cesium.NearFarScalar(1e5, 1.0, 8e6, 0.22),
        heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    })
    this._fireHotspotEntities.push(entity)
  }

  GlobeController.prototype._renderFireCluster = function(dataSource, cluster) {
    const Cesium = window.Cesium
    const lead = cluster.lead || {}
    const color = this._fireHotspotColor(lead)
    const pixelSize = Math.min(
      4.5 + Math.log2(cluster.count + 1) * 2.05 + Math.sqrt(cluster.maxFrp || 1) * 0.08,
      cluster.strikeCount > 0 ? 13 : 11
    )
    const labelThreshold = cluster.cellSize >= 4 ? 40 : cluster.cellSize >= 2.5 ? 28 : cluster.cellSize >= 1 ? 18 : 14
    const labelText = cluster.count >= labelThreshold || cluster.strikeCount > 0 ? `${cluster.count}` : ""
    const ringRadius = Math.min(
      5_000 + cluster.count * 320 + cluster.cellSize * 6_000 + (cluster.maxFrp || 0) * 18,
      42_000
    )

    if (cluster.count >= 14 || cluster.strikeCount > 1 || cluster.maxFrp > 55) {
      const ring = dataSource.entities.add({
        id: `fire-cluster-ring-${cluster.id}`,
        position: Cesium.Cartesian3.fromDegrees(cluster.lng, cluster.lat, 0),
        ellipse: {
          semiMinorAxis: ringRadius,
          semiMajorAxis: ringRadius,
          material: color.withAlpha(cluster.strikeCount > 0 ? 0.05 : 0.02),
          outline: true,
          outlineColor: color.withAlpha(cluster.strikeCount > 0 ? 0.14 : 0.08),
          outlineWidth: 0.6,
          height: 0,
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._fireHotspotEntities.push(ring)
    }

    const entity = dataSource.entities.add({
      id: `fire-cluster-${cluster.id}`,
      position: Cesium.Cartesian3.fromDegrees(cluster.lng, cluster.lat, 20),
      point: {
        pixelSize,
        color: color.withAlpha(0.8),
        outlineColor: color.withAlpha(0.14),
        outlineWidth: 0.9,
        scaleByDistance: new Cesium.NearFarScalar(1e5, 1.05, 1.2e7, 0.32),
        heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      label: labelText ? {
        text: labelText,
        font: "11px JetBrains Mono, monospace",
        fillColor: Cesium.Color.WHITE.withAlpha(0.82),
        outlineColor: Cesium.Color.BLACK.withAlpha(0.8),
        outlineWidth: 2,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        pixelOffset: new Cesium.Cartesian2(0, -(pixelSize + 8)),
        horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
        scaleByDistance: new Cesium.NearFarScalar(1e5, 0.95, 9e6, 0.25),
        translucencyByDistance: new Cesium.NearFarScalar(1e5, 0.95, 9e6, 0.0),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      } : undefined,
    })
    this._fireHotspotEntities.push(entity)
  }

  GlobeController.prototype._clusterFireHotspots = function(hotspots, cellSize) {
    const cells = new Map()

    hotspots.forEach(f => {
      const row = Math.floor((f.lat + 90) / cellSize)
      const col = Math.floor((f.lng + 180) / cellSize)
      const key = `${row}:${col}`

      if (!cells.has(key)) {
        cells.set(key, {
          key,
          latSum: 0,
          lngSum: 0,
          count: 0,
          maxFrp: 0,
          maxBrightness: 0,
          strikeCount: 0,
          highConfidenceCount: 0,
          latestTime: 0,
          satellites: new Map(),
          lead: null,
        })
      }

      const cell = cells.get(key)
      cell.latSum += f.lat
      cell.lngSum += f.lng
      cell.count += 1
      cell.maxFrp = Math.max(cell.maxFrp, f.frp || 0)
      cell.maxBrightness = Math.max(cell.maxBrightness, f.brightness || 0)
      cell.latestTime = Math.max(cell.latestTime, f.time || 0)
      if (f.strike) cell.strikeCount += 1
      if (this._isHighConfidenceFire(f)) cell.highConfidenceCount += 1

      const sat = f.satellite || "Unknown"
      cell.satellites.set(sat, (cell.satellites.get(sat) || 0) + 1)

      if (!cell.lead || this._firePriorityScore(f) > this._firePriorityScore(cell.lead)) {
        cell.lead = f
      }
    })

    return [...cells.values()]
      .map(cell => ({
        lat: cell.latSum / cell.count,
        lng: cell.lngSum / cell.count,
        count: cell.count,
        maxFrp: cell.maxFrp,
        maxBrightness: cell.maxBrightness,
        strikeCount: cell.strikeCount,
        highConfidenceCount: cell.highConfidenceCount,
        latestTime: cell.latestTime,
        lead: cell.lead,
        cellSize,
        satellites: [...cell.satellites.entries()]
          .sort((a, b) => b[1] - a[1])
          .slice(0, 3)
          .map(([name, count]) => ({ name, count })),
      }))
      .sort((a, b) => b.count - a.count || (b.maxFrp || 0) - (a.maxFrp || 0))
      .map((cell, idx) => ({ ...cell, id: idx }))
  }

  GlobeController.prototype._fireHotspotColor = function(f = {}) {
    if (f.strike) return cachedColor("#e040fb")

    const brightness = f.brightness || 300
    if (brightness < 320) return cachedColor("#ffd54f")
    if (brightness < 350) return cachedColor("#ff9800")
    if (brightness < 400) return cachedColor("#ff5722")
    return cachedColor("#d50000")
  }

  GlobeController.prototype._isHighConfidenceFire = function(f = {}) {
    const conf = `${f.confidence || ""}`.toLowerCase()
    const numeric = Number.parseInt(conf, 10)
    return conf === "high" || conf === "h" || (!Number.isNaN(numeric) && numeric >= 80)
  }

  GlobeController.prototype._firePriorityScore = function(f = {}) {
    return (f.strike ? 1_000_000 : 0) +
      (this._isHighConfidenceFire(f) ? 100_000 : 0) +
      ((f.frp || 0) * 100) +
      (f.brightness || 0) +
      ((f.time || 0) / 1_000_000_000)
  }

  // ── Satellite NORAD IDs for FIRMS satellites ──────────────────
  const SAT_NORAD = {
    "Suomi NPP": 37849,
    "NOAA-20": 43013,
    "NOAA-21": 54234,
    "Terra": 25994,
    "Aqua": 27424,
  }

  GlobeController.prototype.showFireHotspotDetail = function(f) {
    this._clearSatFireArc()
    const date = f.time ? new Date(f.time) : null
    const ago = date ? this._timeAgo(date) : "Unknown"
    const timeStr = date ? date.toUTCString().replace("GMT", "UTC") : "Unknown"

    const confValue = Number.parseInt(f.confidence, 10)
    const confColor = this._isHighConfidenceFire(f) ? "#f44336"
      : (f.confidence === "nominal" || f.confidence === "n" || (!Number.isNaN(confValue) && confValue >= 30 && confValue < 80)) ? "#ff9800"
      : "#66bb6a"
    const confLabel = f.confidence || "unknown"

    const noradId = SAT_NORAD[f.satellite]
    const satLink = noradId
      ? `<button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;"
           data-action="click->globe#flyToSatellite" data-norad="${noradId}">
           <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Track ${this._escapeHtml(f.satellite)}
         </button>`
      : ""

    const isStrike = f.strike
    const titleColor = isStrike ? "#e040fb" : "#ff5722"
    const titleIcon = isStrike ? "fa-crosshairs" : "fa-fire"
    const titleText = isStrike ? "Possible Strike" : "Active Fire / Hotspot"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${titleColor};">
        <i class="fa-solid ${titleIcon}" style="margin-right:6px;"></i>${titleText}
      </div>
      ${isStrike ? `<div style="margin:4px 0 8px;padding:4px 8px;background:rgba(224,64,251,0.1);border:1px solid rgba(224,64,251,0.3);border-radius:4px;font:500 9px var(--gt-mono);color:#e040fb;letter-spacing:0.5px;">THERMAL ANOMALY IN ACTIVE CONFLICT ZONE</div>` : ""}
      <div class="detail-country">${f.lat.toFixed(3)}°, ${f.lng.toFixed(3)}°</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Brightness</span>
          <span class="detail-value">${f.brightness ? f.brightness.toFixed(1) + " K" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Confidence</span>
          <span class="detail-value" style="color:${confColor};">${confLabel}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Fire Power</span>
          <span class="detail-value">${f.frp ? f.frp.toFixed(1) + " MW" : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Day/Night</span>
          <span class="detail-value">${f.daynight === "D" ? "☀ Day" : "🌙 Night"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Detected by</span>
          <span class="detail-value" style="color:#ce93d8;">${this._escapeHtml(f.satellite || "Unknown")} (${f.instrument || "?"})</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Time</span>
          <span class="detail-value">${ago}</span>
        </div>
      </div>
      ${satLink}
      ${this._connectionsPlaceholder()}
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: NASA FIRMS (VIIRS/MODIS)</div>
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("fire_hotspot", f.lat, f.lng, { satellite: f.satellite })

    // Draw arc from detecting satellite to fire location
    if (noradId) this._drawSatFireArc(f, noradId)

    // Fly to fire
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(f.lng, f.lat, 300000),
      duration: 1.5,
    })
  }

  GlobeController.prototype.showFireClusterDetail = function(cluster) {
    this._clearSatFireArc()
    const date = cluster.latestTime ? new Date(cluster.latestTime) : null
    const ago = date ? this._timeAgo(date) : "Unknown"
    const timeStr = date ? date.toUTCString().replace("GMT", "UTC") : "Unknown"
    const satList = cluster.satellites?.length
      ? cluster.satellites.map(item => `${item.name}${item.count > 1 ? ` (${item.count})` : ""}`).join(", ")
      : "Unknown"

    let confidenceLabel = "Low-confidence mix"
    let confidenceColor = "#66bb6a"
    if (cluster.highConfidenceCount === cluster.count) {
      confidenceLabel = "All high-confidence"
      confidenceColor = "#f44336"
    } else if (cluster.highConfidenceCount > 0) {
      confidenceLabel = `${cluster.highConfidenceCount}/${cluster.count} high-confidence`
      confidenceColor = "#ff9800"
    }

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${cluster.strikeCount > 0 ? "#e040fb" : "#ff7043"};">
        <i class="fa-solid ${cluster.strikeCount > 0 ? "fa-crosshairs" : "fa-fire"}" style="margin-right:6px;"></i>
        Fire Cluster
      </div>
      <div class="detail-country">${cluster.lat.toFixed(2)}°, ${cluster.lng.toFixed(2)}°</div>
      <div style="margin:4px 0 10px;padding:6px 8px;background:rgba(255,112,67,0.1);border:1px solid rgba(255,112,67,0.2);border-radius:4px;font:500 9px var(--gt-mono);color:#ffab91;letter-spacing:0.4px;">
        ${cluster.count} detections grouped into one cell. Zoom closer or disable Dense Clusters to inspect individual hotspots.
      </div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Detections</span>
          <span class="detail-value">${cluster.count}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Possible strikes</span>
          <span class="detail-value" style="color:${cluster.strikeCount > 0 ? "#e040fb" : "#9aa4b2"};">${cluster.strikeCount}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Confidence</span>
          <span class="detail-value" style="color:${confidenceColor};">${this._escapeHtml(confidenceLabel)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Peak fire power</span>
          <span class="detail-value">${cluster.maxFrp ? `${cluster.maxFrp.toFixed(1)} MW` : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Peak brightness</span>
          <span class="detail-value">${cluster.maxBrightness ? `${cluster.maxBrightness.toFixed(1)} K` : "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Latest detection</span>
          <span class="detail-value">${ago}</span>
        </div>
        <div class="detail-field" style="grid-column:1 / -1;">
          <span class="detail-label">Satellites</span>
          <span class="detail-value" style="color:#ce93d8;">${this._escapeHtml(satList)}</span>
        </div>
      </div>
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Latest detection: ${this._escapeHtml(timeStr)} · Source: NASA FIRMS (VIIRS/MODIS)</div>
    `
    this.detailPanelTarget.style.display = ""
    this._flyToCoordinates(cluster.lng, cluster.lat, Math.max(700000, cluster.cellSize * 260000), { duration: 1.2 })
  }

  // Draw an arc from the detecting satellite's current position to the fire
  GlobeController.prototype._drawSatFireArc = function(fire, noradId) {
    this._clearSatFireArc()
    const Cesium = window.Cesium

    // Find the satellite entity
    const satEntity = this._findSatelliteByNorad(noradId)
    if (!satEntity) return

    const satPos = satEntity.position?.getValue(this.viewer.clock.currentTime)
    if (!satPos) return

    const firePos = Cesium.Cartesian3.fromDegrees(fire.lng, fire.lat, 0)

    const dataSource = this.getFiresDataSource()
    this._satFireArc = dataSource.entities.add({
      id: "sat-fire-arc",
      polyline: {
        positions: [satPos, firePos],
        width: 1.5,
        material: new Cesium.PolylineDashMaterialProperty({
          color: Cesium.Color.fromCssColorString("#ce93d8").withAlpha(0.6),
          dashLength: 12,
        }),
        arcType: Cesium.ArcType.NONE,
      },
    })
    this._requestRender()
  }

  GlobeController.prototype._clearSatFireArc = function() {
    if (this._satFireArc) {
      const ds = this._ds["fires"]
      if (ds) ds.entities.remove(this._satFireArc)
      this._satFireArc = null
      this._requestRender()
    }
  }

  GlobeController.prototype._findSatelliteByNorad = function(noradId) {
    // Search through all satellite datasources
    for (const [key, ds] of Object.entries(this._ds)) {
      if (!key.startsWith("sat-")) continue
      const entities = ds.entities.values
      for (let i = 0; i < entities.length; i++) {
        const e = entities[i]
        if (e.id && String(e.id) === String(noradId)) return e
      }
    }
    return null
  }

  // NORAD ID → satellite category mapping for auto-loading
  const NORAD_CATEGORY = {
    37849: "weather",  // Suomi NPP
    43013: "weather",  // NOAA-20
    54234: "weather",  // NOAA-21
    25994: "resource", // Terra
    27424: "resource", // Aqua
  }

  GlobeController.prototype.flyToSatellite = function(event) {
    const noradId = event.currentTarget.dataset.norad
    const satEntity = this._findSatelliteByNorad(noradId)
    if (satEntity) {
      this.viewer.flyTo(satEntity, { duration: 1.5 })
      return
    }

    // Auto-load the satellite category if not enabled
    const category = NORAD_CATEGORY[parseInt(noradId)]
    if (category && !this._loadedSatCategories.has(category)) {
      this._toast(`Loading ${category} satellites...`)
      this.satCategoryVisible[category] = true
      // Activate the chip UI if visible
      const chip = this.element?.querySelector(`.sb-chip[data-category="${category}"]`)
      if (chip) { chip.classList.add("active"); chip.setAttribute("aria-pressed", "true") }

      this.fetchSatCategory(category).then(() => {
        const entity = this._findSatelliteByNorad(noradId)
        if (entity) {
          this.viewer.flyTo(entity, { duration: 1.5 })
          this._toastHide()
        } else {
          this._toast("Satellite not found in loaded data")
          setTimeout(() => this._toastHide(), 3000)
        }
      })
    } else {
      this._toast("Satellite not found — try enabling more satellite categories")
      setTimeout(() => this._toastHide(), 3000)
    }
  }
}
