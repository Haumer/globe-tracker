import { getDataSource, cachedColor } from "globe/utils"
import { getPlaybackBounds } from "globe/camera"

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

// ── Fire complexes ────────────────────────────────────────────
// A complex is one fire, assembled server-side from every satellite pixel that
// falls inside it. Tiers are Fire Radiative Power in megawatts, so the bands are
// a physical measure rather than an invented score.
const FIRE_COMPLEX_TIERS = {
  extreme: { color: "#d50000", pixelSize: 11, label: "Extreme" },
  major: { color: "#ff5722", pixelSize: 8, label: "Major" },
  moderate: { color: "#ff9800", pixelSize: 5, label: "Moderate" },
  minor: { color: "#ffd54f", pixelSize: 3, label: "Minor" },
}
const FIRE_COMPLEX_FALLBACK_TIER = FIRE_COMPLEX_TIERS.minor

// Below this the camera is looking at a region, so the viewport is a meaningful
// filter and the long tail is worth asking for. Above it, bounds cover most of
// the planet and only notable fires stay legible.
const FIRE_REGIONAL_HEIGHT = 6_000_000
const FIRE_COMPLEX_LIMIT = 4_000

// Of 25,027 complexes in a day, 13,715 are single-pixel minors -- mostly
// agricultural burning and gas flares. They are real, but drawing them at world
// zoom buries the 112 extreme fires that matter.
const FIRE_NOTABLE_TIERS = ["major", "extreme"]

const INSTRUMENT_COLORS = { VIIRS: "#ff8a65", MODIS: "#8bd8ff" }
const FIRE_TREND_COLORS = { growing: "#f44336", easing: "#ff9800", dying: "#66bb6a" }

// Above this the platform is over the fire's horizon, so an arc to it means a
// live line of sight. Matches the threshold the overhead-pass readout uses.
const FIRE_SAT_MIN_ELEVATION = 5

export function applyFiresMethods(GlobeController) {

  GlobeController.prototype.getFiresDataSource = function() { return getDataSource(this.viewer, this._ds, "fires") }

  GlobeController.prototype.toggleFireHotspots = function() {
    this.fireHotspotsVisible = this.hasFireHotspotsToggleTarget && this.fireHotspotsToggleTarget.checked
    this.fireClustersVisible = !this.hasFireClustersToggleTarget || this.fireClustersToggleTarget.checked
    if (this.fireHotspotsVisible) {
      if (this._timelineActive) {
        this._timelineOnLayerToggle?.()
      } else {
        this.fetchFireHotspots()
      }
    } else {
      this._fireHotspotFetchToken += 1
      this._clearFireHotspotEntities()
      this._fireHotspotData = []
      this._fireHotspotClusterData = []
      this._fireComplexData = []
      this._fireComplexById = new Map()
      this._fireComplexQueryKey = null
    }
    this._startFiresRefresh()
    this._updateStats()
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.toggleMinorFires = function() {
    this.minorFiresVisible = this.hasMinorFiresToggleTarget && this.minorFiresToggleTarget.checked
    this._savePrefs()
    if (this.fireHotspotsVisible && !this._timelineActive) this.fetchFireHotspots()
  }

  // Whichever fire shape is currently on the globe. Live mode renders complexes;
  // timeline replay still walks per-pixel detections, because playback is a
  // point-in-time question and a complex is a 24-hour rollup.
  GlobeController.prototype._currentFireData = function() {
    return (this._timelineActive ? this._fireHotspotData : this._fireComplexData) || []
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
    if (!this._timelineActive) return this._fetchFireComplexes()

    const fetchToken = ++this._fireHotspotFetchToken
    this._toast("Loading fire hotspots...")
    try {
      let url
      if (this._timelineActive && this._timelineCursor) {
        const from = new Date(this._timelineCursor.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString()
        const params = new URLSearchParams({
          from,
          to: this._timelineCursor.toISOString(),
          types: "fire",
        })
        const bounds = this.hasActiveFilter() ? this.getFilterBounds?.() : this.getViewportBounds?.()
        if (bounds) Object.entries(bounds).forEach(([key, value]) => params.set(key, value))
        url = `/api/playback/events?${params.toString()}`
      } else {
        url = "/api/fire_hotspots"
      }

      const resp = await fetch(url)
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
      if (this._timelineActive) {
        this._fireHotspotData = raw.map(event => ({
          id: event.external_id || event.id,
          lat: event.lat,
          lng: event.lng,
          brightness: event.brightness,
          confidence: event.confidence,
          satellite: event.satellite,
          instrument: event.instrument,
          frp: event.frp,
          daynight: event.daynight,
          time: event.time,
          strike: false,
        }))
      } else {
        // API returns arrays: [id, lat, lng, brightness, confidence, satellite, instrument, frp, daynight, time, strike]
        this._fireHotspotData = raw.map(r => ({
          id: r[0], lat: r[1], lng: r[2], brightness: r[3],
          confidence: r[4], satellite: r[5], instrument: r[6],
          frp: r[7], daynight: r[8], time: r[9], strike: r[10] === 1,
        }))
      }
      this._fireHotspotClusterData = []
      if (!this._timelineActive) {
        this._handleBackgroundRefresh(resp, "fire-hotspots", this._fireHotspotData.length > 0, () => {
          if (this.fireHotspotsVisible && !this._timelineActive) this.fetchFireHotspots()
        })
      }
      this.renderFireHotspots()
      this._markFresh("fireHotspots")
      this._updateStats()
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch fire hotspots:", e)
      this._toastHide()
    }
  }

  // ── Fire complexes: fetch ─────────────────────────────────────
  // The query follows the camera. At world zoom the globe asks for notable
  // fires only; zoomed into a region it asks for everything in view, because
  // there the long tail is a handful of fires rather than 13,000.
  GlobeController.prototype._fireComplexQuery = function() {
    const height = this.viewer?.camera?.positionCartographic?.height || 0
    const filtered = !!(this.hasActiveFilter && this.hasActiveFilter())
    const regional = height < FIRE_REGIONAL_HEIGHT || filtered
    const params = new URLSearchParams()

    // getViewportBounds returns null whenever the globe cannot be picked -- an
    // unloaded tile, a camera angled off the limb. getPlaybackBounds falls back
    // to the view rectangle and then to a camera approximation, which is what
    // playback already relies on.
    const bounds = regional
      ? (filtered ? this.getFilterBounds?.() : getPlaybackBounds(this.viewer))
      : null
    if (bounds) {
      Object.entries(bounds).forEach(([key, value]) => params.set(key, Number(value).toFixed(2)))
    }

    // Without bounds the long tail is a global query for 13,000 single-pixel
    // burns, so an unresolvable viewport keeps the tier gate rather than
    // quietly dropping it.
    if (!this.minorFiresVisible && !(regional && bounds)) params.set("notable", "1")
    params.set("limit", `${FIRE_COMPLEX_LIMIT}`)

    return params
  }

  // Camera moves constantly; the query only changes when the viewport has moved
  // enough to matter, so the key is the deciding factor for whether to refetch.
  GlobeController.prototype.maybeRefetchFireComplexes = function() {
    if (!this.fireHotspotsVisible || this._timelineActive) return
    if (this._fireComplexQuery().toString() === this._fireComplexQueryKey) return

    this._fetchFireComplexes()
  }

  GlobeController.prototype._fetchFireComplexes = async function() {
    const fetchToken = ++this._fireHotspotFetchToken
    const params = this._fireComplexQuery()
    this._toast("Loading fires...")

    try {
      const resp = await fetch(`/api/fire_clusters?${params.toString()}`)
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

      // [external_id, lat, lng, intensity_mw, tier, pixels, passes, last_ms, first_ms, latest_mw]
      this._fireComplexData = raw.map(r => ({
        id: r[0],
        lat: r[1],
        lng: r[2],
        mw: r[3],
        tier: r[4],
        pixels: r[5],
        passes: r[6],
        time: r[7],
        firstTime: r[8],
        latestMw: r[9],
        complex: true,
        // Search and the satellite-visibility readout both key off `frp`.
        frp: r[3],
      }))
      this._fireComplexById = new Map(this._fireComplexData.map(fire => [fire.id, fire]))
      this._fireComplexQueryKey = params.toString()

      this._handleBackgroundRefresh(resp, "fire-clusters", this._fireComplexData.length > 0, () => {
        if (this.fireHotspotsVisible && !this._timelineActive) this._fetchFireComplexes()
      })

      this.renderFireHotspots()
      this._markFresh("fireHotspots")
      this._updateStats()
      this._toastHide()

      // Pinned fires ride the layer's cadence rather than a timer of their own.
      this._refreshPinnedLiveStates?.("fire_complex")
      if (this._fireDossier) this._refreshFireDossier()
    } catch (e) {
      console.error("Failed to fetch fire complexes:", e)
      this._toastHide()
    }
  }

  // ── Fire complexes: render ────────────────────────────────────
  GlobeController.prototype._fireComplexTier = function(complex = {}) {
    return FIRE_COMPLEX_TIERS[complex.tier] || FIRE_COMPLEX_FALLBACK_TIER
  }

  GlobeController.prototype._renderFireComplexes = function() {
    this._clearFireHotspotEntities()
    this._fireHotspotClusterData = []

    // The server already bounded the query, but the camera keeps moving between
    // fetches, so cull against where it is now rather than where it was.
    const bounds = this.getViewportBounds()
    const visible = this._fireComplexData.filter(fire => {
      if (bounds && (fire.lat < bounds.lamin || fire.lat > bounds.lamax ||
                     fire.lng < bounds.lomin || fire.lng > bounds.lomax)) return false
      if (this.hasActiveFilter && this.hasActiveFilter() && !this.pointPassesFilter(fire.lat, fire.lng)) return false
      return true
    })

    if (visible.length === 0) {
      this._requestRender()
      return
    }

    const dataSource = this.getFiresDataSource()
    dataSource.entities.suspendEvents()
    visible.forEach(fire => this._renderFireComplex(dataSource, fire))
    dataSource.entities.resumeEvents()

    this._requestRender()
  }

  GlobeController.prototype._renderFireComplex = function(dataSource, fire) {
    const Cesium = window.Cesium
    const tier = this._fireComplexTier(fire)
    const color = cachedColor(tier.color)

    // Extreme fires get a footprint ring. The radius tracks pixel count, which
    // is the area actually burning, not the radiative power.
    if (fire.tier === "extreme") {
      const radius = Math.min(4_000 + Math.sqrt(fire.pixels || 1) * 900, 60_000)
      const ring = dataSource.entities.add({
        id: `fire-complex-ring-${fire.id}`,
        position: Cesium.Cartesian3.fromDegrees(fire.lng, fire.lat, 0),
        ellipse: {
          semiMinorAxis: radius,
          semiMajorAxis: radius,
          material: color.withAlpha(0.06),
          outline: true,
          outlineColor: color.withAlpha(0.22),
          outlineWidth: 0.8,
          height: 0,
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
        },
      })
      this._fireHotspotEntities.push(ring)
    }

    const entity = dataSource.entities.add({
      id: `fire-complex-${fire.id}`,
      position: Cesium.Cartesian3.fromDegrees(fire.lng, fire.lat, 10),
      point: {
        pixelSize: tier.pixelSize,
        color: color.withAlpha(0.85),
        outlineColor: color.withAlpha(0.25),
        outlineWidth: 1,
        scaleByDistance: new Cesium.NearFarScalar(1e5, 1.05, 1.4e7, 0.4),
        heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      label: fire.tier === "extreme" ? {
        text: this._fireMwLabel(fire.mw),
        font: "11px JetBrains Mono, monospace",
        fillColor: Cesium.Color.WHITE.withAlpha(0.85),
        outlineColor: Cesium.Color.BLACK.withAlpha(0.8),
        outlineWidth: 2,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        pixelOffset: new Cesium.Cartesian2(0, -(tier.pixelSize + 8)),
        horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
        scaleByDistance: new Cesium.NearFarScalar(1e5, 0.95, 1.2e7, 0.3),
        translucencyByDistance: new Cesium.NearFarScalar(1e5, 0.95, 1.2e7, 0.0),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      } : undefined,
    })
    this._fireHotspotEntities.push(entity)
  }

  GlobeController.prototype._fireMwLabel = function(mw) {
    const value = Number(mw) || 0
    if (value >= 10_000) return `${(value / 1000).toFixed(1)} GW`
    if (value >= 1000) return `${Math.round(value).toLocaleString()} MW`
    if (value >= 10) return `${Math.round(value)} MW`
    return `${value.toFixed(1)} MW`
  }

  GlobeController.prototype.renderFireHotspots = function() {
    if (!this.fireHotspotsVisible) {
      this._clearFireHotspotEntities()
      this._fireHotspotClusterData = []
      return
    }
    if (!this._timelineActive) return this._renderFireComplexes()
    this._clearFireHotspotEntities()
    this._fireHotspotClusterData = []
    const bounds = this._timelineActive && !(this.hasActiveFilter && this.hasActiveFilter())
      ? null
      : this.getViewportBounds()
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
    const titleText = isStrike ? "Heat Signature" : "Active Fire / Hotspot"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${titleColor};">
        <i class="fa-solid ${titleIcon}" style="margin-right:6px;"></i>${titleText}
      </div>
      ${isStrike ? `<div style="margin:4px 0 8px;padding:4px 8px;background:rgba(224,64,251,0.1);border:1px solid rgba(224,64,251,0.3);border-radius:4px;font:500 9px var(--gt-mono);color:#e040fb;letter-spacing:0.5px;">THERMAL SIGNAL IN ACTIVE CONFLICT ZONE</div>` : ""}
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
  // ── Fire complexes: the pinned card ───────────────────────────
  // A pinned fire is a subscription, not a snapshot. The card re-reads the
  // complex on every layer refresh and reports what moved since you pinned it,
  // because a fire that is still burning is remeasured every satellite pass.
  GlobeController.prototype._renderFireComplexCardBody = function(payload) {
    const fire = payload.record || {}
    const tier = this._fireComplexTier(fire)
    const detail = payload.detail
    const trend = detail?.trend
    const trendMark = { growing: "▲", easing: "▶", dying: "▼" }[trend] || ""
    const trendColor = FIRE_TREND_COLORS[trend] || "rgba(200,210,225,0.5)"

    if (payload.extinct) {
      return `
        <div class="anchor-fire-body">
          <div class="anchor-fire-gone">No longer detected. Last seen ${this._escapeHtml(fire.time ? this._timeAgo(new Date(fire.time)) : "unknown")} at ${this._fireMwLabel(fire.latestMw)}.</div>
        </div>`
    }

    const spark = detail?.observations?.length
      ? this._fireEvolutionSvg(detail.observations, { width: 268, height: 34, compact: true })
      : ""

    return `
      <div class="anchor-fire-body">
        <div class="anchor-fire-headline">
          <span class="anchor-fire-mw" style="color:${tier.color};">${this._fireMwLabel(fire.mw)}</span>
          <span class="anchor-fire-mw-label">peak</span>
          <span class="anchor-fire-trend" style="color:${trendColor};">${trendMark} ${this._escapeHtml(trend || "")}</span>
        </div>
        <div class="anchor-fire-sub">${this._fireMwLabel(fire.latestMw)} now · ${(fire.pixels || 0).toLocaleString()} px · ${fire.passes || 0} passes</div>
        ${spark}
        ${this._firePinDeltaHtml(payload)}
      </div>
    `
  }

  // The reason to pin a fire rather than just look at it.
  GlobeController.prototype._firePinDeltaHtml = function(payload) {
    const baseline = payload.pinBaseline
    const fire = payload.record
    if (!baseline || !fire || !payload.pinned) return ""

    const newPasses = (fire.passes || 0) - (baseline.passes || 0)
    const tierChanged = baseline.tier !== fire.tier
    const mwFrom = baseline.latestMw
    const mwTo = fire.latestMw

    if (newPasses <= 0 && !tierChanged) {
      return `<div class="anchor-fire-delta anchor-fire-delta--quiet">Watching — no new pass yet</div>`
    }

    const parts = []
    if (newPasses > 0) parts.push(`+${newPasses} pass${newPasses === 1 ? "" : "es"}`)
    if (mwFrom != null && mwTo != null) parts.push(`${this._fireMwLabel(mwFrom)} → ${this._fireMwLabel(mwTo)}`)
    if (tierChanged) parts.push(`${baseline.tier} → ${fire.tier}`)

    return `<div class="anchor-fire-delta"${tierChanged ? ` style="color:${this._fireComplexTier(fire).color};"` : ""}>Since pinned: ${this._escapeHtml(parts.join(" · "))}</div>`
  }

  // Called for every pinned fire whenever the fire layer refreshes.
  GlobeController.prototype._refreshPinnedFireComplex = async function(state) {
    const id = state?.record?.id
    if (!id) return false

    try {
      const resp = await fetch(`/api/fire_clusters/${encodeURIComponent(id)}`)

      // A complex drops out of the feed when it stops being detected -- the
      // fire went out. That is a result, not an error, so the card says so
      // rather than silently freezing on its last known numbers.
      if (resp.status === 404) {
        if (state.extinct) return false
        state.extinct = true
        return true
      }
      if (!resp.ok) return false

      const detail = await resp.json()
      const previousTier = state.record?.tier
      state.extinct = false
      state.detail = detail
      state.record = {
        ...state.record,
        mw: detail.intensity_mw,
        latestMw: detail.latest_mw,
        tier: detail.tier,
        pixels: detail.pixel_count,
        passes: detail.pass_count,
        time: detail.last_detected_at ? new Date(detail.last_detected_at).getTime() : state.record?.time,
      }

      // A fire crossing a tier boundary changes what the card means, so the
      // accent and leader line follow it.
      if (detail.tier !== previousTier) {
        const tier = this._fireComplexTier(state.record)
        state.accent = tier.color
        state.stroke = tier.color
        state.chips = [{ label: tier.label, tone: detail.tier === "extreme" ? "critical" : "warning" }]
        this._applyPinnedAnchoredDetailAccent?.(state)
      }

      return true
    } catch (e) {
      console.error("Failed to refresh pinned fire:", e)
      return false
    }
  }

  // The active card opens from an index row, which carries no pass history.
  // Hydrating it gives the card its sparkline without a second click.
  GlobeController.prototype._hydrateActiveFireCard = async function() {
    const state = this._anchoredDetailState
    if (state?.kind !== "fire_complex" || state.detail) return

    if (await this._refreshPinnedFireComplex(state)) this._refreshAnchoredDetailContent()
  }

  // ── Fire complexes: the dossier ───────────────────────────────
  GlobeController.prototype.openFireDossier = async function(fire) {
    if (!fire?.id) return

    this._fireDossier = { fire, detail: null, loading: true }
    this._renderFireDossier()
    this._showRightPanel?.("fire")
    this._flyToCoordinates(fire.lng, fire.lat, 400000, { duration: 1.2 })

    const token = ++this._fireComplexDetailToken
    try {
      const resp = await fetch(`/api/fire_clusters/${encodeURIComponent(fire.id)}`)
      if (token !== this._fireComplexDetailToken) return

      if (!resp.ok) {
        this._fireDossier = { fire, detail: null, loading: false, missing: true }
        this._renderFireDossier()
        return
      }

      const detail = await resp.json()
      if (token !== this._fireComplexDetailToken) return

      this._fireDossier = { fire, detail, loading: false }
      this._renderFireDossier()
      this._drawFireSatelliteArcs(fire, detail.satellites || [])
    } catch (e) {
      console.error("Failed to load fire dossier:", e)
    }
  }

  GlobeController.prototype._renderFireDossier = function() {
    if (!this.hasFireDossierContentTarget) return

    const state = this._fireDossier
    if (!state) {
      this.fireDossierContentTarget.innerHTML = `<div class="fd-empty">SELECT A FIRE</div>`
      return
    }

    const { fire, detail } = state
    const tier = this._fireComplexTier(fire)
    const trend = detail?.trend
    const trendColor = FIRE_TREND_COLORS[trend] || "rgba(200,210,225,0.5)"
    const trendMark = { growing: "▲", easing: "▶", dying: "▼" }[trend] || ""

    if (state.missing) {
      this.fireDossierContentTarget.innerHTML = `
        <div class="fd-head"><span class="fd-tier" style="color:${tier.color};border-color:${tier.color};">${tier.label.toUpperCase()}</span></div>
        <div class="fd-empty">This complex is no longer in the feed — it stopped being detected.</div>
        ${this._firePinnedListHtml()}
      `
      return
    }

    this.fireDossierContentTarget.innerHTML = `
      <div class="fd-head">
        <span class="fd-tier" style="color:${tier.color};border-color:${tier.color};">${tier.label.toUpperCase()}</span>
        <span class="fd-coords">${fire.lat.toFixed(3)}°, ${fire.lng.toFixed(3)}°</span>
      </div>

      <div class="fd-hero">
        <div class="fd-hero-main">
          <div class="fd-hero-value" style="color:${tier.color};">${this._fireMwLabel(fire.mw)}</div>
          <div class="fd-hero-label">peak single pass</div>
        </div>
        <div class="fd-hero-side">
          <div class="fd-hero-trend" style="color:${trendColor};">${trendMark} ${this._escapeHtml(trend || "unknown")}</div>
          <div class="fd-hero-now">${this._fireMwLabel(fire.latestMw)} now</div>
        </div>
      </div>

      ${detail ? this._fireDossierEvolutionHtml(detail) : `<div class="fd-loading">Loading pass history…</div>`}

      <div class="fd-stats">
        <div class="fd-stat"><span class="fd-stat-label">Footprint</span><span class="fd-stat-value">${(fire.pixels || 0).toLocaleString()} px</span></div>
        <div class="fd-stat"><span class="fd-stat-label">Passes</span><span class="fd-stat-value">${fire.passes || 0}</span></div>
        <div class="fd-stat"><span class="fd-stat-label">Detections</span><span class="fd-stat-value">${(detail?.detection_count || 0).toLocaleString()}</span></div>
        <div class="fd-stat"><span class="fd-stat-label">Burning for</span><span class="fd-stat-value">${this._fireBurnDuration(fire)}</span></div>
      </div>

      ${detail ? this._fireDossierSatellitesHtml(fire, detail) : ""}
      ${this._firePinnedListHtml()}

      <div class="fd-source">Peak intensity is the strongest single satellite pass, never the sum across passes · NASA FIRMS (VIIRS/MODIS)</div>
    `
  }

  GlobeController.prototype._fireBurnDuration = function(fire) {
    if (!fire.firstTime || !fire.time) return "—"
    const hours = (fire.time - fire.firstTime) / 3_600_000
    if (hours < 1) return `${Math.round(hours * 60)}m`
    return `${hours.toFixed(1)}h`
  }

  GlobeController.prototype._fireDossierEvolutionHtml = function(detail) {
    const observations = detail.observations || []
    if (!observations.length) return `<div class="fd-empty">No pass history recorded.</div>`

    return `
      <div class="fd-section-title">EVOLUTION</div>
      ${this._fireEvolutionSvg(observations, { width: 320, height: 110, axes: true })}
    `
  }

  // The satellites that saw this fire, and whether any of them can see it right
  // now. Elevation is computed from the fire's own position, so a link means a
  // live line of sight rather than "contributed a pass at some point".
  GlobeController.prototype._fireDossierSatellitesHtml = function(fire, detail) {
    const names = detail.satellites || []
    if (!names.length) return ""

    const status = this._fireSatelliteStatus(fire, names)
    const lastPassBy = new Map()
    ;(detail.observations || []).forEach(observation => {
      lastPassBy.set(observation.satellite, observation)
    })

    const rows = names.map(name => {
      const observation = lastPassBy.get(name)
      const info = status.get(name)
      const color = INSTRUMENT_COLORS[observation?.instrument] || "#9aa4b2"
      const norad = SAT_NORAD[name]

      let stateHtml = `<span class="fd-sat-state fd-sat-state--unknown">not loaded</span>`
      let actions = ""
      if (info?.overhead) {
        stateHtml = `<span class="fd-sat-state fd-sat-state--overhead">↗ ${Math.round(info.elevation)}° overhead</span>`
        actions = `<button type="button" class="fd-sat-btn" data-action="click->globe#linkFireSatellite" data-norad="${norad}" data-sat="${this._escapeHtml(name)}">Link</button>`
      } else if (info) {
        stateHtml = `<span class="fd-sat-state fd-sat-state--below">below horizon</span>`
      }
      if (norad) {
        actions += `<button type="button" class="fd-sat-btn" data-action="click->globe#flyToSatellite" data-norad="${norad}">Track</button>`
      }

      return `
        <div class="fd-sat-row">
          <div class="fd-sat-main">
            <span class="fd-sat-dot" style="background:${color};"></span>
            <span class="fd-sat-name">${this._escapeHtml(name)}</span>
            ${stateHtml}
          </div>
          <div class="fd-sat-meta">
            <span>${observation ? new Date(observation.at).toISOString().slice(11, 16) : "—"}</span>
            <span>${observation ? this._fireMwLabel(observation.mw) : "—"}</span>
            <span class="fd-sat-actions">${actions}</span>
          </div>
        </div>`
    }).join("")

    // Platforms sit across three catalogue categories, so rather than telling
    // the reader which layers to hunt for, offer to load exactly the ones this
    // fire's detectors live in.
    const missing = names.filter(name => SAT_NORAD[name] && !status.has(name))
    const hint = missing.length
      ? `<div class="fd-sat-hint">
           ${missing.length} of ${names.length} platforms not loaded, so their position is unknown.
           <button type="button" class="fd-sat-btn" data-action="click->globe#loadFirePlatforms">Load platforms</button>
         </div>`
      : ""

    return `
      <div class="fd-section-title">DETECTED BY <span class="fd-section-count">${names.length} platforms</span></div>
      <div class="fd-sat-list">${rows}</div>
      ${hint}
    `
  }

  // Pinned fires live here too, so the dossier doubles as the switcher.
  GlobeController.prototype._firePinnedListHtml = function() {
    const pins = (this._pinnedAnchoredDetails || []).filter(state => state.kind === "fire_complex")
    if (!pins.length) return ""

    const activeId = this._fireDossier?.fire?.id
    const rows = pins.map(state => {
      const fire = state.record || {}
      const tier = this._fireComplexTier(fire)
      const active = fire.id === activeId ? " fd-pin-row--active" : ""
      return `
        <button type="button" class="fd-pin-row${active}" data-action="click->globe#focusPinnedFire" data-fire-id="${this._escapeHtml(fire.id || "")}">
          <span class="fd-pin-dot" style="background:${tier.color};"></span>
          <span class="fd-pin-tier">${tier.label}</span>
          <span class="fd-pin-mw">${this._fireMwLabel(fire.mw)}</span>
          <span class="fd-pin-loc">${Number(fire.lat).toFixed(1)}°, ${Number(fire.lng).toFixed(1)}°</span>
          ${state.extinct ? `<span class="fd-pin-gone">out</span>` : ""}
        </button>`
    }).join("")

    return `
      <div class="fd-section-title">PINNED FIRES <span class="fd-section-count">${pins.length}</span></div>
      <div class="fd-pin-list">${rows}</div>
    `
  }

  // Keep an open dossier current with the layer without stealing the camera.
  GlobeController.prototype._refreshFireDossier = async function() {
    const fire = this._fireDossier?.fire
    if (!fire?.id) return

    try {
      const resp = await fetch(`/api/fire_clusters/${encodeURIComponent(fire.id)}`)
      if (this._fireDossier?.fire?.id !== fire.id) return

      if (resp.status === 404) {
        this._fireDossier = { fire, detail: null, loading: false, missing: true }
        this._renderFireDossier()
        return
      }
      if (!resp.ok) return

      const detail = await resp.json()
      if (this._fireDossier?.fire?.id !== fire.id) return

      this._fireDossier = {
        fire: {
          ...fire,
          mw: detail.intensity_mw,
          latestMw: detail.latest_mw,
          tier: detail.tier,
          pixels: detail.pixel_count,
          passes: detail.pass_count,
          time: detail.last_detected_at ? new Date(detail.last_detected_at).getTime() : fire.time,
        },
        detail,
        loading: false,
      }
      this._renderFireDossier()
    } catch (e) {
      console.error("Failed to refresh fire dossier:", e)
    }
  }

  GlobeController.prototype.focusPinnedFire = function(event) {
    const id = event?.currentTarget?.dataset?.fireId
    const pin = (this._pinnedAnchoredDetails || []).find(state => state.record?.id === id)
    if (!pin?.record) return

    this.openFireDossier(pin.record)
  }

  // ── Fire complexes: satellite link ────────────────────────────
  // Propagate each detecting platform's TLE and take its elevation from the
  // fire. Above the horizon means it could be measuring this fire right now.
  GlobeController.prototype._fireSatelliteStatus = function(fire, names = []) {
    const status = new Map()
    const sat = window.satellite
    if (!sat || !this.satelliteData?.length) return status

    const now = new Date()
    const gmst = sat.gstime(now)
    const observerGd = {
      latitude: fire.lat * Math.PI / 180,
      longitude: fire.lng * Math.PI / 180,
      height: 0,
    }

    names.forEach(name => {
      const norad = SAT_NORAD[name]
      if (!norad) return

      const record = this.satelliteData.find(entry => Number(entry.norad_id) === norad)
      if (!record) return

      try {
        let satrec = this._satrecCache?.get(record.norad_id)
        if (!satrec) satrec = sat.twoline2satrec(record.tle_line1, record.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) return

        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        const lookAngles = sat.ecfToLookAngles(observerGd, sat.eciToEcf(posVel.position, gmst))
        const elevation = lookAngles.elevation * 180 / Math.PI

        status.set(name, {
          elevation,
          overhead: elevation > FIRE_SAT_MIN_ELEVATION,
          lat: sat.degreesLat(posGd.latitude),
          lng: sat.degreesLong(posGd.longitude),
          alt: posGd.height * 1000,
        })
      } catch {
        // Skip platforms with an unusable TLE rather than dropping the row.
      }
    })

    return status
  }

  GlobeController.prototype._drawFireSatelliteArcs = function(fire, names = []) {
    this._clearFireSatelliteArcs()
    const status = this._fireSatelliteStatus(fire, names)
    status.forEach((info, name) => {
      if (info.overhead) this._drawFireSatelliteArc(fire, name, info)
    })
  }

  GlobeController.prototype._drawFireSatelliteArc = function(fire, name, info) {
    const Cesium = window.Cesium
    if (!Cesium || !info) return

    const dataSource = this.getFiresDataSource()
    const entity = dataSource.entities.add({
      id: `fire-sat-arc-${fire.id}-${name}`,
      polyline: {
        positions: [
          Cesium.Cartesian3.fromDegrees(info.lng, info.lat, info.alt),
          Cesium.Cartesian3.fromDegrees(fire.lng, fire.lat, 0),
        ],
        width: 1.5,
        material: new Cesium.PolylineDashMaterialProperty({
          color: Cesium.Color.fromCssColorString("#ce93d8").withAlpha(0.65),
          dashLength: 12,
        }),
        arcType: Cesium.ArcType.NONE,
      },
    })

    this._fireSatArcEntities ||= []
    this._fireSatArcEntities.push(entity)
    this._requestRender()
  }

  GlobeController.prototype._clearFireSatelliteArcs = function() {
    if (!this._fireSatArcEntities?.length) return

    const ds = this._ds["fires"]
    if (ds) this._fireSatArcEntities.forEach(entity => ds.entities.remove(entity))
    this._fireSatArcEntities = []
    this._requestRender()
  }

  // Load the satellite categories this fire's detectors live in, so the
  // overhead readout can answer rather than shrug.
  GlobeController.prototype.loadFirePlatforms = async function(event) {
    event?.preventDefault?.()
    const fire = this._fireDossier?.fire
    const names = this._fireDossier?.detail?.satellites || []
    if (!fire || !names.length) return

    const categories = [...new Set(names.map(name => NORAD_CATEGORY[SAT_NORAD[name]]).filter(Boolean))]
    if (!categories.length) return

    this._toast?.("Loading detecting platforms…")
    for (const category of categories) {
      this.satCategoryVisible[category] = true
      const chip = this.element?.querySelector(`.sb-chip[data-category="${category}"]`)
      if (chip) { chip.classList.add("active"); chip.setAttribute("aria-pressed", "true") }
      await this.fetchSatCategory(category)
    }

    this._toastHide()
    this._renderFireDossier()
    this._drawFireSatelliteArcs(fire, names)
  }

  GlobeController.prototype.linkFireSatellite = function(event) {
    event?.preventDefault?.()
    const name = event?.currentTarget?.dataset?.sat
    const fire = this._fireDossier?.fire
    if (!name || !fire) return

    const info = this._fireSatelliteStatus(fire, [name]).get(name)
    if (!info?.overhead) {
      this._toast?.(`${name} is below the horizon from this fire`)
      setTimeout(() => this._toastHide(), 2500)
      return
    }

    this._clearFireSatelliteArcs()
    this._drawFireSatelliteArc(fire, name, info)
    this._toast?.(`${name} — ${Math.round(info.elevation)}° above the fire`)
    setTimeout(() => this._toastHide(), 2500)
  }

  // ── Fire complexes: evolution chart ───────────────────────────
  // One line per instrument, never one line across both. MODIS resolves 1km
  // pixels and VIIRS 375m, so joining them draws a sawtooth that reads as a fire
  // flaring and collapsing when nothing on the ground has changed.
  GlobeController.prototype._fireEvolutionSvg = function(observations, options = {}) {
    const width = options.width || 320
    const height = options.height || 110
    const compact = !!options.compact
    const padX = compact ? 3 : 30
    const padY = compact ? 4 : 12

    const times = observations.map(observation => new Date(observation.at).getTime())
    const minTime = Math.min(...times)
    const maxTime = Math.max(...times)
    const maxMw = Math.max(...observations.map(observation => Number(observation.mw) || 0), 1)
    const spanTime = maxTime - minTime || 1

    const x = (time) => padX + ((time - minTime) / spanTime) * (width - padX - (compact ? padX : 6))
    const y = (mw) => height - padY - ((Number(mw) || 0) / maxMw) * (height - padY * 2)

    const byInstrument = new Map()
    observations.forEach((observation, index) => {
      const key = observation.instrument || "Unknown"
      if (!byInstrument.has(key)) byInstrument.set(key, [])
      byInstrument.get(key).push({ ...observation, at: times[index] })
    })

    let series = ""
    let dots = ""
    byInstrument.forEach((points, instrument) => {
      const color = INSTRUMENT_COLORS[instrument] || "#9aa4b2"
      if (points.length > 1) {
        const path = points.map(point => `${x(point.at).toFixed(1)},${y(point.mw).toFixed(1)}`).join(" ")
        series += `<polyline points="${path}" style="fill:none;stroke:${color};stroke-width:1.5;opacity:0.85;"></polyline>`
      }
      points.forEach(point => {
        dots += `<circle cx="${x(point.at).toFixed(1)}" cy="${y(point.mw).toFixed(1)}" r="${compact ? 1.8 : 2.6}" style="fill:${color};"></circle>`
      })
    })

    if (compact) {
      return `<svg class="anchor-fire-spark" viewBox="0 0 ${width} ${height}">${series}${dots}</svg>`
    }

    const axes = `
      <line x1="${padX}" y1="${height - padY}" x2="${width - 6}" y2="${height - padY}" style="stroke:rgba(255,255,255,0.14);stroke-width:1;"></line>
      <text x="2" y="${padY + 8}" style="fill:rgba(200,210,225,0.45);font:9px var(--gt-mono, monospace);">${this._fireMwLabel(maxMw)}</text>
      <text x="2" y="${height - padY}" style="fill:rgba(200,210,225,0.45);font:9px var(--gt-mono, monospace);">0</text>
    `

    const legend = [...byInstrument.keys()].map(instrument => {
      const color = INSTRUMENT_COLORS[instrument] || "#9aa4b2"
      return `<span style="color:${color};">● ${this._escapeHtml(instrument)}</span>`
    }).join("")

    const from = new Date(minTime).toISOString().slice(5, 16).replace("T", " ")
    const to = new Date(maxTime).toISOString().slice(5, 16).replace("T", " ")

    return `
      <div class="fd-chart">
        <svg viewBox="0 0 ${width} ${height}">${axes}${series}${dots}</svg>
      </div>
      <div class="fd-chart-foot">
        <span>${this._escapeHtml(from)}</span>
        <span class="fd-chart-legend">${legend}</span>
        <span>${this._escapeHtml(to)}</span>
      </div>
    `
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
    const expectedId = `sat-${noradId}`
    const direct = this.satelliteEntities?.get?.(expectedId)
    if (direct) return direct

    // Fallback for older satellite datasource shapes.
    for (const [key, ds] of Object.entries(this._ds)) {
      if (key !== "satellites" && key !== "sat-orbits" && !key.startsWith("sat-")) continue
      const entities = ds.entities.values
      for (let i = 0; i < entities.length; i++) {
        const e = entities[i]
        if (e.id && (String(e.id) === expectedId || String(e.id) === String(noradId))) return e
      }
    }
    return null
  }

  // NORAD ID → satellite category mapping for auto-loading
  const NORAD_CATEGORY = {
    37849: "weather",  // Suomi NPP
    43013: "weather",  // NOAA-20
    54234: "weather",  // NOAA-21
    25994: "science",  // Terra -- catalogued under science, not resource
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
