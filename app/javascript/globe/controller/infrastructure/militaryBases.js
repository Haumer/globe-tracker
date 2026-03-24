import { getDataSource, cachedColor, LABEL_DEFAULTS } from "../../utils"

function createMilitaryBaseIcon(baseType, color) {
  const size = 28
  const canvas = document.createElement("canvas")
  canvas.width = size; canvas.height = size
  const ctx = canvas.getContext("2d")
  const cx = size / 2, cy = size / 2

  // Shield shape
  ctx.fillStyle = color
  ctx.globalAlpha = 0.15
  ctx.beginPath()
  ctx.moveTo(cx, 4)
  ctx.lineTo(size - 4, 10)
  ctx.lineTo(size - 4, 18)
  ctx.quadraticCurveTo(cx, size, cx, size)
  ctx.quadraticCurveTo(cx, size, 4, 18)
  ctx.lineTo(4, 10)
  ctx.closePath()
  ctx.fill()

  ctx.globalAlpha = 1.0
  ctx.strokeStyle = color
  ctx.lineWidth = 1.5
  ctx.stroke()

  // Center dot
  ctx.fillStyle = color
  ctx.beginPath()
  ctx.arc(cx, cy + 1, 3, 0, Math.PI * 2)
  ctx.fill()

  return canvas.toDataURL()
}

export function applyMilitaryBasesMethods(GlobeController) {
  GlobeController.prototype.getMilitaryBasesDataSource = function() {
    return getDataSource(this.viewer, this._ds, "military-bases")
  }

  GlobeController.prototype.toggleMilitaryBases = function() {
    this.militaryBasesVisible = this.hasMilitaryBasesToggleTarget && this.militaryBasesToggleTarget.checked
    if (this.militaryBasesVisible) {
      this.fetchMilitaryBases()
      if (!this._milBaseCameraCb) {
        this._milBaseCameraCb = () => { if (this.militaryBasesVisible) this.fetchMilitaryBases() }
        this.viewer.camera.moveEnd.addEventListener(this._milBaseCameraCb)
      }
    } else {
      this._clearMilitaryBaseEntities()
      if (this._milBaseCameraCb) {
        this.viewer.camera.moveEnd.removeEventListener(this._milBaseCameraCb)
        this._milBaseCameraCb = null
      }
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchMilitaryBases = async function() {
    const bounds = this.getViewportBounds()
    let url = "/api/military_bases"
    if (bounds) {
      url += `?north=${bounds.lamax}&south=${bounds.lamin}&east=${bounds.lomax}&west=${bounds.lomin}`
    }
    try {
      const resp = await fetch(url)
      if (!resp.ok) return
      const raw = await resp.json()
      // API returns: [id, lat, lng, name, base_type, country, operator]
      this._militaryBaseData = raw.map(r => ({
        id: r[0], lat: r[1], lng: r[2], name: r[3],
        base_type: r[4], country: r[5], operator: r[6],
      }))
      this.renderMilitaryBases()
    } catch (e) {
      console.error("Failed to fetch military bases:", e)
    }
  }

  GlobeController.prototype.renderMilitaryBases = function() {
    if (!this._militaryBaseData?.length || !this.militaryBasesVisible) return

    const Cesium = window.Cesium
    const dataSource = this.getMilitaryBasesDataSource()
    const bounds = this.getViewportBounds()

    const typeColors = {
      army: "#66bb6a",
      navy: "#42a5f5",
      air_force: "#ff7043",
      nuclear: "#fdd835",
      missile: "#ef5350",
    }

    let visible = this._militaryBaseData
    if (bounds) {
      visible = visible.filter(b =>
        b.lat >= bounds.lamin && b.lat <= bounds.lamax &&
        b.lng >= bounds.lomin && b.lng <= bounds.lomax
      )
    }
    if (this.hasActiveFilter && this.hasActiveFilter()) {
      visible = visible.filter(b => this.pointPassesFilter(b.lat, b.lng))
    }
    visible = visible.slice(0, 1000)

    const wantIds = new Set(visible.map(b => `milbase-${b.id}`))

    dataSource.entities.suspendEvents()

    const keep = []
    for (const e of this._militaryBaseEntities) {
      if (!wantIds.has(e.id)) {
        dataSource.entities.remove(e)
      } else {
        wantIds.delete(e.id)
        keep.push(e)
      }
    }
    this._militaryBaseEntities = keep

    if (!this._milBaseIcons) this._milBaseIcons = {}

    visible.forEach(b => {
      if (!wantIds.has(`milbase-${b.id}`)) return
      const bt = (b.base_type || "").toLowerCase()
      const color = typeColors[bt] || "#ff5252"
      const cesiumColor = Cesium.Color.fromCssColorString(color)

      if (!this._milBaseIcons[bt]) {
        this._milBaseIcons[bt] = createMilitaryBaseIcon(bt, color)
      }

      const entity = dataSource.entities.add({
        id: `milbase-${b.id}`,
        position: Cesium.Cartesian3.fromDegrees(b.lng, b.lat, 50),
        billboard: {
          image: this._milBaseIcons[bt],
          scale: 1.0,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 8e6, 0.3),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: b.name || "Base",
          font: LABEL_DEFAULTS.font,
          fillColor: cesiumColor.withAlpha(0.9),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: LABEL_DEFAULTS.pixelOffsetBelow(),
          scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
          translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
        },
      })
      this._militaryBaseEntities.push(entity)
    })

    dataSource.entities.resumeEvents()
    this._requestRender()
  }

  GlobeController.prototype._clearMilitaryBaseEntities = function() {
    const ds = this._ds["military-bases"]
    if (ds) {
      ds.entities.suspendEvents()
      this._militaryBaseEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
      this._requestRender()
    }
    this._militaryBaseEntities = []
  }

  GlobeController.prototype.showMilitaryBaseDetail = function(base) {
    const typeColors = {
      army: "#66bb6a", navy: "#42a5f5", air_force: "#ff7043",
      nuclear: "#fdd835", missile: "#ef5350",
    }
    const bt = (base.base_type || "").toLowerCase()
    const color = typeColors[bt] || "#ff5252"
    const typeLabel = (base.base_type || "Unknown").replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase())

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-shield-halved" style="margin-right:6px;"></i>${this._escapeHtml(base.name || "Military Base")}
      </div>
      <div class="detail-country">${this._escapeHtml(base.country || "Unknown")}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Type</span>
          <span class="detail-value" style="color:${color};">${typeLabel}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Operator</span>
          <span class="detail-value">${this._escapeHtml(base.operator || "Unknown")}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Position</span>
          <span class="detail-value">${base.lat.toFixed(4)}, ${base.lng.toFixed(4)}</span>
        </div>
      </div>
      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("military_base", base.lat, base.lng, { country_code: base.country })
  }
}
