export function applySatelliteHeatmapGridMethods(GlobeController) {
  GlobeController.prototype.toggleSatHeatmap = function() {
    this.satHeatmapVisible = this.hasSatHeatmapToggleTarget && this.satHeatmapToggleTarget.checked
    if (!this.satHeatmapVisible) {
      this.clearHeatmap()
      this._heatmapGrid.clear()
      this._heatmapLastUpdate = 0
    } else {
      this._heatmapGrid.clear()
      this._heatmapLastUpdate = 0
      if (this.satelliteData.length > 0) this.renderSatHeatmap()
    }
  }

  GlobeController.prototype.clearHeatmap = function() {
    const ds = this._ds["satellites"]
    if (ds && this._heatmapEntities.length > 0) {
      this._heatmapEntities.forEach(entity => ds.entities.remove(entity))
    }
    this._heatmapEntities = []

    if (ds && this._sweepEntities && this._sweepEntities.length > 0) {
      this._sweepEntities.forEach(entity => ds.entities.remove(entity))
    }
    this._sweepEntities = []
  }

  GlobeController.prototype._computeSatPositions = function() {
    const sat = window.satellite
    if (!sat || this.satelliteData.length === 0) return

    const nowMs = Date.now()
    this._heatmapLastUpdate = nowMs
    const now = new Date(nowMs)
    const gmst = sat.gstime(now)
    const positions = []

    for (const satellite of this.satelliteData) {
      if (!this.satCategoryVisible[satellite.category]) continue
      if (positions.length >= 200) break

      try {
        const satrec = sat.twoline2satrec(satellite.tle_line1, satellite.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) continue

        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        const lng = sat.degreesLong(posGd.longitude)
        const lat = sat.degreesLat(posGd.latitude)
        const altKm = posGd.height
        if (isNaN(lng) || isNaN(lat) || isNaN(altKm)) continue

        const earthRadiusKm = 6371
        const radiusKm = earthRadiusKm * Math.acos(earthRadiusKm / (earthRadiusKm + altKm))
        const color = this.satCategoryColors[satellite.category] || "#ab47bc"
        positions.push({ lat, lng, radiusKm, color })
      } catch {
        // Skip invalid TLE rows.
      }
    }

    this._lastSatPositions = positions
    return positions
  }

  GlobeController.prototype.toggleBuildHeatmap = function() {
    this._buildHeatmapActive = this.hasBuildHeatmapToggleTarget && this.buildHeatmapToggleTarget.checked
    if (!this._buildHeatmapActive) this._clearBuildHeatmap()
    else this._initBuildHeatmap()
    this._savePrefs()
  }

  GlobeController.prototype._initBuildHeatmap = function() {
    this._clearBuildHeatmap()
    if (this.selectedCountries.size === 0 || !this._selectedCountriesBbox) return

    const Cesium = window.Cesium
    const dataSource = this.getSatellitesDataSource()
    const bbox = this._selectedCountriesBbox
    const size = 0.12
    const rowStep = size * 1.5
    const colStep = size * Math.sqrt(3)
    let rendered = 0

    for (let lat = bbox.minLat; lat <= bbox.maxLat; lat += rowStep) {
      for (let lng = bbox.minLng; lng <= bbox.maxLng; lng += colStep) {
        if (rendered >= 8000) break
        const cell = this._snapToHexGrid(lat, lng)
        if (this._buildHeatmapGrid.has(cell.key)) continue
        if (!this._pointInSelectedCountries(cell.lat, cell.lng)) continue

        const verts = this._buildHexVerts(cell.lat, cell.lng, size)
        const entity = dataSource.entities.add({
          polygon: {
            hierarchy: verts,
            material: Cesium.Color.fromCssColorString("#0d47a1").withAlpha(0.06),
            outline: true,
            outlineColor: Cesium.Color.fromCssColorString("#0d47a1").withAlpha(0.15),
            outlineWidth: 1,
            height: 0,
            classificationType: Cesium.ClassificationType.BOTH,
          },
        })
        this._buildHeatmapGrid.set(cell.key, { lat: cell.lat, lng: cell.lng, hits: 0, entity })
        this._buildHeatmapBaseEntities.push(entity)
        rendered++
      }
    }
  }

  GlobeController.prototype._clearBuildHeatmap = function() {
    const ds = this._ds["satellites"]
    if (ds) {
      this._buildHeatmapBaseEntities.forEach(entity => ds.entities.remove(entity))
    }
    this._buildHeatmapBaseEntities = []
    this._buildHeatmapGrid.clear()
  }

  GlobeController.prototype._updateBuildHeatmap = function() {
    if (!this._buildHeatmapActive || this._buildHeatmapGrid.size === 0) return

    const Cesium = window.Cesium
    const positions = this._lastSatPositions || []
    if (positions.length === 0) return

    const size = 0.12
    const rowStep = size * 1.5
    const colStep = size * Math.sqrt(3)

    for (const position of positions) {
      const radiusDeg = position.radiusKm / 111.32
      const cosCenter = Math.cos(position.lat * Math.PI / 180) || 0.01

      for (let lat = position.lat - radiusDeg; lat <= position.lat + radiusDeg; lat += rowStep) {
        for (let lng = position.lng - radiusDeg; lng <= position.lng + radiusDeg; lng += colStep) {
          const cell = this._snapToHexGrid(lat, lng)
          const gridCell = this._buildHeatmapGrid.get(cell.key)
          if (!gridCell) continue

          const dLat = (gridCell.lat - position.lat) * 111.32
          const dLng = (gridCell.lng - position.lng) * 111.32 * cosCenter
          const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
          if (distKm > position.radiusKm) continue
          gridCell.hits++
        }
      }
    }

    let maxHits = 1
    for (const cell of this._buildHeatmapGrid.values()) {
      if (cell.hits > maxHits) maxHits = cell.hits
    }

    for (const cell of this._buildHeatmapGrid.values()) {
      if (cell.hits === 0) continue
      const ratio = Math.min(cell.hits / Math.max(maxHits, 1), 1)
      const color = heatmapColor(Cesium, ratio)
      const alpha = 0.15 + ratio * 0.45
      const extHeight = 100 + cell.hits * 1500

      if (!cell.entity?.polygon) continue
      cell.entity.polygon.material = color.withAlpha(alpha)
      cell.entity.polygon.outlineColor = color.withAlpha(Math.min(alpha + 0.15, 0.8))
      cell.entity.polygon.extrudedHeight = extHeight
    }
  }

  GlobeController.prototype._snapToHexGrid = function(lat, lng) {
    const size = 0.12
    const sqrt3 = Math.sqrt(3)
    const rowSpacing = size * 1.5
    const colSpacing = size * sqrt3
    const row = Math.round(lat / rowSpacing)
    const offset = (((row % 2) + 2) % 2) * colSpacing * 0.5
    const col = Math.round((lng - offset) / colSpacing)

    return {
      lat: row * rowSpacing,
      lng: col * colSpacing + offset,
      key: `${row},${col}`
    }
  }

  GlobeController.prototype._buildHexVerts = function(cellLat, cellLng, size) {
    const Cesium = window.Cesium
    const cosLat = Math.cos(cellLat * Math.PI / 180) || 0.01
    const verts = []
    for (let index = 0; index < 6; index++) {
      const angle = (Math.PI / 3) * index + (Math.PI / 6)
      verts.push(Cesium.Cartesian3.fromDegrees(
        cellLng + (size * Math.cos(angle)) / cosLat,
        cellLat + size * Math.sin(angle)
      ))
    }
    return verts
  }

  GlobeController.prototype.renderSatHeatmap = function() {
    const Cesium = window.Cesium
    const sat = window.satellite
    if (!sat || this.satelliteData.length === 0) return

    const nowMs = Date.now()
    const hitLifeMs = this._heatmapHitLifeSec * 1000
    const hasFilter = this.hasActiveFilter()
    const hasCountries = this.selectedCountries.size > 0 && this._selectedCountriesBbox
    const shouldRecompute = (nowMs - this._heatmapLastUpdate) > 10000

    if (shouldRecompute) {
      const satPositions = this._computeSatPositions() || []
      stampHeatmapHits.call(this, satPositions, nowMs, hasFilter)
    }

    pruneExpiredHeatmapHits(this._heatmapGrid, nowMs, hitLifeMs)

    this.clearHeatmap()
    const dataSource = this.getSatellitesDataSource()
    const bounds = hasFilter ? this.getFilterBounds() : this.getViewportBounds()

    if (hasCountries) {
      renderSweepEntities.call(this, Cesium, dataSource, bounds)
    }

    renderHeatmapEntities.call(this, Cesium, dataSource, bounds)
  }
}

function heatmapColor(Cesium, ratio) {
  if (ratio < 0.2) return Cesium.Color.fromCssColorString("#0d47a1")
  if (ratio < 0.4) return Cesium.Color.fromCssColorString("#00838f")
  if (ratio < 0.6) return Cesium.Color.fromCssColorString("#2e7d32")
  if (ratio < 0.8) return Cesium.Color.fromCssColorString("#f9a825")
  return Cesium.Color.fromCssColorString("#e65100")
}

function stampHeatmapHits(satPositions, nowMs, hasFilter) {
  const size = 0.12
  const rowStep = size * 1.5
  const colStep = size * Math.sqrt(3)

  satPositions.forEach(position => {
    const radiusDeg = position.radiusKm / 111.32
    const cosCenter = Math.cos(position.lat * Math.PI / 180) || 0.01

    for (let lat = position.lat - radiusDeg; lat <= position.lat + radiusDeg; lat += rowStep) {
      for (let lng = position.lng - radiusDeg; lng <= position.lng + radiusDeg; lng += colStep) {
        const cell = this._snapToHexGrid(lat, lng)
        const dLat = (cell.lat - position.lat) * 111.32
        const dLng = (cell.lng - position.lng) * 111.32 * cosCenter
        const dist = Math.sqrt(dLat * dLat + dLng * dLng)
        if (dist > position.radiusKm) continue
        if (hasFilter && !this.pointPassesFilter(cell.lat, cell.lng)) continue

        const existing = this._heatmapGrid.get(cell.key)
        if (existing) existing.hits.push(nowMs)
        else this._heatmapGrid.set(cell.key, { lat: cell.lat, lng: cell.lng, hits: [nowMs] })
      }
    }
  })
}

function pruneExpiredHeatmapHits(grid, nowMs, hitLifeMs) {
  for (const [key, cell] of grid) {
    cell.hits = cell.hits.filter(timestamp => (nowMs - timestamp) < hitLifeMs)
    if (cell.hits.length === 0) grid.delete(key)
  }
}

function renderSweepEntities(Cesium, dataSource, bounds) {
  const positions = this._lastSatPositions || []
  const bbox = this._selectedCountriesBbox
  const size = 0.12
  const rowStep = size * 1.5
  const colStep = size * Math.sqrt(3)
  let sweepCount = 0

  for (const position of positions) {
    if (sweepCount >= 2000) break
    const radiusDeg = position.radiusKm / 111.32
    const cosCenter = Math.cos(position.lat * Math.PI / 180) || 0.01
    const sweepColor = Cesium.Color.fromCssColorString(position.color)
    const minLat = Math.max(bbox.minLat, position.lat - radiusDeg)
    const maxLat = Math.min(bbox.maxLat, position.lat + radiusDeg)
    const lngSpread = radiusDeg / cosCenter
    const minLng = Math.max(bbox.minLng, position.lng - lngSpread)
    const maxLng = Math.min(bbox.maxLng, position.lng + lngSpread)
    if (minLat >= maxLat || minLng >= maxLng) continue

    for (let lat = minLat; lat <= maxLat; lat += rowStep) {
      for (let lng = minLng; lng <= maxLng; lng += colStep) {
        if (sweepCount >= 2000) break
        const cell = this._snapToHexGrid(lat, lng)
        if (bounds) {
          if (cell.lat < bounds.lamin - 2 || cell.lat > bounds.lamax + 2 ||
              cell.lng < bounds.lomin - 2 || cell.lng > bounds.lomax + 2) continue
        }

        const dLat = (cell.lat - position.lat) * 111.32
        const dLng = (cell.lng - position.lng) * 111.32 * cosCenter
        const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
        if (distKm > position.radiusKm) continue
        if (!this._pointInSelectedCountries(cell.lat, cell.lng)) continue
        if (this._heatmapGrid.has(cell.key)) continue

        const falloff = Math.max(0, 1 - distKm / position.radiusKm)
        const verts = this._buildHexVerts(cell.lat, cell.lng, size)
        const entity = dataSource.entities.add({
          polygon: {
            hierarchy: verts,
            material: sweepColor.withAlpha(0.04 + falloff * 0.12),
            outline: true,
            outlineColor: sweepColor.withAlpha(0.12 + falloff * 0.25),
            outlineWidth: 1,
            height: 0,
            classificationType: Cesium.ClassificationType.BOTH,
          },
        })
        this._sweepEntities.push(entity)
        sweepCount++
      }
    }
  }
}

function renderHeatmapEntities(Cesium, dataSource, bounds) {
  let maxHits = 1
  for (const cell of this._heatmapGrid.values()) {
    if (cell.hits.length > maxHits) maxHits = cell.hits.length
  }

  const size = 0.12
  const heightPerHit = 2000
  let rendered = 0

  for (const cell of this._heatmapGrid.values()) {
    if (rendered >= 4000) break
    if (bounds) {
      if (cell.lat < bounds.lamin - 2 || cell.lat > bounds.lamax + 2 ||
          cell.lng < bounds.lomin - 2 || cell.lng > bounds.lomax + 2) continue
    }

    const count = cell.hits.length
    const ratio = Math.min(count / Math.max(maxHits, 1), 1)
    const color = heatmapColor(Cesium, ratio)
    const alpha = 0.3 + ratio * 0.35
    const fillColor = color.withAlpha(alpha)
    const verts = this._buildHexVerts(cell.lat, cell.lng, size)
    const entity = dataSource.entities.add({
      polygon: {
        hierarchy: verts,
        material: fillColor,
        outline: true,
        outlineColor: fillColor.withAlpha(Math.min(alpha + 0.1, 0.7)),
        outlineWidth: 1,
        extrudedHeight: 100 + count * heightPerHit,
        height: 0,
      },
    })
    this._heatmapEntities.push(entity)
    rendered++
  }
}
