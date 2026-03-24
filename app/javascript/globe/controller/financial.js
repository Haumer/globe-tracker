import { getDataSource } from "../utils"

export function applyFinancialMethods(GlobeController) {

  GlobeController.prototype.toggleFinancial = function() {
    this.financialVisible = !this.financialVisible
    if (this.financialVisible) {
      this.fetchCommodities()
    } else {
      this._clearFinancialEntities()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchCommodities = async function() {
    try {
      const resp = await fetch("/api/commodities")
      if (!resp.ok) return
      const data = await resp.json()
      this._commodityData = data.prices || []
      this._renderCommodities()
      this._markFresh("financial")
    } catch (e) {
      console.warn("Commodity fetch failed:", e)
    }
  }

  GlobeController.prototype._renderCommodities = function() {
    const Cesium = window.Cesium
    const ds = getDataSource(this.viewer, this._ds, "financial")
    this._clearFinancialEntities()
    this._financialEntities = []

    if (!this._commodityData?.length) return

    this._commodityData.forEach((item, idx) => {
      if (item.lat == null || item.lng == null) return

      const isUp = item.change_pct > 0
      const isDown = item.change_pct < 0
      const color = isUp
        ? Cesium.Color.fromCssColorString("#4caf50")
        : isDown
          ? Cesium.Color.fromCssColorString("#f44336")
          : Cesium.Color.fromCssColorString("#ffc107")

      const isCommodity = item.category === "commodity"
      const changeStr = item.change_pct != null
        ? `${isUp ? "+" : ""}${item.change_pct.toFixed(2)}%`
        : ""
      const priceStr = item.category === "currency"
        ? `$${item.price.toFixed(4)}`
        : `$${item.price.toFixed(2)}`

      // Main label
      const label = ds.entities.add({
        id: `fin-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(item.lng, item.lat, 0),
        billboard: {
          image: this._makeFinancialIcon(item.symbol, color.toCssColorString(), isCommodity),
          width: 32,
          height: 32,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1e7, 0.5),
        },
        label: {
          text: `${item.symbol}\n${priceStr} ${changeStr}`,
          font: "10px JetBrains Mono, monospace",
          fillColor: color,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 2,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, 24),
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1e7, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1.5e7, 0.0),
        },
      })
      this._financialEntities.push(label)
    })

    this._requestRender()
  }

  GlobeController.prototype._makeFinancialIcon = function(symbol, color, isCommodity) {
    const key = `fin-${symbol}-${color}`
    if (this._iconCache?.[key]) return this._iconCache[key]
    if (!this._iconCache) this._iconCache = {}

    const size = 32
    const canvas = document.createElement("canvas")
    canvas.width = size; canvas.height = size
    const ctx = canvas.getContext("2d")

    // Background circle
    ctx.beginPath()
    ctx.arc(size / 2, size / 2, size / 2 - 1, 0, Math.PI * 2)
    ctx.fillStyle = "rgba(0,0,0,0.75)"
    ctx.fill()
    ctx.strokeStyle = color
    ctx.lineWidth = 2
    ctx.stroke()

    // Symbol icon
    ctx.font = isCommodity ? "14px sans-serif" : "bold 12px 'JetBrains Mono', monospace"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = color

    const icons = {
      OIL_WTI: "🛢️", OIL_BRENT: "🛢️", GAS_NAT: "🔥", GOLD: "🥇",
      SILVER: "🥈", COPPER: "🟤", WHEAT: "🌾", IRON: "⛏️",
      LNG: "⛽", URANIUM: "☢️",
    }
    ctx.fillText(icons[symbol] || "$", size / 2, size / 2)

    const url = canvas.toDataURL()
    this._iconCache[key] = url
    return url
  }

  GlobeController.prototype._clearFinancialEntities = function() {
    const ds = this._ds["financial"]
    if (ds && this._financialEntities?.length) {
      this._financialEntities.forEach(e => ds.entities.remove(e))
    }
    this._financialEntities = []
  }

  GlobeController.prototype.showCommodityDetail = function(item) {
    const isUp = item.change_pct > 0
    const changeColor = isUp ? "#4caf50" : item.change_pct < 0 ? "#f44336" : "#ffc107"
    const changeStr = item.change_pct != null
      ? `${isUp ? "+" : ""}${item.change_pct.toFixed(2)}%`
      : "—"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${changeColor};">${item.name}</div>
      <div class="detail-country">${item.region}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Price</span>
          <span class="detail-value">$${item.price.toFixed(item.category === "currency" ? 4 : 2)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Change</span>
          <span class="detail-value" style="color:${changeColor};">${changeStr}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Unit</span>
          <span class="detail-value">${item.unit || "—"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Category</span>
          <span class="detail-value">${item.category}</span>
        </div>
      </div>
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: Alpha Vantage / ECB</div>
    `
    this.detailPanelTarget.style.display = ""
  }
}
