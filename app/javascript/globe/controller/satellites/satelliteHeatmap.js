import { haversineDistance } from "../../utils"

export function applySatHeatmapMethods(GlobeController) {
  // ── Satellite Coverage Heatmap ───────────────────────────

  GlobeController.prototype.toggleSatHeatmap = function() {
    this.satHeatmapVisible = this.hasSatHeatmapToggleTarget && this.satHeatmapToggleTarget.checked
    if (!this.satHeatmapVisible) {
      this.clearHeatmap()
      this._heatmapGrid.clear()
      this._heatmapLastUpdate = 0
    } else {
      // Start fresh — heatmap builds from scratch via live sweep
      this._heatmapGrid.clear()
      this._heatmapLastUpdate = 0
      if (this.satelliteData.length > 0) {
        this.renderSatHeatmap()
      }
    }
  }

  GlobeController.prototype.clearHeatmap = function() {
    const ds = this._ds["satellites"]
    if (ds && this._heatmapEntities.length > 0) {
      this._heatmapEntities.forEach(e => ds.entities.remove(e))
    }
    this._heatmapEntities = []
    // Also clear live sweep entities
    if (ds && this._sweepEntities && this._sweepEntities.length > 0) {
      this._sweepEntities.forEach(e => ds.entities.remove(e))
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
    for (const s of this.satelliteData) {
      if (!this.satCategoryVisible[s.category]) continue
      if (positions.length >= 200) break
      try {
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) continue
        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        const sLng = sat.degreesLong(posGd.longitude)
        const sLat = sat.degreesLat(posGd.latitude)
        const altKm = posGd.height
        if (isNaN(sLng) || isNaN(sLat) || isNaN(altKm)) continue
        const R = 6371
        const scanRadiusKm = R * Math.acos(R / (R + altKm))
        const color = this.satCategoryColors[s.category] || "#ab47bc"
        positions.push({ lat: sLat, lng: sLng, radiusKm: scanRadiusKm, color })
      } catch { /* skip */ }
    }

    this._lastSatPositions = positions
    return positions
  }

  // ── Build Heatmap ─────────────────────────────────────────
  // Projects a full hex grid onto selected countries, then accumulates
  // satellite sweep hits onto those hexes over time.

  GlobeController.prototype.toggleBuildHeatmap = function() {
    this._buildHeatmapActive = this.hasBuildHeatmapToggleTarget && this.buildHeatmapToggleTarget.checked
    if (!this._buildHeatmapActive) {
      this._clearBuildHeatmap()
    } else {
      this._initBuildHeatmap()
    }
    this._savePrefs()
  }

  GlobeController.prototype._initBuildHeatmap = function() {
    this._clearBuildHeatmap()
    if (this.selectedCountries.size === 0 || !this._selectedCountriesBbox) return

    const Cesium = window.Cesium
    const dataSource = this.getSatellitesDataSource()
    const bb = this._selectedCountriesBbox

    const S = 0.12
    const rowStep = S * 1.5
    const colStep = S * Math.sqrt(3)
    let rendered = 0

    for (let la = bb.minLat; la <= bb.maxLat; la += rowStep) {
      for (let ln = bb.minLng; ln <= bb.maxLng; ln += colStep) {
        if (rendered >= 8000) break
        const cell = this._snapToHexGrid(la, ln)
        if (this._buildHeatmapGrid.has(cell.key)) continue
        if (!this._pointInSelectedCountries(cell.lat, cell.lng)) continue

        const verts = this._buildHexVerts(cell.lat, cell.lng, S)
        const entity = dataSource.entities.add({
          polygon: {
            hierarchy: verts,
            material: Cesium.Color.fromCssColorString("#0d47a1").withAlpha(0.06),
            outline: true,
            outlineColor: Cesium.Color.fromCssColorString("#0d47a1").withAlpha(0.15),
            outlineWidth: 1,
            height: 0,
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
      this._buildHeatmapBaseEntities.forEach(e => ds.entities.remove(e))
    }
    this._buildHeatmapBaseEntities = []
    this._buildHeatmapGrid.clear()
  }

  GlobeController.prototype._updateBuildHeatmap = function() {
    if (!this._buildHeatmapActive || this._buildHeatmapGrid.size === 0) return

    const Cesium = window.Cesium
    const positions = this._lastSatPositions || []
    if (positions.length === 0) return

    const S = 0.12
    const rowStep = S * 1.5
    const colStep = S * Math.sqrt(3)

    // For each satellite, stamp hits on base grid cells within its scan radius
    for (const sp of positions) {
      const radiusDeg = sp.radiusKm / 111.32
      const cosCenter = Math.cos(sp.lat * Math.PI / 180) || 0.01

      for (let la = sp.lat - radiusDeg; la <= sp.lat + radiusDeg; la += rowStep) {
        for (let ln = sp.lng - radiusDeg; ln <= sp.lng + radiusDeg; ln += colStep) {
          const cell = this._snapToHexGrid(la, ln)
          const gridCell = this._buildHeatmapGrid.get(cell.key)
          if (!gridCell) continue

          const dLat = (gridCell.lat - sp.lat) * 111.32
          const dLng = (gridCell.lng - sp.lng) * 111.32 * cosCenter
          const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
          if (distKm > sp.radiusKm) continue

          gridCell.hits++
        }
      }
    }

    // Update visuals based on hit count
    let maxHits = 1
    for (const cell of this._buildHeatmapGrid.values()) {
      if (cell.hits > maxHits) maxHits = cell.hits
    }

    for (const cell of this._buildHeatmapGrid.values()) {
      if (cell.hits === 0) continue
      const t = Math.min(cell.hits / Math.max(maxHits, 1), 1)

      let color
      if (t < 0.2) color = Cesium.Color.fromCssColorString("#0d47a1")
      else if (t < 0.4) color = Cesium.Color.fromCssColorString("#00838f")
      else if (t < 0.6) color = Cesium.Color.fromCssColorString("#2e7d32")
      else if (t < 0.8) color = Cesium.Color.fromCssColorString("#f9a825")
      else color = Cesium.Color.fromCssColorString("#e65100")

      const alpha = 0.15 + t * 0.45
      const extHeight = 100 + cell.hits * 1500

      if (cell.entity && cell.entity.polygon) {
        cell.entity.polygon.material = color.withAlpha(alpha)
        cell.entity.polygon.outlineColor = color.withAlpha(Math.min(alpha + 0.15, 0.8))
        cell.entity.polygon.extrudedHeight = extHeight
      }
    }
  }

  // Snap lat/lng to nearest hex cell on a fixed global grid
  // Pointy-top hex: size S = 0.12° (center-to-vertex)
  // Row spacing = S * 1.5, Col spacing = S * sqrt(3)

  GlobeController.prototype._snapToHexGrid = function(lat, lng) {
    const S = 0.12
    const sqrt3 = Math.sqrt(3)
    const rowSpacing = S * 1.5
    const colSpacing = S * sqrt3

    const row = Math.round(lat / rowSpacing)
    const offset = (((row % 2) + 2) % 2) * colSpacing * 0.5
    const col = Math.round((lng - offset) / colSpacing)

    return {
      lat: row * rowSpacing,
      lng: col * colSpacing + offset,
      key: `${row},${col}`
    }
  }

  GlobeController.prototype._buildHexVerts = function(cellLat, cellLng, S) {
    const Cesium = window.Cesium
    const cosLat = Math.cos(cellLat * Math.PI / 180) || 0.01
    const verts = []
    for (let i = 0; i < 6; i++) {
      const angle = (Math.PI / 3) * i + (Math.PI / 6) // pointy-top
      verts.push(Cesium.Cartesian3.fromDegrees(
        cellLng + (S * Math.cos(angle)) / cosLat,
        cellLat + S * Math.sin(angle)
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

    // Throttle: only recompute every 10 seconds
    const shouldRecompute = (nowMs - this._heatmapLastUpdate) > 10000

    // Compute satellite positions (needed for both stamping and sweep rendering)
    let satPositions = null
    if (shouldRecompute) {
      this._heatmapLastUpdate = nowMs
      const now = new Date(nowMs)
      const gmst = sat.gstime(now)

      satPositions = []
      for (const s of this.satelliteData) {
        if (!this.satCategoryVisible[s.category]) continue
        if (satPositions.length >= 200) break
        try {
          const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
          const posVel = sat.propagate(satrec, now)
          if (!posVel.position) continue
          const posGd = sat.eciToGeodetic(posVel.position, gmst)
          const sLng = sat.degreesLong(posGd.longitude)
          const sLat = sat.degreesLat(posGd.latitude)
          const altKm = posGd.height
          if (isNaN(sLng) || isNaN(sLat) || isNaN(altKm)) continue
          const R = 6371
          const scanRadiusKm = R * Math.acos(R / (R + altKm))
          const color = this.satCategoryColors[s.category] || "#ab47bc"
          satPositions.push({ lat: sLat, lng: sLng, radiusKm: scanRadiusKm, color })
        } catch { /* skip */ }
      }

      // Cache for sweep rendering
      this._lastSatPositions = satPositions

      // Stamp hex cells — only cells inside selected countries (if any)
      const S = 0.12
      const rowStep = S * 1.5
      const colStep = S * Math.sqrt(3)

      satPositions.forEach(sp => {
        const radiusDeg = sp.radiusKm / 111.32
        const cosCenter = Math.cos(sp.lat * Math.PI / 180) || 0.01

        for (let la = sp.lat - radiusDeg; la <= sp.lat + radiusDeg; la += rowStep) {
          for (let ln = sp.lng - radiusDeg; ln <= sp.lng + radiusDeg; ln += colStep) {
            const cell = this._snapToHexGrid(la, ln)
            const dLat = (cell.lat - sp.lat) * 111.32
            const dLng = (cell.lng - sp.lng) * 111.32 * cosCenter
            const dist = Math.sqrt(dLat * dLat + dLng * dLng)
            if (dist > sp.radiusKm) continue

            if (hasFilter && !this.pointPassesFilter(cell.lat, cell.lng)) continue

            const existing = this._heatmapGrid.get(cell.key)
            if (existing) {
              existing.hits.push(nowMs)
            } else {
              this._heatmapGrid.set(cell.key, { lat: cell.lat, lng: cell.lng, hits: [nowMs] })
            }
          }
        }
      })
    }

    // Prune expired hits
    for (const [key, cell] of this._heatmapGrid) {
      cell.hits = cell.hits.filter(t => (nowMs - t) < hitLifeMs)
      if (cell.hits.length === 0) this._heatmapGrid.delete(key)
    }

    // ── Render ──
    this.clearHeatmap()
    const dataSource = this.getSatellitesDataSource()
    const bounds = hasFilter ? this.getFilterBounds() : this.getViewportBounds()

    // ── 1. Live sweep: render each satellite's current footprint on the country ──
    if (hasCountries) {
      const positions = this._lastSatPositions || []
      const bb = this._selectedCountriesBbox
      const S = 0.12
      const rowStep = S * 1.5
      const colStep = S * Math.sqrt(3)
      let sweepCount = 0

      for (const sp of positions) {
        if (sweepCount >= 2000) break
        const radiusDeg = sp.radiusKm / 111.32
        const cosCenter = Math.cos(sp.lat * Math.PI / 180) || 0.01
        const sweepColor = Cesium.Color.fromCssColorString(sp.color)

        // Intersection of satellite circle with country bbox
        const minLat = Math.max(bb.minLat, sp.lat - radiusDeg)
        const maxLat = Math.min(bb.maxLat, sp.lat + radiusDeg)
        const lngSpread = radiusDeg / cosCenter
        const minLng = Math.max(bb.minLng, sp.lng - lngSpread)
        const maxLng = Math.min(bb.maxLng, sp.lng + lngSpread)
        if (minLat >= maxLat || minLng >= maxLng) continue

        for (let la = minLat; la <= maxLat; la += rowStep) {
          for (let ln = minLng; ln <= maxLng; ln += colStep) {
            if (sweepCount >= 2000) break
            const cell = this._snapToHexGrid(la, ln)
            const dLat = (cell.lat - sp.lat) * 111.32
            const dLng = (cell.lng - sp.lng) * 111.32 * cosCenter
            const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
            if (distKm > sp.radiusKm) continue
            if (!this._pointInSelectedCountries(cell.lat, cell.lng)) continue

            // Don't render sweep hex if there's already a heatmap hex (heatmap takes priority)
            if (this._heatmapGrid.has(cell.key)) continue

            const falloff = Math.max(0, 1 - distKm / sp.radiusKm)
            const verts = this._buildHexVerts(cell.lat, cell.lng, S)
            const entity = dataSource.entities.add({
              polygon: {
                hierarchy: verts,
                material: sweepColor.withAlpha(0.04 + falloff * 0.12),
                outline: true,
                outlineColor: sweepColor.withAlpha(0.12 + falloff * 0.25),
                outlineWidth: 1,
                height: 0,
              },
            })
            this._sweepEntities.push(entity)
            sweepCount++
          }
        }
      }
    }

    // ── 2. Accumulated heatmap hexes ──
    let maxHits = 1
    for (const cell of this._heatmapGrid.values()) {
      if (cell.hits.length > maxHits) maxHits = cell.hits.length
    }

    const S = 0.12
    const heightPerHit = 2000
    let rendered = 0

    for (const cell of this._heatmapGrid.values()) {
      if (rendered >= 4000) break

      if (bounds) {
        if (cell.lat < bounds.lamin - 2 || cell.lat > bounds.lamax + 2 ||
            cell.lng < bounds.lomin - 2 || cell.lng > bounds.lomax + 2) continue
      }

      const count = cell.hits.length
      const t = Math.min(count / Math.max(maxHits, 1), 1)

      let color
      if (t < 0.2) color = Cesium.Color.fromCssColorString("#0d47a1")
      else if (t < 0.4) color = Cesium.Color.fromCssColorString("#00838f")
      else if (t < 0.6) color = Cesium.Color.fromCssColorString("#2e7d32")
      else if (t < 0.8) color = Cesium.Color.fromCssColorString("#f9a825")
      else color = Cesium.Color.fromCssColorString("#e65100")

      const alpha = 0.3 + t * 0.35
      const fillColor = color.withAlpha(alpha)
      const verts = this._buildHexVerts(cell.lat, cell.lng, S)
      const extrudedHeight = 100 + count * heightPerHit

      const entity = dataSource.entities.add({
        polygon: {
          hierarchy: verts,
          material: fillColor,
          outline: true,
          outlineColor: fillColor.withAlpha(Math.min(alpha + 0.1, 0.7)),
          outlineWidth: 1,
          extrudedHeight: extrudedHeight,
          height: 0,
        },
      })
      this._heatmapEntities.push(entity)
      rendered++
    }
  }

  GlobeController.prototype.renderSatHexFootprint = function({ lat, lng, alt, altKm, color }) {
    const Cesium = window.Cesium
    const dataSource = this.getSatellitesDataSource()

    const baseColor = Cesium.Color.fromCssColorString(color)
    const satPos = Cesium.Cartesian3.fromDegrees(lng, lat, alt)

    const R = 6371
    const scanRadiusKm = R * Math.acos(R / (R + altKm))
    const scanRadiusDeg = scanRadiusKm / 111.32
    const cosLat = Math.cos(lat * Math.PI / 180) || 0.01

    // Country-constrained mode: destroy & rebuild (infrequent, complex geometry)
    if (this._satFootprintCountryMode && this.selectedCountries.size > 0 && this._selectedCountriesBbox) {
      this._clearNadirFootprint()
      this._renderCountryConstrainedHexes(baseColor, lat, lng, scanRadiusKm, scanRadiusDeg, satPos)
      return
    }

    const S = 0.12
    const rowH = S * 1.5
    const colW = S * Math.sqrt(3)
    const cosCenter = Math.cos(lat * Math.PI / 180) || 0.01

    const hexOffsets = [
      [-1, -0.5], [-1, 0.5],
      [ 0, -1],   [ 0, 0], [ 0, 1],
      [ 1, -0.5], [ 1, 0.5],
    ]

    // Reuse existing entities if count matches (7 hexes + 1 line + 1 dot = 9)
    const needsCreate = !this._satFootprintEntities || this._satFootprintEntities.length !== 9

    if (needsCreate) {
      // Clear old entities
      this._clearNadirFootprint()

      // Create 7 hex polygons
      hexOffsets.forEach(([dr, dc]) => {
        const hexLat = lat + dr * rowH
        const hexLng = lng + dc * colW / cosCenter
        const dLat = dr * rowH * 111.32
        const dLng = dc * colW * 111.32
        const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
        const falloff = Math.max(0, 1 - distKm / (scanRadiusKm * 0.05))

        const entity = dataSource.entities.add({
          polygon: {
            hierarchy: new Cesium.PolygonHierarchy(this._buildHexVerts(hexLat, hexLng, S)),
            material: baseColor.withAlpha(0.12 + falloff * 0.25),
            outline: true,
            outlineColor: baseColor.withAlpha(0.35 + falloff * 0.5),
            outlineWidth: 1.5,
            height: 0,
          },
        })
        this._satFootprintEntities.push(entity)
      })

      // Nadir line — use CallbackProperty so Cesium doesn't rebuild geometry each frame
      this._nadirLinePositions = [satPos, Cesium.Cartesian3.fromDegrees(lng, lat, 0)]
      this._satFootprintEntities.push(dataSource.entities.add({
        polyline: {
          positions: new Cesium.CallbackProperty(() => this._nadirLinePositions, false),
          width: 3,
          material: baseColor.withAlpha(0.6),
        },
      }))

      // Nadir dot — use CallbackProperty for position
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
    } else {
      // Update existing entities in-place — no destroy/recreate
      hexOffsets.forEach(([dr, dc], i) => {
        const hexLat = lat + dr * rowH
        const hexLng = lng + dc * colW / cosCenter
        this._satFootprintEntities[i].polygon.hierarchy = new Cesium.PolygonHierarchy(this._buildHexVerts(hexLat, hexLng, S))
      })

      // Update nadir line + dot via their backing references (CallbackProperty reads these)
      this._nadirLinePositions = [satPos, Cesium.Cartesian3.fromDegrees(lng, lat, 0)]
      this._nadirDotPosition = Cesium.Cartesian3.fromDegrees(lng, lat, 0)
    }
  }

  GlobeController.prototype._renderCountryConstrainedHexes = function(baseColor, satLat, satLng, scanRadiusKm, scanRadiusDeg, satPos) {
    const Cesium = window.Cesium
    const dataSource = this.getSatellitesDataSource()
    const bb = this._selectedCountriesBbox

    // Hex grid params — use the heatmap grid size for consistency
    const S = 0.12
    const sqrt3 = Math.sqrt(3)
    const rowStep = S * 1.5
    const colStep = S * sqrt3

    // Scan area: intersection of country bbox and satellite scan circle
    const minLat = Math.max(bb.minLat, satLat - scanRadiusDeg)
    const maxLat = Math.min(bb.maxLat, satLat + scanRadiusDeg)
    const cosCenter = Math.cos(satLat * Math.PI / 180) || 0.01
    const lngSpread = scanRadiusDeg / cosCenter
    const minLng = Math.max(bb.minLng, satLng - lngSpread)
    const maxLng = Math.min(bb.maxLng, satLng + lngSpread)

    if (minLat >= maxLat || minLng >= maxLng) return

    let rendered = 0

    for (let la = minLat; la <= maxLat; la += rowStep) {
      for (let ln = minLng; ln <= maxLng; ln += colStep) {
        if (rendered >= 3000) break

        const cell = this._snapToHexGrid(la, ln)

        // Must be inside satellite scan radius
        const dLat = (cell.lat - satLat) * 111.32
        const dLng = (cell.lng - satLng) * 111.32 * cosCenter
        const distKm = Math.sqrt(dLat * dLat + dLng * dLng)
        if (distKm > scanRadiusKm) continue

        // Must be inside selected countries
        if (!this._pointInSelectedCountries(cell.lat, cell.lng)) continue

        const cosHex = Math.cos(cell.lat * Math.PI / 180) || 0.01
        const verts = []
        for (let i = 0; i < 6; i++) {
          const angle = (Math.PI / 3) * i + (Math.PI / 6) // pointy-top
          const vLat = cell.lat + S * Math.sin(angle)
          const vLng = cell.lng + (S * Math.cos(angle)) / cosHex
          verts.push(Cesium.Cartesian3.fromDegrees(vLng, vLat))
        }

        const falloff = Math.max(0, 1 - distKm / scanRadiusKm)
        const fillAlpha = 0.1 + falloff * 0.3
        const outlineAlpha = 0.3 + falloff * 0.5
        const extHeight = falloff * 1200

        const entity = dataSource.entities.add({
          polygon: {
            hierarchy: verts,
            material: baseColor.withAlpha(fillAlpha),
            outline: true,
            outlineColor: baseColor.withAlpha(outlineAlpha),
            outlineWidth: 1.5,
            height: 0,
            extrudedHeight: extHeight,
          },
        })
        this._satFootprintEntities.push(entity)
        rendered++
      }
    }

    // Nadir line
    this._satFootprintEntities.push(dataSource.entities.add({
      polyline: {
        positions: [satPos, Cesium.Cartesian3.fromDegrees(satLng, satLat, 0)],
        width: 2,
        material: baseColor.withAlpha(0.6),
      },
    }))

    // Nadir dot
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
    // Force re-render if a satellite is selected
    if (this._selectedSatPosition) {
      this.renderSatHexFootprint(this._selectedSatPosition)
    }
    // Refresh the detail panel to update button state
    if (this.selectedSatNoradId) {
      const satData = this.satelliteData.find(s => s.norad_id === this.selectedSatNoradId)
      if (satData) this.showSatelliteDetail(satData)
    }
  }

  // ── Satellite Visibility & Ground Events ────────────────────────

  GlobeController.prototype.showSatVisibility = function(event) {
    // Toggle: if already showing, hide
    if (this._satVisEntities?.length) {
      this._clearSatVisEntities()
      event.currentTarget.classList.remove("tracking")
      return
    }

    const lat = parseFloat(event.currentTarget.dataset.lat)
    const lng = parseFloat(event.currentTarget.dataset.lng)
    if (isNaN(lat) || isNaN(lng)) return

    event.currentTarget.classList.add("tracking")
    this._clearSatVisEntities()
    this._satVisEventPos = { lat, lng }

    const sat = window.satellite
    if (!sat || !this.satelliteData.length) {
      // Append message to detail panel
      const msg = document.createElement("div")
      msg.style.cssText = "margin-top:8px;font:400 10px var(--gt-mono);color:#ce93d8;"
      msg.textContent = "Enable satellite categories first to see overhead passes."
      event.currentTarget.parentNode.appendChild(msg)
      return
    }

    const Cesium = window.Cesium
    const now = new Date()
    const gmst = sat.gstime(now)
    const observerGd = {
      latitude: lat * Math.PI / 180,
      longitude: lng * Math.PI / 180,
      height: 0,
    }

    const visible = []

    this.satelliteData.forEach(s => {
      try {
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) return

        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        const satLng = sat.degreesLong(posGd.longitude)
        const satLat = sat.degreesLat(posGd.latitude)
        const satAlt = posGd.height // km

        if (isNaN(satLng) || isNaN(satLat) || isNaN(satAlt)) return

        // Compute look angles (elevation)
        const posEcf = sat.eciToEcf(posVel.position, gmst)
        const lookAngles = sat.ecfToLookAngles(observerGd, posEcf)
        const elevationDeg = lookAngles.elevation * 180 / Math.PI

        if (elevationDeg > 5) {
          visible.push({
            name: s.name,
            norad_id: s.norad_id,
            category: s.category,
            lat: satLat,
            lng: satLng,
            alt: satAlt,
            elevation: elevationDeg,
            azimuth: lookAngles.azimuth * 180 / Math.PI,
          })
        }
      } catch (e) {
        // Skip satellites with bad TLE
      }
    })

    // Sort by elevation (highest first) and limit to top 15
    visible.sort((a, b) => b.elevation - a.elevation)
    const top = visible.slice(0, 15)

    // Render visibility lines
    const dataSource = this.getSatellitesDataSource()

    top.forEach((s, i) => {
      const color = Cesium.Color.fromCssColorString(this.satCategoryColors[s.category] || "#ce93d8").withAlpha(0.5)

      // Line from satellite to ground event
      const line = dataSource.entities.add({
        id: `satvis-line-${i}`,
        polyline: {
          positions: [
            Cesium.Cartesian3.fromDegrees(s.lng, s.lat, s.alt * 1000),
            Cesium.Cartesian3.fromDegrees(lng, lat, 0),
          ],
          width: 1.5,
          material: new Cesium.PolylineDashMaterialProperty({
            color: color,
            dashLength: 16,
          }),
        },
      })
      this._satVisEntities.push(line)

      // Small label at satellite position
      const lbl = dataSource.entities.add({
        id: `satvis-lbl-${i}`,
        position: Cesium.Cartesian3.fromDegrees(s.lng, s.lat, s.alt * 1000),
        label: {
          text: `${s.name} (${s.elevation.toFixed(0)}°)`,
          font: "10px JetBrains Mono, monospace",
          fillColor: color.withAlpha(0.9),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          pixelOffset: new Cesium.Cartesian2(8, 0),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 5e7, 0.3),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1, 5e7, 0.1),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._satVisEntities.push(lbl)
    })

    // Ground marker at event location
    const groundMarker = dataSource.entities.add({
      id: "satvis-ground",
      position: Cesium.Cartesian3.fromDegrees(lng, lat, 0),
      ellipse: {
        semiMinorAxis: 50000,
        semiMajorAxis: 50000,
        material: Cesium.Color.fromCssColorString("#ce93d8").withAlpha(0.1),
        outline: true,
        outlineColor: Cesium.Color.fromCssColorString("#ce93d8").withAlpha(0.4),
        outlineWidth: 1,
        height: 0,
      },
    })
    this._satVisEntities.push(groundMarker)

    // Append satellite list to the detail panel
    const listHtml = top.length > 0
      ? top.map(s => {
          const catColor = this.satCategoryColors[s.category] || "#ce93d8"
          return `<div style="display:flex;justify-content:space-between;font:400 10px var(--gt-mono);color:var(--gt-text-dim);padding:1px 0;">
            <span style="color:${catColor};">${this._escapeHtml(s.name)}</span>
            <span>${s.elevation.toFixed(0)}° el · ${Math.round(s.alt)} km</span>
          </div>`
        }).join("")
      : `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">No satellites currently overhead. Enable more satellite categories.</div>`

    const container = document.createElement("div")
    container.id = "satvis-results"
    container.innerHTML = `
      <div style="margin-top:10px;padding:6px 8px;background:rgba(171,71,188,0.08);border:1px solid rgba(171,71,188,0.25);border-radius:4px;">
        <div style="font:600 9px var(--gt-mono);color:#ce93d8;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">
          <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>${top.length} SATELLITES OVERHEAD
        </div>
        ${listHtml}
      </div>
    `

    // Remove previous results if any
    document.getElementById("satvis-results")?.remove()
    this.detailContentTarget.appendChild(container)
  }

  GlobeController.prototype._clearSatVisEntities = function() {
    if (!this._satVisEntities?.length) return
    const ds = this._ds["satellites"]
    if (ds) {
      this._satVisEntities.forEach(e => ds.entities.remove(e))
    }
    this._satVisEntities = []
    this._satVisEventPos = null
    document.getElementById("satvis-results")?.remove()
    document.getElementById("ground-events-results")?.remove()
  }

  GlobeController.prototype.showGroundEvents = function(event) {
    // Toggle: if already showing, hide
    if (this._satVisEntities?.length) {
      this._clearSatVisEntities()
      event.currentTarget.classList.remove("tracking")
      return
    }

    const noradId = parseInt(event.currentTarget.dataset.norad)
    const satData = this.satelliteData.find(s => s.norad_id === noradId)
    if (!satData) return

    event.currentTarget.classList.add("tracking")

    const sat = window.satellite
    if (!sat) return
    const Cesium = window.Cesium
    const now = new Date()
    const gmst = sat.gstime(now)

    // Get satellite position
    const satrec = sat.twoline2satrec(satData.tle_line1, satData.tle_line2)
    const posVel = sat.propagate(satrec, now)
    if (!posVel.position) return
    const posGd = sat.eciToGeodetic(posVel.position, gmst)
    const satLat = sat.degreesLat(posGd.latitude)
    const satLng = sat.degreesLong(posGd.longitude)
    const satAltKm = posGd.height

    // Footprint radius: horizon distance from satellite altitude
    const footprintKm = Math.sqrt(2 * 6371 * satAltKm)
    const footprintM = footprintKm * 1000

    // Collect ground events within footprint
    const events = []
    const catIcons = { earthquake: "house-crack", natural: "bolt", conflict: "crosshairs", fire: "fire", news: "newspaper" }
    const catColors = { earthquake: "#ff7043", natural: "#66bb6a", conflict: "#f44336", fire: "#ff5722", news: "#ff9800" }

    // Earthquakes
    if (this._earthquakeData?.length) {
      this._earthquakeData.forEach(eq => {
        const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat: eq.lat, lng: eq.lng })
        if (dist <= footprintM) {
          events.push({ type: "earthquake", label: `M${eq.mag.toFixed(1)} ${eq.title}`, lat: eq.lat, lng: eq.lng, dist })
        }
      })
    }

    // Natural events
    if (this._naturalEventData?.length) {
      this._naturalEventData.forEach(ev => {
        const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat: ev.lat, lng: ev.lng })
        if (dist <= footprintM) {
          events.push({ type: "natural", label: ev.title, lat: ev.lat, lng: ev.lng, dist })
        }
      })
    }

    // Conflicts
    if (this._conflictData?.length) {
      this._conflictData.forEach(c => {
        if (!c.lat || !c.lng) return
        const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat: c.lat, lng: c.lng })
        if (dist <= footprintM) {
          events.push({ type: "conflict", label: `${c.conflict || "Conflict"} — ${c.country || ""}`, lat: c.lat, lng: c.lng, dist })
        }
      })
    }

    // Fire hotspots
    if (this._fireHotspotData?.length) {
      this._fireHotspotData.forEach(f => {
        const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat: f.lat, lng: f.lng })
        if (dist <= footprintM) {
          events.push({ type: "fire", label: `Fire ${f.lat.toFixed(2)}°, ${f.lng.toFixed(2)}° (${f.satellite || "?"})`, lat: f.lat, lng: f.lng, dist })
        }
      })
    }

    // News
    if (this._newsData?.length) {
      this._newsData.forEach(n => {
        if (!n.lat || !n.lng) return
        const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat: n.lat, lng: n.lng })
        if (dist <= footprintM) {
          events.push({ type: "news", label: n.title || "News", lat: n.lat, lng: n.lng, dist })
        }
      })
    }

    events.sort((a, b) => a.dist - b.dist)
    const top = events.slice(0, 20)

    // Draw lines from satellite to each ground event
    this._clearSatVisEntities()
    const dataSource = this.getSatellitesDataSource()
    const satColor = Cesium.Color.fromCssColorString(this.satCategoryColors[satData.category] || "#ce93d8")

    // Footprint circle on ground
    const fpCircle = dataSource.entities.add({
      id: "satvis-footprint",
      position: Cesium.Cartesian3.fromDegrees(satLng, satLat, 0),
      ellipse: {
        semiMinorAxis: footprintM,
        semiMajorAxis: footprintM,
        material: satColor.withAlpha(0.04),
        outline: true,
        outlineColor: satColor.withAlpha(0.2),
        outlineWidth: 1,
        height: 0,
      },
    })
    this._satVisEntities.push(fpCircle)

    top.forEach((ev, i) => {
      const evColor = Cesium.Color.fromCssColorString(catColors[ev.type] || "#ce93d8").withAlpha(0.5)
      const line = dataSource.entities.add({
        id: `satvis-gnd-${i}`,
        polyline: {
          positions: [
            Cesium.Cartesian3.fromDegrees(satLng, satLat, satAltKm * 1000),
            Cesium.Cartesian3.fromDegrees(ev.lng, ev.lat, 0),
          ],
          width: 1.5,
          material: new Cesium.PolylineDashMaterialProperty({ color: evColor, dashLength: 16 }),
        },
      })
      this._satVisEntities.push(line)
    })

    // Build results HTML
    const listHtml = top.length > 0
      ? top.map(ev => {
          const color = catColors[ev.type] || "#ce93d8"
          const icon = catIcons[ev.type] || "circle"
          const distKm = Math.round(ev.dist / 1000)
          return `<div style="display:flex;gap:6px;align-items:start;font:400 10px var(--gt-mono);color:var(--gt-text-dim);padding:2px 0;">
            <i class="fa-solid fa-${icon}" style="color:${color};margin-top:2px;font-size:9px;flex-shrink:0;"></i>
            <span style="flex:1;line-height:1.3;">${this._escapeHtml(ev.label)}</span>
            <span style="flex-shrink:0;color:${color};">${distKm} km</span>
          </div>`
        }).join("")
      : `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">No active events in footprint. Enable event layers (EQ, EVT, WAR, FIRE, NEWS).</div>`

    const container = document.createElement("div")
    container.id = "ground-events-results"
    container.innerHTML = `
      <div style="margin-top:10px;padding:6px 8px;background:rgba(171,71,188,0.08);border:1px solid rgba(171,71,188,0.25);border-radius:4px;">
        <div style="font:600 9px var(--gt-mono);color:#ce93d8;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">
          <i class="fa-solid fa-crosshairs" style="margin-right:4px;"></i>${top.length} EVENTS IN FOOTPRINT
          <span style="font-weight:400;text-transform:none;margin-left:4px;">(${Math.round(footprintKm)} km radius)</span>
        </div>
        ${listHtml}
      </div>
    `
    document.getElementById("ground-events-results")?.remove()
    this.detailContentTarget.appendChild(container)
  }
}
