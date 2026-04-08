import { getDataSource } from "globe/utils"

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

    if (!this._conflictPulseData?.length) return

    const prev = this._conflictPulsePrevScores || {}
    const increased = new Set()
    this._conflictPulseData.forEach(z => {
      const prevScore = prev[z.cell_key]
      if (prevScore !== undefined && z.pulse_score >= prevScore + 5) increased.add(z.cell_key)
    })
    this._conflictPulsePrevScores = {}
    this._conflictPulseData.forEach(z => { this._conflictPulsePrevScores[z.cell_key] = z.pulse_score })

    this._pulsingRings = []

    ds.entities.suspendEvents()

    if (this._hexCellData?.length && this._hexTheaterVisible !== false) {
      this._hexCellData.forEach((cell, idx) => {
        const t = cell.intensity
        if (t < 0.01) return
        if (!cell.vertices || cell.vertices.length !== 6) return
        const r = 255
        const g = Math.round(180 * (1 - t * 0.8))
        const b = Math.round(50 * (1 - t))
        const hexColor = Cesium.Color.fromBytes(r, g, b)
        const positions = cell.vertices.map(v => Cesium.Cartesian3.fromDegrees(v[1], v[0]))

        const hex = ds.entities.add({
          id: `cpulse-hex-${idx}`,
          polygon: {
            hierarchy: new Cesium.PolygonHierarchy(positions),
            material: hexColor.withAlpha(0.18 + t * 0.35),
            outline: true,
            outlineColor: hexColor.withAlpha(0.5 + t * 0.4),
            outlineWidth: 2,
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

    this._conflictPulseData.forEach((zone, idx) => {
      const zoneKey = this._conflictPulseEntityKey(zone.cell_key || `zone-${idx}`)
      const score = zone.pulse_score
      const t = Math.min((score - 20) / 60, 1)

      let r, g, b
      if (score >= 70) {
        r = 244; g = 67; b = 54
      } else if (score >= 50) {
        r = 255; g = 152; b = 0
      } else {
        r = 255; g = 193; b = 7
      }
      const color = Cesium.Color.fromBytes(r, g, b)
      const radius = score >= 50 ? (100000 + score * 2000) : (60000 + score * 1000)
      const baseAlpha = score >= 70 ? 0.15 : (score >= 50 ? 0.10 : 0.04)
      const outlineAlpha = score >= 70 ? 0.6 : (score >= 50 ? 0.4 : 0.15)

      const ring = ds.entities.add({
        id: `cpulse-ring-${zoneKey}`,
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
        ellipse: {
          semiMajorAxis: radius,
          semiMinorAxis: radius,
          material: color.withAlpha(baseAlpha),
          outline: true,
          outlineColor: color.withAlpha(outlineAlpha),
          outlineWidth: score >= 50 ? 2 : 1,
          height: 5100,
        },
      })
      this._conflictPulseEntities.push(ring)

      const shouldPulse = this._timelineActive
        ? increased.has(zone.cell_key)
        : (zone.escalation_trend === "surging" || zone.escalation_trend === "active" || increased.has(zone.cell_key))

      if (shouldPulse) {
        const pulseRing = ds.entities.add({
          id: `cpulse-pulse-${zoneKey}`,
          position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
          ellipse: {
            semiMajorAxis: this._timelineActive ? radius * 1.28 : radius,
            semiMinorAxis: this._timelineActive ? radius * 1.28 : radius,
            material: this._timelineActive ? color.withAlpha(0.03) : Cesium.Color.TRANSPARENT,
            outline: true,
            outlineColor: color.withAlpha(this._timelineActive ? 0.42 : 0.8),
            outlineWidth: this._timelineActive ? 2 : 3,
            height: 5200,
          },
        })
        this._conflictPulseEntities.push(pulseRing)
        if (!this._timelineActive) {
          this._pulsingRings.push({ entity: pulseRing, baseRadius: radius, color, phaseOffset: idx * 0.7 })
        }
      }

      if (score >= 50) {
        const core = ds.entities.add({
          id: `cpulse-core-${zoneKey}`,
          position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
          ellipse: {
            semiMajorAxis: radius * 0.25,
            semiMinorAxis: radius * 0.25,
            material: color.withAlpha(0.2 + t * 0.15),
            outline: false,
            height: 5100,
          },
        })
        this._conflictPulseEntities.push(core)
      }

      const trendArrow = { surging: "▲", escalating: "↗", elevated: "→", active: "●", baseline: "↓" }[zone.escalation_trend] || ""
      const iconSize = score >= 70 ? 48 : (score >= 50 ? 44 : 36)
      const point = ds.entities.add({
        id: `cpulse-${zoneKey}`,
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat, 5500),
        billboard: {
          image: this._makePulseIcon(trendArrow, color.toCssColorString(), score),
          width: iconSize,
          height: iconSize,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          scaleByDistance: new Cesium.NearFarScalar(3e5, 1.2, 8e6, 0.5),
        },
        label: {
          text: zone.situation_name || (zone.escalation_trend || "").toUpperCase(),
          font: "bold 13px 'JetBrains Mono', monospace",
          fillColor: Cesium.Color.WHITE,
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 5,
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

    ;(this._strategicSituationData || []).forEach((item, idx) => {
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

      this._pulsingRings.forEach(({ entity, baseRadius, color, phaseOffset }) => {
        if (!entity.ellipse) return
        const phase = ((elapsed + phaseOffset) % 3) / 3
        const expandFactor = 1.0 + phase * 0.5
        const alpha = 0.8 * (1 - phase)
        entity.ellipse.semiMajorAxis = baseRadius * expandFactor
        entity.ellipse.semiMinorAxis = baseRadius * expandFactor
        entity.ellipse.outlineColor = color.withAlpha(alpha)
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
