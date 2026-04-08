import { getDataSource } from "globe/utils"

export function applyChokepointsMethods(GlobeController) {

  GlobeController.prototype.toggleChokepoints = function() {
    this.chokepointsVisible = this.hasChokepointsToggleTarget && this.chokepointsToggleTarget.checked
    if (this.chokepointsVisible) {
      this.fetchChokepoints()
    } else {
      this._clearChokepointEntities()
      if (this._syncRightPanels) this._syncRightPanels()
    }
    if (this.insightsVisible && this._renderInsightMarkers) this._renderInsightMarkers()
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
      this._chokepointSnapshotStatus = data.snapshot_status || "ready"
      this._renderChokepoints()
      if (this._chokepointSnapshotStatus === "ready") {
        this._toastHide()
      } else {
        this._toast(`Chokepoints: ${this._statusLabel(this._chokepointSnapshotStatus, "snapshot")}`)
      }
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
      const chokepointId = cp.id || `idx-${idx}`
      const color = Cesium.Color.fromCssColorString(statusColors[cp.status] || "#4fc3f7")
      const radiusM = (cp.radius_km || 30) * 1000

      // Shipping lane zone circle
      const zone = ds.entities.add({
        id: `choke-zone-${chokepointId}`,
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
        id: `choke-${chokepointId}`,
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
          id: `choke-ships-${chokepointId}`,
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
    if (this._updateGlobeOcclusion) this._updateGlobeOcclusion()
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

  GlobeController.prototype._upsertChokepointDataRecord = function(chokepoint) {
    if (!chokepoint) return

    const id = chokepoint.id || chokepoint.name
    if (!id) return

    const current = Array.isArray(this._chokepointData) ? [...this._chokepointData] : []
    const idx = current.findIndex((entry) => `${entry.id || entry.name}` === `${id}`)
    if (idx === -1) current.push(chokepoint)
    else current[idx] = { ...current[idx], ...chokepoint }
    this._chokepointData = current
  }

  // ── Click handler detail panel ─────────────────────────────

  GlobeController.prototype.showChokepointDetail = function(cpOrId, options = {}) {
    const identifier = typeof cpOrId === "string"
      ? cpOrId
      : (cpOrId?.id || cpOrId?.name)
    const cp = typeof cpOrId === "string"
      ? (this._findChokepointById?.(cpOrId) || { id: cpOrId, name: cpOrId, status: "monitoring" })
      : cpOrId
    if (!cp || !identifier) return

    if (!options.contextOnly && this._showCompactEntityDetail) {
      this._showCompactEntityDetail("chokepoint", cp, { id: identifier, picked: options.picked })
    }

    const baseContext = this._buildChokepointContext
      ? this._buildChokepointContext(cp)
      : null

    if (!baseContext || !this._setSelectedContext) return

    this._setSelectedContext(baseContext, {
      openRightPanel: options.openRightPanel === true || options.contextOnly !== true,
    })

    if (this.hasDetailPanelTarget) this.detailPanelTarget.style.display = "none"

    this._chokepointLensRequestKey = `${identifier}:${Date.now()}`
    const requestKey = this._chokepointLensRequestKey

    fetch(`/api/chokepoints/${encodeURIComponent(identifier)}`)
      .then(resp => {
        if (!resp.ok) throw new Error(`Chokepoint lens HTTP ${resp.status}`)
        return resp.json()
      })
      .then((data) => {
        if (this._chokepointLensRequestKey !== requestKey) return
        const enriched = data.chokepoint || cp
        this._upsertChokepointDataRecord(enriched)
        if (!this._selectedContext || this._selectedContext.kind !== "chokepoint") return
        const selectedId = this._selectedContext.nodeRequest?.id || this._selectedContext.title
        if (`${selectedId || ""}` !== `${identifier}` && `${this._selectedContext.title || ""}` !== `${enriched.name || ""}`) return
        this._setSelectedContext(this._buildChokepointContext(enriched), {
          openRightPanel: this._isRightPanelVisible?.() === true,
        })
      })
      .catch((error) => {
        console.warn("Chokepoint lens failed:", error)
      })
  }
}
