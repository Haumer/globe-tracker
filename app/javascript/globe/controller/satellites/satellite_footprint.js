export function applySatelliteFootprintMethods(GlobeController) {
  GlobeController.prototype.renderSatHexFootprint = function({ lat, lng, alt, altKm, color }) {
    const Cesium = window.Cesium
    const dataSource = this.getSatellitesDataSource()
    const baseColor = Cesium.Color.fromCssColorString(color)
    const satPos = Cesium.Cartesian3.fromDegrees(lng, lat, alt)
    const earthRadiusKm = 6371
    const scanRadiusKm = earthRadiusKm * Math.acos(earthRadiusKm / (earthRadiusKm + altKm))
    const scanRadiusDeg = scanRadiusKm / 111.32

    if (this._satFootprintCountryMode && this.selectedCountries.size > 0 && this._selectedCountriesBbox) {
      this._clearNadirFootprint()
      this._renderCountryConstrainedHexes(baseColor, lat, lng, scanRadiusKm, scanRadiusDeg, satPos)
      return
    }

    const size = 0.12
    const rowHeight = size * 1.5
    const colWidth = size * Math.sqrt(3)
    const cosCenter = Math.cos(lat * Math.PI / 180) || 0.01
    const hexOffsets = [
      [-1, -0.5], [-1, 0.5],
      [0, -1], [0, 0], [0, 1],
      [1, -0.5], [1, 0.5],
    ]
    const needsCreate = !this._satFootprintEntities || this._satFootprintEntities.length !== 9

    if (needsCreate) {
      this._clearNadirFootprint()
      createFootprintEntities.call(this, Cesium, dataSource, baseColor, lat, lng, scanRadiusKm, rowHeight, colWidth, cosCenter, size, hexOffsets, satPos)
    } else {
      updateFootprintEntities.call(this, Cesium, lat, lng, rowHeight, colWidth, cosCenter, size, hexOffsets, satPos)
    }
  }

  GlobeController.prototype._renderCountryConstrainedHexes = function(baseColor, satLat, satLng, scanRadiusKm, scanRadiusDeg, satPos) {
    const Cesium = window.Cesium
    const dataSource = this.getSatellitesDataSource()
    const bbox = this._selectedCountriesBbox
    const size = 0.12
    const rowStep = size * 1.5
    const colStep = size * Math.sqrt(3)
    const minLat = Math.max(bbox.minLat, satLat - scanRadiusDeg)
    const maxLat = Math.min(bbox.maxLat, satLat + scanRadiusDeg)
    const cosCenter = Math.cos(satLat * Math.PI / 180) || 0.01
    const lngSpread = scanRadiusDeg / cosCenter
    const minLng = Math.max(bbox.minLng, satLng - lngSpread)
    const maxLng = Math.min(bbox.maxLng, satLng + lngSpread)
    if (minLat >= maxLat || minLng >= maxLng) return

    let rendered = 0
    for (let lat = minLat; lat <= maxLat; lat += rowStep) {
      for (let lng = minLng; lng <= maxLng; lng += colStep) {
        if (rendered >= 3000) break

        const cell = this._snapToHexGrid(lat, lng)
        const dLat = (cell.lat - satLat) * 111.32
        const dLng = (cell.lng - satLng) * 111.32 * cosCenter
        const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
        if (distKm > scanRadiusKm) continue
        if (!this._pointInSelectedCountries(cell.lat, cell.lng)) continue

        const falloff = Math.max(0, 1 - distKm / scanRadiusKm)
        const entity = dataSource.entities.add({
          polygon: {
            hierarchy: this._buildHexVerts(cell.lat, cell.lng, size),
            material: baseColor.withAlpha(0.1 + falloff * 0.3),
            outline: true,
            outlineColor: baseColor.withAlpha(0.3 + falloff * 0.5),
            outlineWidth: 1.5,
            height: 0,
            extrudedHeight: falloff * 1200,
          },
        })
        this._satFootprintEntities.push(entity)
        rendered++
      }
    }

    this._satFootprintEntities.push(dataSource.entities.add({
      polyline: {
        positions: [satPos, Cesium.Cartesian3.fromDegrees(satLng, satLat, 0)],
        width: 2,
        material: baseColor.withAlpha(0.6),
      },
    }))

    this._satFootprintEntities.push(dataSource.entities.add({
      position: Cesium.Cartesian3.fromDegrees(satLng, satLat, 0),
      point: {
        pixelSize: 7,
        color: baseColor.withAlpha(0.9),
        outlineColor: baseColor.withAlpha(0.3),
        outlineWidth: 8,
      },
    }))
  }

  GlobeController.prototype.toggleSatFootprintCountryMode = function() {
    this._satFootprintCountryMode = !this._satFootprintCountryMode
    if (this._selectedSatPosition) this.renderSatHexFootprint(this._selectedSatPosition)
    if (!this.selectedSatNoradId) return

    const satData = this.satelliteData.find(satellite => satellite.norad_id === this.selectedSatNoradId)
    if (satData) this.showSatelliteDetail(satData)
  }
}

function createFootprintEntities(Cesium, dataSource, baseColor, lat, lng, scanRadiusKm, rowHeight, colWidth, cosCenter, size, hexOffsets, satPos) {
  hexOffsets.forEach(([dr, dc]) => {
    const hexLat = lat + dr * rowHeight
    const hexLng = lng + dc * colWidth / cosCenter
    const dLat = dr * rowHeight * 111.32
    const dLng = dc * colWidth * 111.32
    const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
    const falloff = Math.max(0, 1 - distKm / (scanRadiusKm * 0.05))

    const entity = dataSource.entities.add({
      polygon: {
        hierarchy: new Cesium.PolygonHierarchy(this._buildHexVerts(hexLat, hexLng, size)),
        material: baseColor.withAlpha(0.12 + falloff * 0.25),
        outline: true,
        outlineColor: baseColor.withAlpha(0.35 + falloff * 0.5),
        outlineWidth: 1.5,
        height: 0,
        classificationType: Cesium.ClassificationType.BOTH,
      },
    })
    this._satFootprintEntities.push(entity)
  })

  this._nadirLinePositions = [satPos, Cesium.Cartesian3.fromDegrees(lng, lat, 0)]
  this._satFootprintEntities.push(dataSource.entities.add({
    polyline: {
      positions: new Cesium.CallbackProperty(() => this._nadirLinePositions, false),
      width: 3,
      material: baseColor.withAlpha(0.6),
    },
  }))

  this._nadirDotPosition = Cesium.Cartesian3.fromDegrees(lng, lat, 0)
  this._satFootprintEntities.push(dataSource.entities.add({
    position: new Cesium.CallbackProperty(() => this._nadirDotPosition, false),
    point: {
      pixelSize: 7,
      color: baseColor.withAlpha(0.9),
      outlineColor: baseColor.withAlpha(0.3),
      outlineWidth: 8,
    },
  }))
}

function updateFootprintEntities(Cesium, lat, lng, rowHeight, colWidth, cosCenter, size, hexOffsets, satPos) {
  hexOffsets.forEach(([dr, dc], index) => {
    const hexLat = lat + dr * rowHeight
    const hexLng = lng + dc * colWidth / cosCenter
    this._satFootprintEntities[index].polygon.hierarchy =
      new Cesium.PolygonHierarchy(this._buildHexVerts(hexLat, hexLng, size))
  })

  this._nadirLinePositions = [satPos, Cesium.Cartesian3.fromDegrees(lng, lat, 0)]
  this._nadirDotPosition = Cesium.Cartesian3.fromDegrees(lng, lat, 0)
}
