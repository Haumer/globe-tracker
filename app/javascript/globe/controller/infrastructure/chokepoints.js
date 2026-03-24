import { getDataSource } from "../../utils"

export function applyChokepointsMethods(GlobeController) {

  GlobeController.prototype.toggleChokepoints = function() {
    this.chokepointsVisible = this.hasChokepointsToggleTarget && this.chokepointsToggleTarget.checked
    if (this.chokepointsVisible) {
      this.fetchChokepoints()
    } else {
      this._clearChokepointEntities()
      if (this._syncRightPanels) this._syncRightPanels()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchChokepoints = async function() {
    this._toast("Loading chokepoints...")
    try {
      const resp = await fetch("/api/chokepoints")
      if (!resp.ok) return
      const data = await resp.json()
      this._chokepointData = data.chokepoints || []
      this._renderChokepoints()
      this._toastHide()
    } catch (e) {
      console.warn("Chokepoint fetch failed:", e)
    }
  }

  GlobeController.prototype._renderChokepoints = function() {
    this._clearChokepointEntities()
    const Cesium = window.Cesium
    const ds = getDataSource(this.viewer, this._ds, "chokepoints")

    if (!this._chokepointData?.length) return

    const statusColors = {
      critical: "#f44336",
      elevated: "#ff9800",
      monitoring: "#ffc107",
      normal: "#4fc3f7",
    }

    ds.entities.suspendEvents()
    this._chokepointData.forEach((cp, idx) => {
      const color = Cesium.Color.fromCssColorString(statusColors[cp.status] || "#4fc3f7")
      const radiusM = (cp.radius_km || 30) * 1000

      // Shipping lane zone circle
      const zone = ds.entities.add({
        id: `choke-zone-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(cp.lng, cp.lat),
        ellipse: {
          semiMajorAxis: radiusM,
          semiMinorAxis: radiusM,
          material: color.withAlpha(cp.status === "normal" ? 0.03 : 0.08),
          outline: true,
          outlineColor: color.withAlpha(cp.status === "normal" ? 0.2 : 0.5),
          outlineWidth: cp.status === "normal" ? 1 : 2,
          height: 4000,
        },
      })
      this._chokepointEntities.push(zone)

      // Clickable billboard
      const iconSize = cp.status === "critical" ? 36 : (cp.status === "normal" ? 28 : 32)
      const point = ds.entities.add({
        id: `choke-${idx}`,
        position: Cesium.Cartesian3.fromDegrees(cp.lng, cp.lat, 4500),
        billboard: {
          image: this._makeChokepointIcon(cp, statusColors[cp.status] || "#4fc3f7"),
          width: iconSize,
          height: iconSize,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1.0, 2e7, 0.3),
        },
        label: {
          text: cp.name,
          font: "bold 10px 'JetBrains Mono', monospace",
          fillColor: color.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, iconSize / 2 + 4),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1.0, 2e7, 0.25),
          translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, 2e7, 0.0),
        },
      })
      this._chokepointEntities.push(point)

      // Ship count label (if ships detected)
      if (cp.ships_nearby?.total > 0) {
        const shipLabel = ds.entities.add({
          id: `choke-ships-${idx}`,
          position: Cesium.Cartesian3.fromDegrees(cp.lng, cp.lat, 4500),
          label: {
            text: `${cp.ships_nearby.total} ships`,
            font: "10px 'JetBrains Mono', monospace",
            fillColor: Cesium.Color.fromCssColorString("#26c6da").withAlpha(0.8),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 2,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            pixelOffset: new Cesium.Cartesian2(0, -(iconSize / 2 + 4)),
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
            scaleByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1e7, 0.3),
            translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1e7, 0.0),
          },
        })
        this._chokepointEntities.push(shipLabel)
      }
    })
    ds.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._makeChokepointIcon = function(cp, color) {
    const key = `choke-${cp.id}-${cp.status}`
    if (this._iconCache?.[key]) return this._iconCache[key]
    if (!this._iconCache) this._iconCache = {}

    const size = 36
    const canvas = document.createElement("canvas")
    canvas.width = size; canvas.height = size
    const ctx = canvas.getContext("2d")

    // Background
    ctx.beginPath()
    ctx.arc(size / 2, size / 2, size / 2 - 1, 0, Math.PI * 2)
    ctx.fillStyle = "rgba(0,0,0,0.8)"
    ctx.fill()
    ctx.strokeStyle = color
    ctx.lineWidth = 2.5
    ctx.stroke()

    // Anchor icon
    ctx.font = "16px sans-serif"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = color
    ctx.fillText("\u2693", size / 2, size / 2)

    const url = canvas.toDataURL()
    this._iconCache[key] = url
    return url
  }

  GlobeController.prototype._clearChokepointEntities = function() {
    const ds = this._ds["chokepoints"]
    if (ds && this._chokepointEntities?.length) {
      ds.entities.suspendEvents()
      this._chokepointEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._chokepointEntities = []
  }

  // ── Click handler detail panel ─────────────────────────────

  GlobeController.prototype.showChokepointDetail = function(cp) {
    const statusColors = { critical: "#f44336", elevated: "#ff9800", monitoring: "#ffc107", normal: "#4fc3f7" }
    const color = statusColors[cp.status] || "#4fc3f7"

    // Flow chips
    let flowsHtml = ""
    if (cp.flows) {
      Object.entries(cp.flows).forEach(([type, data]) => {
        if (!data.pct) return
        flowsHtml += `<div style="display:flex;justify-content:space-between;padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
          <span style="font:600 11px var(--gt-mono);color:#e0e0e0;text-transform:capitalize;">${type}</span>
          <span style="font:700 11px var(--gt-mono);color:${color};">${data.pct}% of world</span>
        </div>`
        if (data.volume) flowsHtml += `<div style="font:400 9px var(--gt-mono);color:#888;padding:1px 0 4px;">${data.volume}</div>`
        if (data.note) flowsHtml += `<div style="font:400 9px var(--gt-mono);color:#666;padding:1px 0 4px;">${data.note}</div>`
      })
    }

    // Commodity signals
    let commodityHtml = ""
    if (cp.commodity_signals?.length) {
      commodityHtml = cp.commodity_signals.map(c => {
        const isUp = c.change_pct > 0
        const cColor = isUp ? "#4caf50" : c.change_pct < 0 ? "#f44336" : "#888"
        const changeStr = c.change_pct != null ? `${isUp ? "+" : ""}${c.change_pct}%` : ""
        return `<span class="detail-chip" style="background:rgba(${isUp ? "76,175,80" : "244,67,54"},0.15);color:${cColor};">${c.symbol} $${c.price} ${changeStr}</span>`
      }).join("")
    }

    // Risk factors
    const risksHtml = (cp.risk_factors || []).map(r =>
      `<div style="font:400 10px var(--gt-mono);color:#ff9800;padding:2px 0;">- ${this._escapeHtml(r)}</div>`
    ).join("")

    // Ships
    const ships = cp.ships_nearby || {}

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-anchor" style="margin-right:6px;"></i>${this._escapeHtml(cp.name)}
      </div>
      <div style="display:inline-block;padding:2px 8px;border-radius:3px;background:${color};color:#000;font:700 10px var(--gt-mono);letter-spacing:1px;margin-bottom:8px;">
        ${cp.status.toUpperCase()}
      </div>
      <div style="font:400 10px var(--gt-mono);color:#aaa;margin-bottom:10px;line-height:1.4;">
        ${this._escapeHtml(cp.description || "")}
      </div>

      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Ships</span>
          <span class="detail-value" style="color:#26c6da;">${ships.total || 0}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Tankers</span>
          <span class="detail-value">${ships.tankers || 0}</span>
        </div>
      </div>

      ${flowsHtml ? `
        <div style="margin:10px 0;">
          <div style="font:600 9px var(--gt-mono);color:#888;letter-spacing:1px;margin-bottom:6px;">TRADE FLOWS</div>
          ${flowsHtml}
        </div>
      ` : ""}

      ${commodityHtml ? `
        <div style="margin:10px 0;">
          <div style="font:600 9px var(--gt-mono);color:#888;letter-spacing:1px;margin-bottom:6px;">MARKET SIGNALS</div>
          <div style="display:flex;flex-wrap:wrap;gap:4px;">${commodityHtml}</div>
        </div>
      ` : ""}

      ${cp.conflict_pulse?.length ? `
        <div style="margin:10px 0;">
          <div style="font:600 9px var(--gt-mono);color:#888;letter-spacing:1px;margin-bottom:6px;">CONFLICT NEARBY</div>
          ${cp.conflict_pulse.map(p => `<span class="detail-chip" style="background:rgba(244,67,54,0.15);color:#f44336;">${p.trend} (${p.score})</span>`).join("")}
        </div>
      ` : ""}

      ${risksHtml ? `
        <div style="margin:10px 0;">
          <div style="font:600 9px var(--gt-mono);color:#888;letter-spacing:1px;margin-bottom:6px;">RISK FACTORS</div>
          ${risksHtml}
        </div>
      ` : ""}

      <button class="detail-track-btn" style="background:rgba(244,67,54,0.2);border-color:rgba(244,67,54,0.4);color:#f44336;" data-action="click->globe#revealPulseConnections" data-lat="${cp.lat}" data-lng="${cp.lng}" data-signals="${this._escapeHtml(JSON.stringify(cp.conflict_pulse?.length ? { military_flights: 1 } : {}))}">
        <i class="fa-solid fa-eye" style="margin-right:4px;"></i>Reveal Connected Layers
      </button>

      <button class="detail-track-btn" style="background:rgba(38,198,218,0.15);border-color:rgba(38,198,218,0.3);color:#26c6da;" data-action="click->globe#showSatVisibility" data-lat="${cp.lat}" data-lng="${cp.lng}">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
      </button>

      ${this._connectionsPlaceholder()}
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: EIA / UNCTAD / S&P Global</div>
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("ship", cp.lat, cp.lng)
  }
}
