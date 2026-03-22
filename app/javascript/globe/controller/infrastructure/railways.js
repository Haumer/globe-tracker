import { getDataSource, cachedColor } from "../../utils"

export function applyRailwaysMethods(GlobeController) {
  GlobeController.prototype.getRailwaysDataSource = function() { return getDataSource(this.viewer, this._ds, "railways") }

  GlobeController.prototype.toggleRailways = function() {
    this.railwaysVisible = this.hasRailwaysToggleTarget && this.railwaysToggleTarget.checked
    if (this.railwaysVisible) {
      this.fetchRailways()
      if (!this._rwCameraCb) {
        this._rwCameraCb = () => {
          if (!this.railwaysVisible) return
          clearTimeout(this._rwDebounce)
          this._rwDebounce = setTimeout(() => this.fetchRailways(), 300)
        }
        this.viewer.camera.moveEnd.addEventListener(this._rwCameraCb)
      }
    } else {
      this._clearRailwayEntities()
      if (this._rwCameraCb) { this.viewer.camera.moveEnd.removeEventListener(this._rwCameraCb); this._rwCameraCb = null }
      if (this._syncRightPanels) this._syncRightPanels()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchRailways = async function() {
    if (this._rwFetching) return
    this._rwFetching = true

    let url = "/api/railways"
    const bounds = this.getViewportBounds() || this.getFilterBounds()
    if (bounds) {
      url += `?bbox=${bounds.lamin},${bounds.lomin},${bounds.lamax},${bounds.lomax}`
    }

    try {
      const resp = await fetch(url)
      if (!resp.ok) return
      const raw = await resp.json()
      this._railwayData = raw.map(r => ({
        id: r[0], category: r[1], electrified: r[2],
        continent: r[3], coordinates: r[4],
      }))
      this.renderRailways()
    } catch (e) {
      console.error("Failed to fetch railways:", e)
    } finally {
      this._rwFetching = false
    }
  }

  GlobeController.prototype.renderRailways = function() {
    if (!this._railwayData || !this.railwaysVisible) return

    const Cesium = window.Cesium
    const dataSource = this.getRailwaysDataSource()

    // Atomic clear + rebuild in one suspend block to prevent flicker
    dataSource.entities.suspendEvents()
    this._railwayEntities.forEach(e => dataSource.entities.remove(e))
    this._railwayEntities = []
    this._railwayData.forEach(rw => {
      if (!rw.coordinates || rw.coordinates.length < 2) return

      const positions = rw.coordinates.map(c =>
        Cesium.Cartesian3.fromDegrees(c[0], c[1], 100)
      )

      const isElec = rw.electrified === 1
      const isMajor = rw.category === 1
      const color = isElec
        ? cachedColor("#64b5f6", 0.8)
        : cachedColor("#b0bec5", 0.75)
      const width = isMajor ? 4 : rw.category === 2 ? 3 : 2.5

      const entity = dataSource.entities.add({
        id: `rw-${rw.id}`,
        polyline: {
          positions,
          width,
          material: new Cesium.PolylineGlowMaterialProperty({
            glowPower: 0.15,
            color,
          }),
        },
      })
      this._railwayEntities.push(entity)
    })
    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype.showRailwayDetail = function(id) {
    const rw = (this._railwayData || []).find(r => String(r.id) === String(id))
    if (!rw) return

    const categoryLabels = { 1: "Major", 2: "Secondary", 3: "Tertiary" }
    const categoryLabel = categoryLabels[rw.category] || "Unknown"
    const electrifiedLabel = rw.electrified === 1 ? "Yes" : "No"
    const continentLabel = rw.continent || "—"
    const isElec = rw.electrified === 1
    const color = isElec ? "#64b5f6" : "#b0bec5"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-train" style="margin-right:6px;"></i>Railway
      </div>
      <div class="detail-country">${this._escapeHtml(continentLabel)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Category</span>
          <span class="detail-value">
            <span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${color};margin-right:4px;"></span>
            ${categoryLabel}
          </span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Electrified</span>
          <span class="detail-value">${electrifiedLabel}</span>
        </div>
      </div>
    `
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype._clearRailwayEntities = function() {
    const ds = this._ds["railways"]
    if (ds) {
      ds.entities.suspendEvents()
      this._railwayEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._railwayEntities = []
  }
}
