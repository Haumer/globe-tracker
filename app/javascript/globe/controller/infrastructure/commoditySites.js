import { getDataSource, LABEL_DEFAULTS } from "globe/utils"

const COMMODITY_STYLE = {
  oil_crude: { color: "#ef5350", symbol: "O", icon: "fa-solid fa-oil-well" },
  oil_refined: { color: "#ffb74d", symbol: "R", icon: "fa-solid fa-gas-pump" },
  gas_nat: { color: "#4fc3f7", symbol: "G", icon: "fa-solid fa-fire-flame-simple" },
  lng: { color: "#26c6da", symbol: "LNG", icon: "fa-solid fa-water" },
  helium: { color: "#7dd3fc", symbol: "He", icon: "fa-solid fa-circle-nodes" },
  copper: { color: "#ff7043", symbol: "Cu", icon: "fa-solid fa-industry" },
  iron_ore: { color: "#b0bec5", symbol: "Fe", icon: "fa-solid fa-mountain" },
  fertilizer: { color: "#9ccc65", symbol: "F", icon: "fa-solid fa-seedling" },
}

const iconCache = new Map()

function commodityStyle(key) {
  return COMMODITY_STYLE[key] || { color: "#b0bec5", symbol: "C", icon: "fa-solid fa-industry" }
}

function createCommoditySiteIcon(symbol, color) {
  const cacheKey = `${symbol}:${color}`
  if (iconCache.has(cacheKey)) return iconCache.get(cacheKey)

  const size = 28
  const canvas = document.createElement("canvas")
  canvas.width = size
  canvas.height = size
  const ctx = canvas.getContext("2d")
  const center = size / 2

  ctx.fillStyle = `${color}22`
  ctx.beginPath()
  ctx.arc(center, center, 12, 0, Math.PI * 2)
  ctx.fill()

  ctx.strokeStyle = color
  ctx.lineWidth = 1.6
  ctx.beginPath()
  ctx.arc(center, center, 11, 0, Math.PI * 2)
  ctx.stroke()

  ctx.fillStyle = color
  ctx.font = symbol.length > 1 ? "bold 10px JetBrains Mono, monospace" : "bold 12px JetBrains Mono, monospace"
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"
  ctx.fillText(symbol, center, center + 0.5)

  const url = canvas.toDataURL()
  iconCache.set(cacheKey, url)
  return url
}

function titleize(value) {
  return String(value || "unknown").replace(/_/g, " ").replace(/\b\w/g, char => char.toUpperCase())
}

export function applyCommoditySitesMethods(GlobeController) {
  GlobeController.prototype.getCommoditySitesDataSource = function() {
    return getDataSource(this.viewer, this._ds, "commodity-sites")
  }

  GlobeController.prototype.toggleCommoditySites = function() {
    this.commoditySitesVisible = this.hasCommoditySitesToggleTarget && this.commoditySitesToggleTarget.checked
    if (this.commoditySitesVisible) {
      this._ensureCommoditySiteData().then(() => this.renderCommoditySites())
      if (!this._commoditySiteCameraCb) {
        this._commoditySiteCameraCb = () => {
          if (!this.commoditySitesVisible) return
          this.renderCommoditySites()
        }
        this.viewer.camera.moveEnd.addEventListener(this._commoditySiteCameraCb)
      }
    } else {
      this._clearCommoditySiteEntities()
      if (this._commoditySiteCameraCb) {
        this.viewer.camera.moveEnd.removeEventListener(this._commoditySiteCameraCb)
        this._commoditySiteCameraCb = null
      }
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._ensureCommoditySiteData = async function() {
    if (this._commoditySiteAll?.length > 0) return

    this._toast("Loading commodity sites...")
    try {
      const resp = await fetch("/api/commodity_sites")
      if (!resp.ok) return
      const payload = await resp.json()
      const sites = Array.isArray(payload) ? payload : (payload.commodity_sites || [])
      this._commoditySiteAll = sites
      this._commoditySiteData = sites
      this._markFresh("commoditySites")
      this._toastHide()
    } catch (error) {
      console.error("Failed to fetch commodity sites:", error)
    }
  }

  GlobeController.prototype.renderCommoditySites = function() {
    if (!this.commoditySitesVisible || !this._commoditySiteAll?.length) return

    const Cesium = window.Cesium
    const dataSource = this.getCommoditySitesDataSource()
    const bounds = this.getViewportBounds()

    let visible = this._commoditySiteAll
    if (bounds) {
      visible = visible.filter(site =>
        site.lat >= bounds.lamin && site.lat <= bounds.lamax &&
        site.lng >= bounds.lomin && site.lng <= bounds.lomax
      )
    }
    if (this.hasActiveFilter()) {
      visible = visible.filter(site => this.pointPassesFilter(site.lat, site.lng))
    }
    visible = visible.slice(0, 200)

    dataSource.entities.suspendEvents()
    this._commoditySiteEntities.forEach(entity => dataSource.entities.remove(entity))
    this._commoditySiteEntities = []

    visible.forEach(site => {
      const style = commodityStyle(site.commodity_key)
      const cesiumColor = Cesium.Color.fromCssColorString(style.color)
      const entity = dataSource.entities.add({
        id: `comsite-${site.id}`,
        position: Cesium.Cartesian3.fromDegrees(site.lng, site.lat, 80),
        billboard: {
          image: createCommoditySiteIcon(style.symbol, style.color),
          scale: 0.78,
          scaleByDistance: new Cesium.NearFarScalar(6e4, 1.0, 8e6, 0.25),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: site.map_label || site.name,
          font: LABEL_DEFAULTS.font,
          fillColor: cesiumColor.withAlpha(0.9),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          pixelOffset: LABEL_DEFAULTS.pixelOffsetBelow(),
          scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
          translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._commoditySiteEntities.push(entity)
    })

    dataSource.entities.resumeEvents()
    this._requestRender()
    this._commoditySiteData = visible
  }

  GlobeController.prototype._clearCommoditySiteEntities = function() {
    const dataSource = this._ds["commodity-sites"]
    if (dataSource) {
      dataSource.entities.suspendEvents()
      this._commoditySiteEntities.forEach(entity => dataSource.entities.remove(entity))
      dataSource.entities.resumeEvents()
      this._requestRender()
    }
    this._commoditySiteEntities = []
  }

  GlobeController.prototype.showCommoditySiteDetail = function(site) {
    const style = commodityStyle(site.commodity_key)
    const products = Array.isArray(site.products) && site.products.length > 0 ? site.products.join(", ") : "—"
    const locationPrecision = site.location_precision ? titleize(site.location_precision) : "Site area"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${style.color};">
        <i class="${style.icon}" style="margin-right:6px;"></i>${this._escapeHtml(site.name)}
      </div>
      <div class="detail-country">${this._escapeHtml(site.location_label || site.country_name || "Unknown location")}</div>
      <div style="margin-top:4px;font:400 11px var(--gt-mono);color:#9fb2bc;">${this._escapeHtml(site.country_name || "Unknown country")}</div>
      <div class="detail-grid" style="margin-top:10px;">
        <div class="detail-field">
          <span class="detail-label">Commodity</span>
          <span class="detail-value" style="color:${style.color};">${this._escapeHtml(site.commodity_name || titleize(site.commodity_key))}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Stage</span>
          <span class="detail-value">${this._escapeHtml(titleize(site.stage))}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Type</span>
          <span class="detail-value">${this._escapeHtml(titleize(site.site_kind))}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Operator</span>
          <span class="detail-value">${this._escapeHtml(site.operator || "Unknown")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Products</span>
          <span class="detail-value">${this._escapeHtml(products)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Placement</span>
          <span class="detail-value">${this._escapeHtml(locationPrecision)}</span>
        </div>
      </div>
      <div style="margin-top:10px;font:400 11px var(--gt-mono);color:#b7c4cc;line-height:1.5;">${this._escapeHtml(site.summary || "")}</div>
      <a href="${site.source_url}" target="_blank" rel="noopener" class="detail-track-btn" style="margin-top:10px;">Open source →</a>
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.35);">Source: ${this._escapeHtml(site.source_name || "Curated source")} · ${this._escapeHtml(titleize(site.source_kind || "curated"))}</div>
    `
    this.detailPanelTarget.style.display = ""
  }
}
