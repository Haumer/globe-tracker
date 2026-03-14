import { findCountryAtPoint, getDataSource, cachedColor } from "../../utils"

export function applyCablesMethods(GlobeController) {
  GlobeController.prototype.getCablesDataSource = function() { return getDataSource(this.viewer, this._ds, "cables") }

  GlobeController.prototype.toggleCables = function() {
    this.cablesVisible = this.hasCablesToggleTarget && this.cablesToggleTarget.checked
    if (this.cablesVisible) {
      this.fetchCables()
    } else {
      this._clearCableEntities()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.fetchCables = async function() {
    this._toast("Loading submarine cables...")
    try {
      const resp = await fetch("/api/submarine_cables")
      if (!resp.ok) return
      const data = await resp.json()
      const hasData = (data.cables?.length || 0) > 0 || (data.landingPoints?.length || 0) > 0
      this._handleBackgroundRefresh(resp, "submarine-cables", hasData, () => {
        if (this.cablesVisible) this.fetchCables()
      })
      this._renderCables(data.cables, data.landingPoints)
      this._markFresh("cables")
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch submarine cables:", e)
    }
  }

  GlobeController.prototype._renderCables = function(cables, landingPoints) {
    this._clearCableEntities()
    const Cesium = window.Cesium
    const dataSource = this.getCablesDataSource()

    // Render cable polylines
    cables.forEach(cable => {
      const color = Cesium.Color.fromCssColorString(cable.color || "#00bcd4").withAlpha(0.6)
      const coords = cable.coordinates || []

      // Each cable may have multiple segments (array of arrays of [lng, lat])
      coords.forEach((segment, si) => {
        if (!Array.isArray(segment) || segment.length < 2) return
        const positions = segment.map(pt => {
          if (Array.isArray(pt) && pt.length >= 2) {
            return Cesium.Cartesian3.fromDegrees(pt[0], pt[1], -50)
          }
          return null
        }).filter(p => p !== null)

        if (positions.length < 2) return

        const entity = dataSource.entities.add({
          id: `cable-${cable.id}-${si}`,
          polyline: {
            positions,
            width: 1.5,
            material: new Cesium.PolylineGlowMaterialProperty({
              glowPower: 0.15,
              color,
            }),
            clampToGround: false,
          },
          properties: {
            cableName: cable.name,
            cableId: cable.id,
          },
        })
        this._cableEntities.push(entity)
      })
    })

    // Render landing points
    if (landingPoints) {
      landingPoints.forEach(lp => {
        const entity = dataSource.entities.add({
          id: `landing-${lp.id}`,
          position: Cesium.Cartesian3.fromDegrees(lp.lng, lp.lat, 50),
          point: {
            pixelSize: 4,
            color: cachedColor("#00e5ff", 0.9),
            outlineColor: cachedColor("#00838f", 0.5),
            outlineWidth: 1,
            scaleByDistance: new Cesium.NearFarScalar(5e4, 1.2, 5e6, 0.3),
            heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
          },
          label: {
            text: lp.name || "",
            font: "10px JetBrains Mono, monospace",
            fillColor: cachedColor("#80deea", 0.8),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 2,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: new Cesium.Cartesian2(0, -10),
            scaleByDistance: new Cesium.NearFarScalar(1e4, 1, 2e6, 0),
            translucencyByDistance: new Cesium.NearFarScalar(1e4, 1.0, 3e6, 0),
          },
        })
        this._landingPointEntities.push(entity)
      })
    }

    // Cross-layer: highlight landing points in attacked countries
    if (this.trafficVisible && this._attackedCountries?.size) {
      this._refreshCableAttackHighlights()
    }
  }

  GlobeController.prototype._clearCableEntities = function() {
    const ds = this.getCablesDataSource()
    this._cableEntities.forEach(e => ds.entities.remove(e))
    this._cableEntities = []
    this._landingPointEntities.forEach(e => ds.entities.remove(e))
    this._landingPointEntities = []
  }

  GlobeController.prototype._refreshCableAttackHighlights = function() {
    this._clearCableAttackHighlights()
    if (!this.trafficVisible || !this._attackedCountries?.size || !this._landingPointEntities.length) return
    if (!this._countryFeatures.length) return // need borders data for country lookup

    const Cesium = window.Cesium
    const dataSource = this.getCablesDataSource()
    this._cableAttackEntities = []

    this._landingPointEntities.forEach(e => {
      const pos = e.position?.getValue(Cesium.JulianDate.now())
      if (!pos) return
      const carto = Cesium.Cartographic.fromCartesian(pos)
      const lat = Cesium.Math.toDegrees(carto.latitude)
      const lng = Cesium.Math.toDegrees(carto.longitude)
      const country = findCountryAtPoint(this._countryFeatures, lat, lng)
      const code = country?.properties?.ISO_A2 || country?.properties?.iso_a2
      if (!code || !this._attackedCountries.has(code)) return

      const ring = dataSource.entities.add({
        id: `cable-atk-${e.id}`,
        position: Cesium.Cartesian3.fromDegrees(lng, lat, 50),
        point: {
          pixelSize: 8,
          color: Cesium.Color.RED.withAlpha(0.8),
          outlineColor: Cesium.Color.RED.withAlpha(0.3),
          outlineWidth: 4,
          scaleByDistance: new Cesium.NearFarScalar(5e4, 1.4, 5e6, 0.4),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._cableAttackEntities.push(ring)
    })
  }

  GlobeController.prototype._clearCableAttackHighlights = function() {
    if (!this._cableAttackEntities) return
    const ds = this._ds["cables"]
    if (ds) {
      this._cableAttackEntities.forEach(e => ds.entities.remove(e))
    }
    this._cableAttackEntities = []
  }
}
