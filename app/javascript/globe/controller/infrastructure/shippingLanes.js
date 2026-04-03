import { COUNTRY_CENTROIDS } from "globe/country_centroids"
import { cachedColor, getDataSource } from "globe/utils"
import { isLayerTemporarilyDisabled } from "globe/controller/ui_registry"

export function applyShippingLanesMethods(GlobeController) {
  GlobeController.prototype.getShippingLanesDataSource = function() { return getDataSource(this.viewer, this._ds, "shippingLanes") }

  GlobeController.prototype.toggleShippingLanes = function() {
    if (isLayerTemporarilyDisabled("shippingLanes")) {
      if (this.hasShippingLanesToggleTarget) this.shippingLanesToggleTarget.checked = false
      this.shippingLanesVisible = false
      this._toast?.("Shipping Lanes temporarily disabled during cleanup")
      this._syncQuickBar()
      this._savePrefs()
      return
    }

    this.shippingLanesVisible = this.hasShippingLanesToggleTarget && this.shippingLanesToggleTarget.checked
    if (this.shippingLanesVisible) {
      this.fetchShippingLanes()
    } else {
      this._clearShippingLaneEntities()
      if (this._syncRightPanels) this._syncRightPanels()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchShippingLanes = async function() {
    this._toast("Loading shipping lanes...")
    try {
      const resp = await fetch("/api/shipping_lanes")
      if (!resp.ok) return
      const data = await resp.json()
      const lanes = data.shipping_lanes || []
      const corridors = data.shipping_corridors || []
      const hasData = lanes.length > 0 || corridors.length > 0
      this._handleBackgroundRefresh(resp, "shipping-lanes", hasData, () => {
        if (this.shippingLanesVisible) this.fetchShippingLanes()
      })
      this._shippingLaneData = lanes
      this._shippingCorridorData = corridors
      this._renderShippingLanes(lanes, corridors)
      this._markFresh("shippingLanes")
      this._toastHide()
    } catch (error) {
      console.error("Failed to fetch shipping lanes:", error)
    }
  }

  GlobeController.prototype._renderShippingLanes = function(lanes, corridors = []) {
    this._clearShippingLaneEntities()
    const Cesium = window.Cesium
    const dataSource = this.getShippingLanesDataSource()

    dataSource.entities.suspendEvents()
    this._renderShippingCorridors(dataSource, corridors)
    lanes.forEach(lane => {
      const anchors = [lane.source_anchor, ...(lane.waypoints || []), lane.destination_anchor]
        .filter(Boolean)
        .map(anchor => this._resolveShippingAnchor(anchor))
        .filter(Boolean)
      const pathPoints = (lane.path_points || [])
        .map(point => this._resolveShippingAnchor(point))
        .filter(Boolean)
      const renderPoints = pathPoints.length >= 2 ? pathPoints : anchors
      if (renderPoints.length < 2) return

      if (this.hasActiveFilter() && !renderPoints.some(point => this.pointPassesFilter(point.lat, point.lng))) return

      const baseColor = cachedColor(lane.color || "#90a4ae", lane.status === "observed" ? 0.82 : 0.56)
      const positions = renderPoints.map(point => Cesium.Cartesian3.fromDegrees(point.lng, point.lat, 200))
      const width = lane.vulnerability_score >= 0.8 ? 5 : lane.vulnerability_score >= 0.55 ? 4 : 3

      const polyline = dataSource.entities.add({
        id: `shipping-lane-${lane.id}`,
        polyline: {
          positions,
          width,
          arcType: Cesium.ArcType.GEODESIC,
          clampToGround: false,
          material: lane.status === "observed"
            ? new Cesium.PolylineGlowMaterialProperty({
              glowPower: 0.12,
              color: baseColor,
            })
            : new Cesium.PolylineDashMaterialProperty({
              color: baseColor,
              dashLength: 14,
            }),
        },
        properties: {
          shippingLaneId: lane.id,
        },
      })
      this._shippingLaneEntities.push(polyline)

      this._renderShippingLaneAnchors(dataSource, lane, anchors, baseColor)
    })
    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._renderShippingCorridors = function(dataSource, corridors) {
    const Cesium = window.Cesium

    corridors.forEach(corridor => {
      const renderPoints = (corridor.path_points || [])
        .map(point => this._resolveShippingAnchor(point))
        .filter(Boolean)
      if (renderPoints.length < 2) return

      if (this.hasActiveFilter() && !renderPoints.some(point => this.pointPassesFilter(point.lat, point.lng))) return

      const isApproach = corridor.kind === "approach"
      const positions = renderPoints.map(point => Cesium.Cartesian3.fromDegrees(point.lng, point.lat, 120))

      const entity = dataSource.entities.add({
        id: `shipping-corridor-${corridor.id}`,
        polyline: {
          positions,
          width: isApproach ? 1.3 : 1.8,
          arcType: Cesium.ArcType.GEODESIC,
          clampToGround: false,
          material: isApproach
            ? new Cesium.PolylineDashMaterialProperty({
              color: cachedColor("#5f6f7a", 0.22),
              dashLength: 10,
            })
            : cachedColor("#5a6a74", 0.18),
        },
      })

      this._shippingLaneEntities.push(entity)
    })
  }

  GlobeController.prototype._renderShippingLaneAnchors = function(dataSource, lane, anchors, baseColor) {
    const Cesium = window.Cesium

    anchors.forEach((anchor, index) => {
      const entityId = anchor.kind === "chokepoint"
        ? `shipping-stop-${lane.id}-${index}`
        : `shipping-port-${lane.id}-${index}`
      const isEndpoint = index === 0 || index === anchors.length - 1
      const isStopover = anchor.role === "modeled_stopover"
      const pixelSize = anchor.kind === "chokepoint" ? 6 : isEndpoint ? 9 : 7
      const pointColor = anchor.kind === "chokepoint"
        ? cachedColor("#4fc3f7", 0.9)
        : isStopover
          ? cachedColor("#ffd54f", 0.9)
          : baseColor

      const entity = dataSource.entities.add({
        id: entityId,
        position: Cesium.Cartesian3.fromDegrees(anchor.lng, anchor.lat, 350),
        point: {
          pixelSize,
          color: pointColor,
          outlineColor: cachedColor("#06131a", 0.85),
          outlineWidth: 2,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.2, 5e6, 0.35),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: anchor.kind === "chokepoint" ? undefined : {
          text: anchor.name || "",
          font: "10px JetBrains Mono, monospace",
          fillColor: pointColor,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 2,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(0, -11),
          scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 2.2e6, 0),
          translucencyByDistance: new Cesium.NearFarScalar(1e4, 1.0, 3e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        properties: {
          shippingLaneId: lane.id,
        },
      })
      this._shippingLaneEntities.push(entity)
    })
  }

  GlobeController.prototype._resolveShippingAnchor = function(anchor) {
    if (!anchor) return null
    let lat = anchor.lat
    let lng = anchor.lng

    if ((lat == null || lng == null) && anchor.country_code) {
      const centroid = COUNTRY_CENTROIDS[anchor.country_code.toUpperCase()]
      if (centroid) [lat, lng] = centroid
    }

    if (lat == null || lng == null) return null

    return {
      ...anchor,
      lat: parseFloat(lat),
      lng: parseFloat(lng),
    }
  }

  GlobeController.prototype._clearShippingLaneEntities = function() {
    const ds = this.getShippingLanesDataSource()
    ds.entities.suspendEvents()
    this._shippingLaneEntities.forEach(entity => ds.entities.remove(entity))
    ds.entities.resumeEvents()
    this._shippingLaneEntities = []
  }

  GlobeController.prototype.showShippingLaneDetail = function(laneId) {
    const lane = (this._shippingLaneData || []).find(item => String(item.id) === String(laneId))
    if (!lane) return

    const routeParts = [lane.source_anchor, ...(lane.waypoints || []), lane.destination_anchor]
      .filter(Boolean)
      .map(anchor => this._resolveShippingAnchor(anchor) || anchor)
      .map(anchor => anchor.name)
      .filter(Boolean)
    const corridorParts = (lane.path_points || [])
      .map(point => this._resolveShippingAnchor(point) || point)
      .filter(point => point.path_role === "corridor")
      .map(point => point.name)
      .filter(Boolean)
    const stopovers = (lane.waypoints || []).filter(anchor => anchor.role === "modeled_stopover")
    const chokepoints = (lane.chokepoints || []).map(item => item.name)
    const partner = (lane.top_partners || [])[0]
    const modeLabel = lane.status === "observed" ? "Observed" : "Modeled"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${lane.color || "#90a4ae"};">
        <i class="fa-solid fa-route" style="margin-right:6px;"></i>${this._escapeHtml(lane.commodity_name || "Shipping lane")}
      </div>
      <div class="detail-country">${this._escapeHtml(lane.name || "Shipping corridor")}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Mode</span>
          <span class="detail-value">${modeLabel}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Vulnerability</span>
          <span class="detail-value">${((lane.vulnerability_score || 0) * 100).toFixed(0)}%</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Dependency</span>
          <span class="detail-value">${((lane.dependency_score || 0) * 100).toFixed(0)}%</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Route Pressure</span>
          <span class="detail-value">${((lane.exposure_score || 0) * 100).toFixed(0)}%</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Load</span>
          <span class="detail-value">${this._escapeHtml(lane.source_anchor?.name || lane.source_country?.name || "—")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Discharge</span>
          <span class="detail-value">${this._escapeHtml(lane.destination_anchor?.name || lane.destination_country?.name || "—")}</span>
        </div>
      </div>
      <div style="margin-top:10px;font:400 11px var(--gt-mono);color:#b7c4cc;line-height:1.5;">
        ${routeParts.length > 0 ? `<div><span style="color:#7aa7ba;">Route</span> ${this._escapeHtml(routeParts.join(" -> "))}</div>` : ""}
        ${corridorParts.length > 0 ? `<div><span style="color:#7aa7ba;">Water corridor</span> ${this._escapeHtml(corridorParts.join(" -> "))}</div>` : ""}
        ${chokepoints.length > 0 ? `<div><span style="color:#7aa7ba;">Vulnerable chokepoints</span> ${this._escapeHtml(chokepoints.join(", "))}</div>` : ""}
        ${stopovers.length > 0 ? `<div><span style="color:#7aa7ba;">Modeled stopovers</span> ${this._escapeHtml(stopovers.map(anchor => anchor.name).join(", "))}</div>` : ""}
        ${partner ? `<div><span style="color:#7aa7ba;">Top supplier</span> ${this._escapeHtml(partner.country_name || "—")} (${Number(partner.share_pct || 0).toFixed(1)}%)</div>` : ""}
      </div>
      ${lane.rationale ? `<div style="margin-top:10px;font:400 11px/1.5 var(--gt-sans);color:#d8e6ee;">${this._escapeHtml(lane.rationale)}</div>` : ""}
    `
    this.detailPanelTarget.style.display = ""
  }
}
