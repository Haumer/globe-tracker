import { getDataSource } from "globe/utils"

export function applyPipelinesMethods(GlobeController) {
  GlobeController.prototype.getPipelinesDataSource = function() { return getDataSource(this.viewer, this._ds, "pipelines") }

  GlobeController.prototype.togglePipelines = function() {
    this.pipelinesVisible = this.hasPipelinesToggleTarget && this.pipelinesToggleTarget.checked
    if (this.pipelinesVisible) {
      this.fetchPipelines()
    } else {
      this._clearPipelineEntities()
      if (this._syncRightPanels) this._syncRightPanels()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchPipelines = async function() {
    this._toast("Loading pipelines...")
    try {
      const resp = await fetch("/api/pipelines")
      if (!resp.ok) return
      const data = await resp.json()
      const hasData = (data.pipelines?.length || 0) > 0
      this._handleBackgroundRefresh(resp, "pipelines", hasData, () => {
        if (this.pipelinesVisible) this.fetchPipelines()
      })
      this._pipelineData = data.pipelines || []
      this._renderPipelines(this._pipelineData)
      this._markFresh("pipelines")
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch pipelines:", e)
    }
  }

  GlobeController.prototype._renderPipelines = function(pipelines) {
    this._clearPipelineEntities()
    const Cesium = window.Cesium
    const dataSource = this.getPipelinesDataSource()

    const typeColors = {
      oil: "#ff6d00",
      gas: "#76ff03",
      products: "#ffab00",
    }

    const statusDash = {
      operational: false,
      under_construction: true,
      proposed: true,
      damaged: true,
    }

    dataSource.entities.suspendEvents()
    pipelines.forEach(pipe => {
      const coords = pipe.coordinates || []
      if (coords.length < 2) return

      // Apply country/circle filter if active
      if (this.hasActiveFilter()) {
        const mid = coords[Math.floor(coords.length / 2)]
        if (mid && !this.pointPassesFilter(mid[0], mid[1])) return
      }

      const color = pipe.color || typeColors[pipe.type] || "#ff6d00"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const isDashed = statusDash[pipe.status] || false
      const alpha = pipe.status === "proposed" ? 0.35 : pipe.status === "damaged" ? 0.5 : 0.7

      // Coordinates are [lat, lng] pairs — convert to Cesium positions
      const positions = coords.map(pt => Cesium.Cartesian3.fromDegrees(pt[1], pt[0], 100)).filter(p => p !== null)
      if (positions.length < 2) return

      let material
      if (isDashed) {
        material = new Cesium.PolylineDashMaterialProperty({
          color: cesiumColor.withAlpha(alpha),
          dashLength: 16,
        })
      } else {
        material = new Cesium.PolylineGlowMaterialProperty({
          glowPower: 0.1,
          color: cesiumColor.withAlpha(alpha),
        })
      }

      const entity = dataSource.entities.add({
        id: `pipeline-${pipe.id}`,
        polyline: {
          positions,
          width: pipe.type === "gas" ? 4 : 5,
          material,
          clampToGround: false,
        },
        properties: {
          pipelineName: pipe.name,
          pipelineId: pipe.id,
          pipelineType: pipe.type,
        },
      })
      this._pipelineEntities.push(entity)

      // Label at midpoint
      const midIdx = Math.floor(coords.length / 2)
      const midPt = coords[midIdx]
      const labelEntity = dataSource.entities.add({
        id: `pipeline-label-${pipe.id}`,
        position: Cesium.Cartesian3.fromDegrees(midPt[1], midPt[0], 200),
        label: {
          text: pipe.name,
          font: "11px JetBrains Mono, monospace",
          fillColor: cesiumColor.withAlpha(0.85),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1, 5e6, 0),
          translucencyByDistance: new Cesium.NearFarScalar(5e4, 1.0, 5e6, 0),
          pixelOffset: new Cesium.Cartesian2(0, -8),
        },
      })
      this._pipelineEntities.push(labelEntity)
    })
    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._clearPipelineEntities = function() {
    const ds = this.getPipelinesDataSource()
    ds.entities.suspendEvents()
    this._pipelineEntities.forEach(e => ds.entities.remove(e))
    ds.entities.resumeEvents()
    this._pipelineEntities = []
  }

  GlobeController.prototype.showPipelineDetail = function(id) {
    const p = (this._pipelineData || []).find(pipe => pipe.id === id)
    if (!p) return

    const typeColors = { oil: "#ff6d00", gas: "#76ff03", products: "#ffab00" }
    const color = p.color || typeColors[p.type] || "#ff6d00"
    const typeLabel = (p.type || "oil").charAt(0).toUpperCase() + (p.type || "oil").slice(1)
    const statusLabel = (p.status || "operational").replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase())

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-oil-well" style="margin-right:6px;"></i>${this._escapeHtml(p.name)}
      </div>
      <div class="detail-country">${this._escapeHtml(p.country || "—")}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Type</span>
          <span class="detail-value" style="color:${color};">${typeLabel}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Status</span>
          <span class="detail-value">${statusLabel}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Length</span>
          <span class="detail-value">${p.length_km ? p.length_km.toLocaleString() + " km" : "—"}</span>
        </div>
      </div>
      <div style="margin-top:8px; font-size:10px; opacity:0.5;">Data: <a href="https://globalenergymonitor.org" target="_blank" rel="noopener" style="color:inherit;">Global Energy Monitor</a> (CC BY 4.0)</div>
    `
    this.detailPanelTarget.style.display = ""
  }
}
