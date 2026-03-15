import { getDataSource, cachedColor } from "../utils"

export function applyWeatherMethods(GlobeController) {

  // Available weather overlay layers
  // Rain & Clouds use RainViewer (free); Temp/Wind/Pressure need OWM paid key
  const WEATHER_LAYERS = {
    precipitation: { label: "Rain",   icon: "fa-cloud-rain",      color: "#42a5f5", free: true },
    clouds:        { label: "Clouds", icon: "fa-cloud",            color: "#90a4ae", free: true },
    temperature:   { label: "Temp",   icon: "fa-temperature-half", color: "#ef5350", owmId: "temp_new" },
    wind:          { label: "Wind",   icon: "fa-wind",             color: "#26c6da", owmId: "wind_new" },
    pressure:      { label: "Hpa",    icon: "fa-gauge-high",       color: "#ab47bc", owmId: "pressure_new" },
  }

  GlobeController.prototype.getWeatherDataSource = function() {
    return getDataSource(this.viewer, this._ds, "weather")
  }

  // ── Weather satellite mapping ──────────────────────────────────
  // Maps weather imagery sources to the satellites that provide them.
  // NORAD IDs for key geostationary weather satellites.
  const WEATHER_SAT_SOURCES = {
    clouds: [
      { norad: 41866, name: "GOES-16 (East)", region: "Americas" },
      { norad: 51850, name: "GOES-18 (West)", region: "Pacific/Americas" },
      { norad: 60133, name: "GOES-19",        region: "Americas" },
      { norad: 40732, name: "Meteosat-11",    region: "Europe/Africa" },
      { norad: 54743, name: "Meteosat-12",    region: "Europe/Africa" },
      { norad: 38552, name: "Meteosat-10",    region: "Indian Ocean" },
      { norad: 40267, name: "Himawari-8",     region: "Asia/Pacific" },
      { norad: 41836, name: "Himawari-9",     region: "Asia/Pacific" },
    ],
    precipitation: [
      // Radar data is ground-based, but polar-orbiting sats provide
      // additional precipitation estimates in areas without radar coverage
      { norad: 37849, name: "Suomi NPP",      region: "Global (polar)" },
      { norad: 43013, name: "NOAA-20",        region: "Global (polar)" },
      { norad: 54234, name: "NOAA-21",        region: "Global (polar)" },
    ],
  }

  // ── Main toggle ──────────────────────────────────────────────

  GlobeController.prototype.toggleWeather = function() {
    this.weatherVisible = this.hasWeatherToggleTarget && this.weatherToggleTarget.checked

    if (this.weatherVisible) {
      this._ensureWeatherPanel()
      this._showWeatherPanel(true)
      // Auto-enable precipitation if nothing is on
      if (!this._weatherActiveLayers || Object.keys(this._weatherActiveLayers).length === 0) {
        this._weatherActiveLayers = {}
        this.toggleWeatherSublayer("precipitation")
      }
      this._fetchWeatherAlerts()
      this._enableWeatherSatellites()
    } else {
      this._removeAllWeatherLayers()
      this._showWeatherPanel(false)
      this._clearWeatherAlertEntities()
      this._clearWeatherSatBeams()
    }
    this._updateStats()
    this._requestRender()
    this._savePrefs()
  }

  // ── Sub-layer toggle (imagery overlays) ───────────────────────

  GlobeController.prototype.toggleWeatherSublayer = async function(layerKey) {
    if (!this._weatherActiveLayers) this._weatherActiveLayers = {}
    if (!this._weatherImageryLayers) this._weatherImageryLayers = {}

    const Cesium = window.Cesium

    if (this._weatherActiveLayers[layerKey]) {
      // Remove this layer
      const layer = this._weatherImageryLayers[layerKey]
      if (layer) {
        this.viewer.imageryLayers.remove(layer)
        delete this._weatherImageryLayers[layerKey]
      }
      delete this._weatherActiveLayers[layerKey]
    } else {
      // Add this layer
      const cfg = WEATHER_LAYERS[layerKey]
      if (!cfg) return

      const provider = await this._createWeatherProvider(layerKey, cfg, Cesium)
      if (!provider) {
        console.warn(`Weather layer "${layerKey}" unavailable (no API key and no free fallback)`)
        return
      }

      const imgLayer = this.viewer.imageryLayers.addImageryProvider(provider)
      imgLayer.alpha = this._weatherOpacity || 0.6
      imgLayer.brightness = 1.2
      this._weatherImageryLayers[layerKey] = imgLayer
      this._weatherActiveLayers[layerKey] = true
    }

    this._syncWeatherChips()
    this._renderWeatherSatBeams()
    this._requestRender()
    this._savePrefs()
  }

  // ── Provider factory: RainViewer for rain/clouds (free), OWM for temp/wind/pressure ──

  GlobeController.prototype._createWeatherProvider = async function(layerKey, cfg, Cesium) {
    // Free layers via RainViewer
    if (cfg.free) {
      return await this._createRainViewerProvider(layerKey, Cesium)
    }

    // OWM paid layers
    const apiKey = this._weatherApiKey()
    if (apiKey && cfg.owmId) {
      return new Cesium.UrlTemplateImageryProvider({
        url: `https://tile.openweathermap.org/map/${cfg.owmId}/{z}/{x}/{y}.png?appid=${apiKey}`,
        minimumLevel: 1,
        maximumLevel: 12,
        credit: new Cesium.Credit("OpenWeatherMap"),
      })
    }

    return null
  }

  GlobeController.prototype._fetchRainViewerMaps = async function() {
    // Cache the RainViewer response for 5 minutes
    if (this._rainViewerData && (Date.now() - this._rainViewerFetchedAt) < 300000) {
      return this._rainViewerData
    }
    try {
      const resp = await fetch("https://api.rainviewer.com/public/weather-maps.json")
      if (!resp.ok) return null
      this._rainViewerData = await resp.json()
      this._rainViewerFetchedAt = Date.now()
      return this._rainViewerData
    } catch {
      return null
    }
  }

  GlobeController.prototype._createRainViewerProvider = async function(layerKey, Cesium) {
    try {
      const data = await this._fetchRainViewerMaps()
      if (!data) return null

      const host = data.host || "https://tilecache.rainviewer.com"

      if (layerKey === "precipitation") {
        const frames = data.radar?.past || []
        if (frames.length === 0) return null
        const latest = frames[frames.length - 1]
        return new Cesium.UrlTemplateImageryProvider({
          url: `${host}${latest.path}/256/{z}/{x}/{y}/2/1_1.png`,
          minimumLevel: 1,
          maximumLevel: 7,
          credit: new Cesium.Credit("RainViewer"),
        })
      }

      if (layerKey === "clouds") {
        // Try satellite infrared first, fall back to radar coverage overlay
        const irFrames = data.satellite?.infrared || []
        if (irFrames.length > 0) {
          const latest = irFrames[irFrames.length - 1]
          return new Cesium.UrlTemplateImageryProvider({
            url: `${host}${latest.path}/256/{z}/{x}/{y}/0/0_0.png`,
            minimumLevel: 1,
            maximumLevel: 7,
            credit: new Cesium.Credit("RainViewer Satellite"),
          })
        }
        // Fallback: use radar coverage mask as a rough cloud indicator
        return new Cesium.UrlTemplateImageryProvider({
          url: `${host}/v2/coverage/0/256/{z}/{x}/{y}/0/0_0.png`,
          minimumLevel: 1,
          maximumLevel: 7,
          credit: new Cesium.Credit("RainViewer"),
        })
      }

      return null
    } catch (e) {
      console.warn("RainViewer provider failed:", e)
      return null
    }
  }

  // ── Opacity control ──────────────────────────────────────────

  GlobeController.prototype.setWeatherOpacity = function(event) {
    const val = parseFloat(event?.target?.value ?? event)
    this._weatherOpacity = val
    if (this._weatherImageryLayers) {
      for (const layer of Object.values(this._weatherImageryLayers)) {
        layer.alpha = val
      }
    }
    this._requestRender()
  }

  // ── Severe weather alerts (NWS for US, data points) ──────────

  GlobeController.prototype._fetchWeatherAlerts = async function() {
    try {
      const resp = await fetch("/api/weather_alerts")
      if (!resp.ok) return
      const data = await resp.json()
      this._weatherAlerts = data.alerts || []
      this._renderWeatherAlerts()
      this._markFresh("weather")
    } catch (e) {
      // Silent — alerts are optional enrichment
    }
  }

  GlobeController.prototype._renderWeatherAlerts = function() {
    const Cesium = window.Cesium
    this._clearWeatherAlertEntities()
    if (!this.weatherVisible || !this._weatherAlerts?.length) return

    const ds = this.getWeatherDataSource()
    ds.show = true
    this._weatherAlertEntities = []

    const severityColor = {
      "Extreme": cachedColor("#d50000", 0.8),
      "Severe":  cachedColor("#ff6d00", 0.8),
      "Moderate": cachedColor("#ffd600", 0.7),
      "Minor":   cachedColor("#00c853", 0.6),
    }

    this._weatherAlerts.forEach((alert, i) => {
      if (!alert.lat || !alert.lng) return
      if (this.hasActiveFilter() && !this.pointPassesFilter(alert.lat, alert.lng)) return

      const color = severityColor[alert.severity] || severityColor["Minor"]
      const entity = ds.entities.add({
        id: `wx-alert-${i}`,
        position: Cesium.Cartesian3.fromDegrees(alert.lng, alert.lat, 10),
        point: {
          pixelSize: alert.severity === "Extreme" ? 10 : 7,
          color,
          outlineColor: color.withAlpha(0.3),
          outlineWidth: 6,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.5, 1e7, 0.4),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: alert.event,
          font: "11px sans-serif",
          fillColor: Cesium.Color.WHITE,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 2,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -14),
          scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 5e6, 0),
          distanceDisplayCondition: new Cesium.DistanceDisplayCondition(0, 3e6),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        properties: {
          type: "weather_alert",
          _alert: alert,
        },
      })
      this._weatherAlertEntities.push(entity)
    })
    this._requestRender()
  }

  GlobeController.prototype._clearWeatherAlertEntities = function() {
    const ds = this._ds["weather"]
    if (ds && this._weatherAlertEntities) {
      this._weatherAlertEntities.forEach(e => ds.entities.remove(e))
    }
    this._weatherAlertEntities = []
  }

  // ── Remove all imagery layers ─────────────────────────────────

  GlobeController.prototype._removeAllWeatherLayers = function() {
    if (this._weatherImageryLayers) {
      for (const layer of Object.values(this._weatherImageryLayers)) {
        this.viewer.imageryLayers.remove(layer)
      }
    }
    this._weatherImageryLayers = {}
    this._weatherActiveLayers = {}
  }

  // ── API key ──────────────────────────────────────────────────

  GlobeController.prototype._weatherApiKey = function() {
    if (this.__owmKey !== undefined) return this.__owmKey
    const meta = document.querySelector('meta[name="owm-api-key"]')
    this.__owmKey = meta?.content || ""
    return this.__owmKey
  }

  // ── Weather panel UI ─────────────────────────────────────────

  GlobeController.prototype._ensureWeatherPanel = function() {
    if (this._weatherPanelBuilt) return
    this._weatherPanelBuilt = true

    const panel = this.element.querySelector('[data-globe-target="weatherPanel"]')
    if (!panel) return

    const apiKey = this._weatherApiKey()

    let html = '<div class="wx-chips">'
    for (const [key, cfg] of Object.entries(WEATHER_LAYERS)) {
      const disabled = !cfg.free && !apiKey
      html += `<button class="wx-chip${disabled ? ' wx-disabled' : ''}" data-wx-layer="${key}"
                data-action="click->globe#onWeatherChip"
                style="--wx-color: ${cfg.color};"${disabled ? ' title="Requires OWM paid plan"' : ''}>
                <i class="fa-solid ${cfg.icon}"></i> ${cfg.label}
              </button>`
    }
    html += '</div>'
    html += `<div class="wx-opacity">
      <label>Opacity</label>
      <input type="range" min="0.1" max="1" step="0.05" value="${this._weatherOpacity || 0.6}"
             data-action="input->globe#setWeatherOpacity">
    </div>`
    html += `<div class="wx-sat-sources" style="font:400 9px var(--gt-mono);color:var(--gt-text-dim);padding:4px 0 0;">
      <i class="fa-solid fa-satellite" style="color:#ffa726;margin-right:3px;"></i>
      Clouds: GOES · Meteosat · Himawari &nbsp;|&nbsp; Precip: ground radar + NOAA/Suomi NPP
    </div>
    <div style="font:400 9px var(--gt-mono);color:var(--gt-text-dim);padding:2px 0 0;">Rain & Clouds via RainViewer${!apiKey ? " · Temp/Wind/Hpa need OWM paid key" : ""}</div>`

    panel.innerHTML = html
  }

  GlobeController.prototype.onWeatherChip = function(event) {
    const btn = event.currentTarget
    if (btn.classList.contains("wx-disabled")) return
    const layerKey = btn.dataset.wxLayer
    if (layerKey) this.toggleWeatherSublayer(layerKey)
  }

  GlobeController.prototype._syncWeatherChips = function() {
    const chips = this.element.querySelectorAll(".wx-chip")
    chips.forEach(chip => {
      const key = chip.dataset.wxLayer
      chip.classList.toggle("active", !!(this._weatherActiveLayers && this._weatherActiveLayers[key]))
    })
  }

  GlobeController.prototype._showWeatherPanel = function(show) {
    const panel = this.element.querySelector('[data-globe-target="weatherPanel"]')
    if (panel) panel.style.display = show ? "" : "none"
  }

  // ── Weather ↔ Satellite link ────────────────────────────────

  // Auto-enable the "weather" satellite category so users see the source sats
  GlobeController.prototype._enableWeatherSatellites = function() {
    if (this.satCategoryVisible.weather) return // already on
    this.satCategoryVisible.weather = true
    if (!this._loadedSatCategories.has("weather")) {
      this.fetchSatCategory("weather")
    }
    // Sync checkbox if it exists
    const cb = this.element.querySelector('[data-category="weather"]')
    if (cb) cb.checked = true
  }

  // Draw dashed scan beams from geostationary weather sats to the ground
  // when the clouds (IR) layer is active — these are the sats providing imagery.
  GlobeController.prototype._renderWeatherSatBeams = function() {
    this._clearWeatherSatBeams()
    if (!this.weatherVisible) return

    const Cesium = window.Cesium
    const ds = this.getWeatherDataSource()
    this._weatherSatBeamEntities = []

    // Determine which source sats to highlight based on active layers
    const activeSources = []
    for (const layerKey of Object.keys(this._weatherActiveLayers || {})) {
      const sources = WEATHER_SAT_SOURCES[layerKey]
      if (sources) activeSources.push(...sources)
    }
    if (activeSources.length === 0) return

    // Find satellite positions and draw beams
    const clock = this.viewer.clock.currentTime
    for (const src of activeSources) {
      const satEntity = this._findSatelliteByNorad(src.norad)
      if (!satEntity) continue

      const satPos = satEntity.position?.getValue?.(clock)
      if (!satPos) continue

      const carto = Cesium.Cartographic.fromCartesian(satPos)
      const groundPos = Cesium.Cartesian3.fromRadians(carto.longitude, carto.latitude, 0)

      // Dashed beam line from satellite to ground (nadir point)
      const beam = ds.entities.add({
        id: `wx-beam-${src.norad}`,
        polyline: {
          positions: [satPos, groundPos],
          width: 1.5,
          material: new Cesium.PolylineDashMaterialProperty({
            color: cachedColor("#ffa726", 0.4),
            dashLength: 16,
          }),
          arcType: Cesium.ArcType.NONE,
        },
      })
      this._weatherSatBeamEntities.push(beam)

      // Small label at nadir showing satellite name + region
      const label = ds.entities.add({
        id: `wx-beam-lbl-${src.norad}`,
        position: groundPos,
        label: {
          text: `${src.name}\n${src.region}`,
          font: "10px JetBrains Mono, monospace",
          fillColor: cachedColor("#ffa726", 0.7),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.6),
          outlineWidth: 2,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, 14),
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1, 2e7, 0),
          translucencyByDistance: new Cesium.NearFarScalar(5e5, 1, 2e7, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._weatherSatBeamEntities.push(label)
    }
    this._requestRender()
  }

  GlobeController.prototype._clearWeatherSatBeams = function() {
    if (!this._weatherSatBeamEntities?.length) return
    const ds = this._ds["weather"]
    if (ds) {
      ds.entities.suspendEvents()
      this._weatherSatBeamEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._weatherSatBeamEntities = []
  }

  // ── Detail popup for weather alerts ───────────────────────────

  GlobeController.prototype.showWeatherAlertDetail = function(alert) {
    const severity = alert.severity || "Unknown"
    const urgency = alert.urgency || ""
    const headline = alert.headline || alert.event || "Weather Alert"
    const description = (alert.description || "").substring(0, 400)
    const areas = alert.areas || ""

    const html = `
      <div style="font-weight:600;font-size:14px;margin-bottom:6px;">${this._escapeHtml(headline)}</div>
      <div style="display:flex;gap:8px;margin-bottom:6px;">
        <span class="wx-severity wx-sev-${severity.toLowerCase()}">${severity}</span>
        ${urgency ? `<span style="font-size:11px;color:var(--gt-text-dim);">${urgency}</span>` : ""}
      </div>
      ${areas ? `<div style="font-size:11px;color:var(--gt-text-dim);margin-bottom:4px;">${this._escapeHtml(areas)}</div>` : ""}
      <div style="font-size:12px;line-height:1.4;color:var(--gt-text-sec);">${this._escapeHtml(description)}${description.length >= 400 ? "..." : ""}</div>
    `
    this._showDetail(html, "weather_alert")
  }
}
