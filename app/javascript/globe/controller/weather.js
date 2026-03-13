import { getDataSource } from "../utils"

export function applyWeatherMethods(GlobeController) {

  // Available weather overlay layers
  // OWM layers need an API key; RainViewer is free (no key)
  const WEATHER_LAYERS = {
    precipitation: { label: "Rain",   icon: "fa-cloud-rain",      color: "#42a5f5", owmId: "precipitation_new" },
    clouds:        { label: "Clouds", icon: "fa-cloud",            color: "#90a4ae", owmId: "clouds_new" },
    temperature:   { label: "Temp",   icon: "fa-temperature-half", color: "#ef5350", owmId: "temp_new" },
    wind:          { label: "Wind",   icon: "fa-wind",             color: "#26c6da", owmId: "wind_new" },
    pressure:      { label: "Hpa",    icon: "fa-gauge-high",       color: "#ab47bc", owmId: "pressure_new" },
  }

  GlobeController.prototype.getWeatherDataSource = function() {
    return getDataSource(this.viewer, this._ds, "weather")
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
    } else {
      this._removeAllWeatherLayers()
      this._showWeatherPanel(false)
      this._clearWeatherAlertEntities()
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
    this._requestRender()
    this._savePrefs()
  }

  // ── Provider factory: OWM if key present, RainViewer for precip fallback ──

  GlobeController.prototype._createWeatherProvider = async function(layerKey, cfg, Cesium) {
    const apiKey = this._weatherApiKey()

    // Try OpenWeatherMap first (all layers supported)
    if (apiKey) {
      return new Cesium.UrlTemplateImageryProvider({
        url: `https://tile.openweathermap.org/map/${cfg.owmId}/{z}/{x}/{y}.png?appid=${apiKey}`,
        minimumLevel: 1,
        maximumLevel: 12,
        credit: new Cesium.Credit("OpenWeatherMap"),
      })
    }

    // Fallback: RainViewer for precipitation (free, no key)
    if (layerKey === "precipitation") {
      return await this._createRainViewerProvider(Cesium)
    }

    // Other layers need OWM key
    return null
  }

  GlobeController.prototype._createRainViewerProvider = async function(Cesium) {
    try {
      // RainViewer provides the latest radar frame timestamp
      const resp = await fetch("https://api.rainviewer.com/public/weather-maps.json")
      if (!resp.ok) return null
      const data = await resp.json()
      const frames = data.radar?.past || []
      if (frames.length === 0) return null
      const latest = frames[frames.length - 1]

      return new Cesium.UrlTemplateImageryProvider({
        url: `https://tilecache.rainviewer.com/v2/radar/${latest.path}/256/{z}/{x}/{y}/2/1_1.png`,
        minimumLevel: 1,
        maximumLevel: 12,
        credit: new Cesium.Credit("RainViewer"),
      })
    } catch (e) {
      console.warn("RainViewer fallback failed:", e)
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
      "Extreme": Cesium.Color.fromCssColorString("#d50000").withAlpha(0.8),
      "Severe":  Cesium.Color.fromCssColorString("#ff6d00").withAlpha(0.8),
      "Moderate": Cesium.Color.fromCssColorString("#ffd600").withAlpha(0.7),
      "Minor":   Cesium.Color.fromCssColorString("#00c853").withAlpha(0.6),
    }

    this._weatherAlerts.forEach((alert, i) => {
      if (!alert.lat || !alert.lng) return
      if (this.hasActiveFilter() && !this.pointPassesFilter(alert.lat, alert.lng)) return

      const color = severityColor[alert.severity] || severityColor["Minor"]
      const entity = ds.entities.add({
        id: `wx-alert-${i}`,
        position: Cesium.Cartesian3.fromDegrees(alert.lng, alert.lat, 500),
        point: {
          pixelSize: alert.severity === "Extreme" ? 10 : 7,
          color,
          outlineColor: color.withAlpha(0.3),
          outlineWidth: 6,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.5, 1e7, 0.4),
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
      // Without OWM key, only precipitation (RainViewer fallback) is available
      const disabled = !apiKey && key !== "precipitation"
      html += `<button class="wx-chip${disabled ? ' wx-disabled' : ''}" data-wx-layer="${key}"
                data-action="click->globe#onWeatherChip"
                style="--wx-color: ${cfg.color};"${disabled ? ' title="Requires OPENWEATHERMAP_API_KEY"' : ''}>
                <i class="fa-solid ${cfg.icon}"></i> ${cfg.label}
              </button>`
    }
    html += '</div>'
    html += `<div class="wx-opacity">
      <label>Opacity</label>
      <input type="range" min="0.1" max="1" step="0.05" value="${this._weatherOpacity || 0.6}"
             data-action="input->globe#setWeatherOpacity">
    </div>`
    if (!apiKey) {
      html += `<div style="font:400 9px var(--gt-mono);color:var(--gt-text-dim);padding:4px 0 0;">Rain via RainViewer · Add OPENWEATHERMAP_API_KEY for all layers</div>`
    }

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
