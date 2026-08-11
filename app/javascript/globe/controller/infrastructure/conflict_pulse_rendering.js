import { getDataSource } from "globe/utils"
import {
  attentionAnchorLabel,
  attentionPalette,
  attentionSeverity,
  shouldRenderAttentionSurface,
} from "globe/controller/infrastructure/conflict_pulse_attention"
import { ambientHash01 } from "globe/controller/ambient_pulse"

export function applyConflictPulseRenderingMethods(GlobeController) {
  GlobeController.prototype._conflictPulseEntityKey = function(value, fallback = "unknown") {
    return encodeURIComponent(String(value ?? fallback))
  }

  GlobeController.prototype._renderConflictPulse = function() {
    if (!this.situationsVisible) {
      this._clearConflictPulseEntities()
      return
    }
    this._clearConflictPulseEntities()
    if (this._pulseAnimFrame) {
      cancelAnimationFrame(this._pulseAnimFrame)
      this._pulseAnimFrame = null
    }

    const Cesium = window.Cesium
    const ds = getDataSource(this.viewer, this._ds, "conflictPulse")

    const zones = this._conflictPulseData || []
    const hexCells = this._hexCellData || []
    const strategicSituations = this._strategicSituationData || []
    if (!zones.length && !hexCells.length && !strategicSituations.length) return

    const prev = this._conflictPulsePrevScores || {}
    const increased = new Set()
    zones.forEach(z => {
      const prevScore = prev[z.cell_key]
      if (prevScore !== undefined && z.pulse_score >= prevScore + 5) increased.add(z.cell_key)
    })
    this._conflictPulsePrevScores = {}
    zones.forEach(z => { this._conflictPulsePrevScores[z.cell_key] = z.pulse_score })

    this._pulsingRings = []

    ds.entities.suspendEvents()

    const surfaceZones = zones
      .map((zone, idx) => ({ zone, idx }))
      .filter(({ zone, idx }) => shouldRenderAttentionSurface(zone, idx))
      .slice(0, 12)
    const surfaceZoneKeys = new Set(surfaceZones.map(({ zone }) => zone.cell_key))

    if (hexCells.length && this._hexTheaterVisible === true) {
      hexCells.forEach((cell, idx) => {
        const t = cell.intensity
        if (t < 0.01) return
        if (!cell.vertices || cell.vertices.length !== 6) return
        const zone = zones.find(candidate => candidate.cell_key === cell.zone_key)
        if (!shouldRenderHexCell(cell, zone, {
          surfaceZoneKeys,
          highlightedTheater: this._highlightedTheater,
        })) return
        const palette = zone ? attentionPalette(zone) : { fill: "#854d0e", stroke: "#facc15" }
        const hexColor = Cesium.Color.fromCssColorString(palette.fill)
        const positions = cell.vertices.map(v => Cesium.Cartesian3.fromDegrees(v[1], v[0]))

        const hex = ds.entities.add({
          id: `cpulse-hex-${idx}`,
          polygon: {
            hierarchy: new Cesium.PolygonHierarchy(positions),
            material: hexColor.withAlpha(0.05 + t * 0.16),
            outline: false,
            height: 5000,
          },
          properties: {
            zone_key: cell.zone_key || "",
            situation: cell.situation || "",
            theater: cell.theater || "",
            count: cell.count,
          },
        })
        this._conflictPulseEntities.push(hex)
      })
    }

    // Attention-region ellipses removed: they were synthetic shapes drawn around a
    // cluster centroid, and the country/admin-boundary surfaces already carry the
    // real conflict geography. surfaceZones is still computed above because the hex
    // filter uses surfaceZoneKeys to decide which cells belong to a ranked zone.

    if (this._strikeArcData?.length && this._strikeArcsVisible !== false) {
      this._strikeArcData.forEach((arc, idx) => {
        if (arc.count < 2) return
        const t = Math.min(arc.count / 20, 1)
        const arcColor = Cesium.Color.fromCssColorString("#f44336")
        const width = Math.max(8, Math.min(1.5 + arc.count * 0.2, 12))
        const arcPositions = this._buildArcPositions(arc.from_lat, arc.from_lng, arc.to_lat, arc.to_lng, 30)
        if (!arcPositions.length) return

        const line = ds.entities.add({
          id: `cpulse-arc-${idx}`,
          polyline: {
            positions: arcPositions,
            width: width,
            material: new Cesium.PolylineGlowMaterialProperty({
              glowPower: 0.15,
              color: arcColor.withAlpha(0.3 + t * 0.4),
            }),
          },
          properties: {
            arcIdx: idx,
            clickable: true,
          },
        })
        this._conflictPulseEntities.push(line)

        const midIdx = Math.floor(arcPositions.length / 2)
        const midLabel = ds.entities.add({
          id: `cpulse-arc-lbl-${idx}`,
          position: arcPositions[midIdx],
          label: {
            text: `${arc.from_name} → ${arc.to_name} (${arc.count})`,
            font: "bold 10px 'JetBrains Mono', monospace",
            fillColor: Cesium.Color.WHITE.withAlpha(0.8),
            outlineColor: Cesium.Color.BLACK,
            outlineWidth: 3,
            style: Cesium.LabelStyle.FILL_AND_OUTLINE,
            verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
            horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
            pixelOffset: new Cesium.Cartesian2(0, -6),
            disableDepthTestDistance: Number.POSITIVE_INFINITY,
            scaleByDistance: new Cesium.NearFarScalar(5e5, 0.8, 8e6, 0.0),
            translucencyByDistance: new Cesium.NearFarScalar(5e5, 0.8, 8e6, 0.0),
          },
          properties: {
            arcIdx: idx,
            clickable: true,
          },
        })
        this._conflictPulseEntities.push(midLabel)
      })
    }

    zones.forEach((zone, idx) => {
      const zoneKey = this._conflictPulseEntityKey(zone.cell_key || `zone-${idx}`)
      const score = Number(zone.pulse_score || 0)
      const t = Math.min((score - 20) / 60, 1)
      const palette = attentionPalette(zone)
      const severity = attentionSeverity(zone)
      const color = Cesium.Color.fromCssColorString(palette.stroke)
      const radius = score >= 50 ? (46000 + score * 900) : (32000 + score * 700)
      const baseAlpha = severity === "critical" ? 0.08 : (severity === "high" ? 0.06 : 0.035)
      const outlineAlpha = severity === "critical" ? 0.75 : (severity === "high" ? 0.55 : 0.28)

      const timelineChanged = this._timelineActive && increased.has(zone.cell_key)
      const ring = ds.entities.add({
        id: `cpulse-ring-${zoneKey}`,
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
        ellipse: {
          semiMajorAxis: radius,
          semiMinorAxis: radius,
          material: color.withAlpha(this._timelineActive ? baseAlpha * (timelineChanged ? 1.2 : 0.9) : baseAlpha),
          outline: true,
          outlineColor: color.withAlpha(this._timelineActive ? outlineAlpha * (timelineChanged ? 1.15 : 0.75) : outlineAlpha),
          outlineWidth: this._timelineActive ? (timelineChanged ? 3 : 1.5) : (score >= 50 ? 2 : 1),
          height: 0,
          heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
          classificationType: Cesium.ClassificationType.BOTH,
          zIndex: 1100 + idx,
        },
      })
      this._conflictPulseEntities.push(ring)

      // Every live zone pulses. The old gate required critical severity or a
      // "surging" trend, and real data carries neither, so nothing ever animated.
      // Intensity now scales with the zone instead of gating it on/off.
      const shouldPulse = !this._timelineActive
      const emphasis = severity === "critical" || zone.escalation_trend === "surging" || increased.has(zone.cell_key)

      if (shouldPulse) {
        const strength = emphasis ? 1 : 0.35 + Math.min(Math.max(t, 0), 1) * 0.4
        const pulseRing = ds.entities.add({
          id: `cpulse-pulse-${zoneKey}`,
          position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
          ellipse: {
            semiMajorAxis: radius,
            semiMinorAxis: radius,
            material: Cesium.Color.TRANSPARENT,
            outline: true,
            outlineColor: color.withAlpha(0.8 * strength),
            outlineWidth: emphasis ? 3 : 2,
            height: 0,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            classificationType: Cesium.ClassificationType.BOTH,
            zIndex: 1200 + idx,
          },
        })
        this._conflictPulseEntities.push(pulseRing)
        // Hash-derived phase and period so zones never ripple in lockstep.
        const seed = ambientHash01(`${zone.cell_key || zoneKey}`)
        this._pulsingRings.push({
          entity: pulseRing,
          baseRadius: radius,
          color,
          strength,
          phaseOffset: seed,
          period: 2.8 + ambientHash01(`${zone.cell_key || zoneKey}#p`) * 1.8,
        })
      }

      if (score >= 55) {
        const core = ds.entities.add({
          id: `cpulse-core-${zoneKey}`,
          position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
          ellipse: {
            semiMajorAxis: radius * 0.25,
            semiMinorAxis: radius * 0.25,
            material: color.withAlpha(0.2 + t * 0.15),
            outline: false,
            height: 0,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            classificationType: Cesium.ClassificationType.BOTH,
            zIndex: 1300 + idx,
          },
        })
        this._conflictPulseEntities.push(core)
      }

      const anchorLabel = attentionAnchorLabel(zone)
      const iconSize = severity === "critical" ? 48 : (severity === "high" ? 42 : 34)
      const iconWidth = Math.max(iconSize * 1.5, Math.min(118, 24 + anchorLabel.length * 11))
      const iconHeight = Math.round(iconSize * 0.62)
      const showLabel = severity === "critical" || severity === "high" || idx < 8
      const point = ds.entities.add({
        id: `cpulse-${zoneKey}`,
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat, 85000),
        billboard: {
          image: this._makeAttentionAnchorIcon(anchorLabel, color.toCssColorString(), severity),
          width: iconWidth,
          height: iconHeight,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(3e5, 1.2, 8e6, 0.5),
        },
        label: {
          text: showLabel ? (zone.situation_name || (zone.escalation_trend || "").toUpperCase()) : "",
          font: "bold 12px 'JetBrains Mono', monospace",
          fillColor: Cesium.Color.fromCssColorString(palette.label).withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 5,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, iconHeight / 2 + 8),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(3e5, 1.0, 8e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(3e5, 1.0, 1e7, 0.0),
        },
      })
      this._conflictPulseEntities.push(point)
    })

    strategicSituations.forEach((item, idx) => {
      const strategicKey = this._conflictPulseEntityKey(item.id || item.node_id || item.name || `strategic-${idx}`)
      const statusColors = {
        critical: "#ff7043",
        elevated: "#ffca28",
        monitoring: "#26c6da",
      }
      const color = Cesium.Color.fromCssColorString(statusColors[item.status] || "#26c6da")
      const radius = 70000 + ((item.strategic_score || 0) * 1200)
      const iconSize = item.status === "critical" ? 34 : 30

      const ring = ds.entities.add({
        id: `cpulse-strat-ring-${strategicKey}`,
        position: Cesium.Cartesian3.fromDegrees(item.lng, item.lat),
        ellipse: {
          semiMajorAxis: radius,
          semiMinorAxis: radius,
          material: color.withAlpha(0.05),
          outline: true,
          outlineColor: color.withAlpha(0.5),
          outlineWidth: 2,
          height: 5300,
        },
      })
      this._conflictPulseEntities.push(ring)

      const point = ds.entities.add({
        id: `cpulse-strat-${strategicKey}`,
        position: Cesium.Cartesian3.fromDegrees(item.lng, item.lat, 5600),
        billboard: {
          image: this._makeStrategicSituationIcon(item, statusColors[item.status] || "#26c6da"),
          width: iconSize,
          height: iconSize,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(3e5, 1.1, 8e6, 0.45),
        },
        label: {
          text: item.name || "Strategic node",
          font: "bold 12px 'JetBrains Mono', monospace",
          fillColor: color.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 4,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.TOP,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, iconSize / 2 + 8),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(3e5, 1.0, 8e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(3e5, 1.0, 1e7, 0.0),
        },
      })
      this._conflictPulseEntities.push(point)
    })
    ds.entities.resumeEvents()
    if (this._updateGlobeOcclusion) this._updateGlobeOcclusion()

    if (!this._timelineActive && this._pulsingRings.length > 0) {
      this._startPulseAnimation()
    }

    this._requestRender()
  }

  GlobeController.prototype._startPulseAnimation = function() {
    if (this._pulseAnimFrame) return
    const startTime = performance.now()

    const animate = () => {
      if (!this._pulsingRings?.length) return
      const elapsed = (performance.now() - startTime) / 1000

      this._pulsingRings.forEach(({ entity, color, phaseOffset, period, strength = 1 }) => {
        if (!entity.ellipse) return
        const cycle = period || 3
        // phaseOffset is a 0..1 fraction of the cycle, so each ring starts elsewhere.
        const phase = (((elapsed / cycle) + phaseOffset) % 1 + 1) % 1
        // Colour only. These are CLAMP_TO_GROUND + classificationType.BOTH ellipses:
        // changing semiMajorAxis/semiMinorAxis per frame makes Cesium rebuild the
        // classified geometry every frame, which throws out of
        // createPotentiallyVisibleSet and kills the render loop. A colour change is
        // a per-instance attribute update, so the geometry is left alone.
        const glow = 0.5 - 0.5 * Math.cos(phase * Math.PI * 2)
        entity.ellipse.outlineColor = color.withAlpha(0.2 + 0.65 * strength * glow)
      })

      this._requestRender()
      this._pulseAnimFrame = requestAnimationFrame(animate)
    }

    this._pulseAnimFrame = requestAnimationFrame(animate)
  }

  GlobeController.prototype._clearConflictPulseEntities = function() {
    if (this._pulseAnimFrame) {
      cancelAnimationFrame(this._pulseAnimFrame)
      this._pulseAnimFrame = null
    }
    this._pulsingRings = []
    const ds = this._ds["conflictPulse"]
    if (ds && this._conflictPulseEntities?.length) {
      ds.entities.suspendEvents()
      this._conflictPulseEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents()
    }
    this._conflictPulseEntities = []
  }

  GlobeController.prototype._buildArcPositions = function(lat1, lng1, lat2, lng2, segments) {
    const Cesium = window.Cesium
    const positions = []

    for (let i = 0; i <= segments; i++) {
      const t = i / segments
      const lat = lat1 + (lat2 - lat1) * t
      const lng = lng1 + (lng2 - lng1) * t
      const arcHeight = Math.sin(t * Math.PI) * 200000
      positions.push(Cesium.Cartesian3.fromDegrees(lng, lat, arcHeight))
    }
    return positions
  }

  GlobeController.prototype._makeAttentionAnchorIcon = function(label, color, severity) {
    const key = `attention-${label}-${color}-${severity}`
    if (this._iconCache?.[key]) return this._iconCache[key]
    if (!this._iconCache) this._iconCache = {}

    const width = Math.max(72, Math.min(118, 24 + `${label}`.length * 11))
    const height = 42
    const canvas = document.createElement("canvas")
    canvas.width = width
    canvas.height = height
    const ctx = canvas.getContext("2d")

    ctx.beginPath()
    ctx.roundRect(4, 7, width - 8, height - 14, 12)
    ctx.fillStyle = "rgba(5,8,14,0.88)"
    ctx.fill()
    ctx.strokeStyle = color
    ctx.lineWidth = severity === "critical" ? 3 : 2.25
    ctx.stroke()

    ctx.font = "bold 17px 'JetBrains Mono', monospace"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = "#f8fafc"
    ctx.fillText(label, width / 2, height / 2 + 1)

    if (severity === "critical") {
      ctx.beginPath()
      ctx.arc(width - 12, 11, 4, 0, Math.PI * 2)
      ctx.fillStyle = color
      ctx.fill()
    }

    const url = canvas.toDataURL()
    this._iconCache[key] = url
    return url
  }

  GlobeController.prototype._makePulseIcon = function(trendArrow, color, score) {
    const key = `pulse-${trendArrow}-${color}-${score}`
    if (this._iconCache?.[key]) return this._iconCache[key]
    if (!this._iconCache) this._iconCache = {}

    const size = 52
    const canvas = document.createElement("canvas")
    canvas.width = size
    canvas.height = size
    const ctx = canvas.getContext("2d")
    const cx = size / 2
    const r = size / 2 - 2

    ctx.beginPath()
    ctx.arc(cx, cx, r, 0, Math.PI * 2)
    ctx.fillStyle = "rgba(0,0,0,0.9)"
    ctx.fill()
    ctx.strokeStyle = color
    ctx.lineWidth = 3
    ctx.stroke()

    ctx.font = "bold 18px 'JetBrains Mono', monospace"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = "#fff"
    ctx.fillText(score, cx, trendArrow ? cx - 4 : cx)

    if (trendArrow) {
      ctx.font = "bold 11px sans-serif"
      ctx.fillStyle = color
      ctx.fillText(trendArrow, cx, cx + 12)
    }

    const url = canvas.toDataURL()
    this._iconCache[key] = url
    return url
  }

  GlobeController.prototype._makeStrategicSituationIcon = function(item, color) {
    const key = `strategic-${item.id}-${item.status}-${item.strategic_score}`
    if (this._iconCache?.[key]) return this._iconCache[key]
    if (!this._iconCache) this._iconCache = {}

    const size = 40
    const canvas = document.createElement("canvas")
    canvas.width = size
    canvas.height = size
    const ctx = canvas.getContext("2d")

    ctx.beginPath()
    ctx.roundRect(4, 4, size - 8, size - 8, 8)
    ctx.fillStyle = "rgba(7,10,15,0.92)"
    ctx.fill()
    ctx.strokeStyle = color
    ctx.lineWidth = 2.5
    ctx.stroke()

    ctx.font = "bold 16px 'JetBrains Mono', monospace"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = color
    ctx.fillText("S", size / 2, 14)

    ctx.font = "bold 11px 'JetBrains Mono', monospace"
    ctx.fillStyle = "#fff"
    ctx.fillText(`${item.strategic_score || 0}`, size / 2, 27)

    const url = canvas.toDataURL()
    this._iconCache[key] = url
    return url
  }
}

function shouldRenderHexCell(cell, zone, options = {}) {
  if (!zone) return false
  if (options.surfaceZoneKeys?.size && cell.zone_key && !options.surfaceZoneKeys.has(cell.zone_key) && !options.highlightedTheater) return false
  if (options.highlightedTheater && cell.theater === options.highlightedTheater) return true

  const center = cellCenter(cell)
  if (!center) return false

  const distanceKm = approxDistanceKm(center, zone)
  return Number.isFinite(distanceKm) && distanceKm <= maxHexDistanceKm(zone)
}

function cellCenter(cell) {
  if (Number.isFinite(Number(cell?.lat)) && Number.isFinite(Number(cell?.lng))) {
    return { lat: Number(cell.lat), lng: Number(cell.lng) }
  }

  const vertices = Array.isArray(cell?.vertices) ? cell.vertices : []
  const points = vertices.filter(vertex => Array.isArray(vertex) && vertex.length >= 2)
  if (!points.length) return null

  return {
    lat: points.reduce((sum, vertex) => sum + Number(vertex[0] || 0), 0) / points.length,
    lng: points.reduce((sum, vertex) => sum + Number(vertex[1] || 0), 0) / points.length,
  }
}

function approxDistanceKm(a, b) {
  const lat1 = Number(a?.lat)
  const lng1 = Number(a?.lng)
  const lat2 = Number(b?.lat)
  const lng2 = Number(b?.lng)
  if (![lat1, lng1, lat2, lng2].every(Number.isFinite)) return Number.POSITIVE_INFINITY

  const dlat = (lat1 - lat2) * 111
  const meanLat = ((lat1 + lat2) / 2) * Math.PI / 180
  const dlng = (lng1 - lng2) * 111 * Math.max(Math.cos(meanLat), 0.1)
  return Math.sqrt(dlat ** 2 + dlng ** 2)
}

function maxHexDistanceKm(zone) {
  const score = Number(zone?.pulse_score || 0)
  if (zone?.analysis_context === "kinetic_conflict") return score >= 80 ? 420 : 340
  if (zone?.attention_state === "strategic_pressure") return 300
  return score >= 55 ? 280 : 220
}
