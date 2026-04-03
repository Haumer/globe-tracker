import { cachedColor, getDataSource, LABEL_DEFAULTS } from "globe/utils"

function portColor(primaryFlowType) {
  switch (primaryFlowType) {
    case "oil": return "#ff8a00"
    case "lng": return "#26c6da"
    case "grain": return "#fbc02d"
    case "semiconductors": return "#42a5f5"
    default: return "#8bc34a"
  }
}

function titleizeFlowType(value) {
  return String(value || "").replace(/_/g, " ").replace(/\b\w/g, char => char.toUpperCase())
}

export function applyPortsMethods(GlobeController) {
  GlobeController.prototype.getPortsDataSource = function() { return getDataSource(this.viewer, this._ds, "ports") }

  GlobeController.prototype.togglePorts = function() {
    this.portsVisible = this.hasPortsToggleTarget && this.portsToggleTarget.checked
    if (this.portsVisible) {
      this._ensurePortData().then(() => this.renderPorts())
      if (!this._portCameraCb) {
        this._portCameraCb = () => {
          if (!this.portsVisible) return
          clearTimeout(this._portDebounce)
          this._portDebounce = setTimeout(() => this.renderPorts(), 220)
        }
        this.viewer.camera.moveEnd.addEventListener(this._portCameraCb)
      }
    } else {
      this._clearPortEntities()
      if (this._portCameraCb) {
        this.viewer.camera.moveEnd.removeEventListener(this._portCameraCb)
        this._portCameraCb = null
      }
      if (this._syncRightPanels) this._syncRightPanels()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._ensurePortData = async function() {
    if (this._portAll?.length > 0) return
    this._toast("Loading ports...")
    try {
      const resp = await fetch("/api/ports")
      if (!resp.ok) return
      const data = await resp.json()
      const ports = data.ports || []
      const hasData = ports.length > 0
      this._handleBackgroundRefresh(resp, "ports", hasData, () => {
        if (this.portsVisible) this._ensurePortData().then(() => this.renderPorts())
      })
      this._portAll = ports
      this._markFresh("ports")
      this._toastHide()
    } catch (error) {
      console.error("Failed to fetch ports:", error)
    }
  }

  GlobeController.prototype.renderPorts = function() {
    if (!this._portAll || !this.portsVisible) return

    const Cesium = window.Cesium
    const dataSource = this.getPortsDataSource()
    const bounds = this.getViewportBounds()

    let visible = this._portAll
    if (bounds) {
      visible = visible.filter(port =>
        port.lat >= bounds.lamin && port.lat <= bounds.lamax &&
        port.lng >= bounds.lomin && port.lng <= bounds.lomax
      )
    }
    if (this.hasActiveFilter()) {
      visible = visible.filter(port => this.pointPassesFilter(port.lat, port.lng))
    }
    visible = visible
      .sort((left, right) => (right.importance_score || 0) - (left.importance_score || 0))
      .slice(0, 1200)

    const labelBudget = visible.length > 650 ? 90 : visible.length > 320 ? 150 : 240

    dataSource.entities.suspendEvents()
    this._portEntities.forEach(entity => dataSource.entities.remove(entity))
    this._portEntities = []

    visible.forEach((port, index) => {
      const color = portColor(port.primary_flow_type)
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const importance = port.importance_score || 0.5
      const pixelSize = importance >= 0.88 ? 11 : importance >= 0.72 ? 9 : 7
      const labelText = port.map_label || port.name
      const showLabel = Boolean(labelText) && index < labelBudget && (importance >= 0.58 || !port.estimated)

      const entity = dataSource.entities.add({
        id: `port-${port.id}`,
        position: Cesium.Cartesian3.fromDegrees(port.lng, port.lat, 120),
        point: {
          pixelSize,
          color: cesiumColor.withAlpha(port.estimated ? 0.72 : 0.88),
          outlineColor: cachedColor("#06131a", 0.88),
          outlineWidth: 2,
          scaleByDistance: new Cesium.NearFarScalar(7.5e4, 1.0, 8e6, 0.35),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: showLabel ? {
          text: labelText,
          font: LABEL_DEFAULTS.font,
          fillColor: cesiumColor.withAlpha(0.9),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          pixelOffset: LABEL_DEFAULTS.pixelOffsetBelow(),
          scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
          translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        } : undefined,
        properties: {
          portId: port.id,
        },
      })

      this._portEntities.push(entity)
    })

    dataSource.entities.resumeEvents()
    this._requestRender()
    this._portData = visible
  }

  GlobeController.prototype.showPortDetail = function(portId) {
    const port = (this._portAll || []).find(item => String(item.id) === String(portId))
    if (!port) return

    const goods = (port.estimated_commodity_names || []).slice(0, 5)
    const flowTypes = (port.flow_types || []).map(titleizeFlowType)
    const dependencyHints = (port.country_dependency_commodities || []).slice(0, 3)
    const modeLabel = port.estimated ? "Modeled + catalog" : "Observed trade location"
    const placeLabel = port.place_label || port.country_name || port.country_code_alpha3 || "Unknown country"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${portColor(port.primary_flow_type)};">
        <i class="fa-solid fa-anchor" style="margin-right:6px;"></i>Port
      </div>
      <div class="detail-country">${this._escapeHtml(port.name)}</div>
      <div style="margin-top:4px;font:400 11px var(--gt-mono);color:#9fb2bc;">${this._escapeHtml(placeLabel)}</div>
      <div class="detail-grid" style="margin-top:10px;">
        <div class="detail-field">
          <span class="detail-label">Mode</span>
          <span class="detail-value">${this._escapeHtml(modeLabel)}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Importance</span>
          <span class="detail-value">${this._escapeHtml(port.importance_tier || "local")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">LOCODE</span>
          <span class="detail-value">${this._escapeHtml(port.locode || "—")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Source</span>
          <span class="detail-value">${this._escapeHtml(port.source || "catalog_prior")}</span>
        </div>
      </div>
      <div style="margin-top:10px;font:400 11px var(--gt-mono);color:#b7c4cc;line-height:1.5;">
        ${flowTypes.length > 0 ? `<div><span style="color:#7aa7ba;">Flow types</span> ${this._escapeHtml(flowTypes.join(", "))}</div>` : ""}
        ${goods.length > 0 ? `<div><span style="color:#7aa7ba;">Estimated goods</span> ${this._escapeHtml(goods.join(", "))}</div>` : ""}
        ${dependencyHints.length > 0 ? `<div><span style="color:#7aa7ba;">Country demand signals</span> ${this._escapeHtml(dependencyHints.join(", "))}</div>` : ""}
      </div>
    `
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype._clearPortEntities = function() {
    const dataSource = this.getPortsDataSource()
    dataSource.entities.suspendEvents()
    this._portEntities.forEach(entity => dataSource.entities.remove(entity))
    dataSource.entities.resumeEvents()
    this._portEntities = []
  }
}
