import { getDataSource, cachedColor } from "../../utils"
import { COUNTRY_CENTROIDS } from "../../country_centroids"

export function applyTrafficMethods(GlobeController) {
  GlobeController.prototype.getTrafficDataSource = function() { return getDataSource(this.viewer, this._ds, "traffic") }

  GlobeController.prototype.toggleTraffic = function() {
    this.trafficVisible = this.hasTrafficToggleTarget && this.trafficToggleTarget.checked
    if (this.trafficVisible) {
      this.fetchTraffic()
      if (this.hasTrafficArcControlsTarget) this.trafficArcControlsTarget.style.display = ""
    } else {
      this._clearTrafficEntities()
      this._trafficData = null
      if (this.hasTrafficArcControlsTarget) this.trafficArcControlsTarget.style.display = "none"
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype.toggleTrafficArcs = function() {
    this.trafficArcsVisible = this.hasTrafficArcsToggleTarget && this.trafficArcsToggleTarget.checked
    if (!this.trafficArcsVisible) {
      this.trafficBlobsVisible = false
      if (this.hasTrafficBlobsToggleTarget) this.trafficBlobsToggleTarget.checked = false
      this._clearTrafficEntities()
      if (this._trafficData) this.renderTraffic()
    } else if (this._trafficData) {
      this._clearTrafficEntities()
      this.renderTraffic()
    }
  }

  GlobeController.prototype.toggleTrafficBlobs = function() {
    this.trafficBlobsVisible = this.hasTrafficBlobsToggleTarget && this.trafficBlobsToggleTarget.checked
    if (this.trafficBlobsVisible && !this.trafficArcsVisible) {
      this.trafficBlobsVisible = false
      if (this.hasTrafficBlobsToggleTarget) this.trafficBlobsToggleTarget.checked = false
      return
    }
    if (!this.trafficBlobsVisible) {
      this._stopTrafficBlobAnim()
      this._removeTrafficBlobEntities()
    } else if (this._trafficData) {
      this._clearTrafficEntities()
      this.renderTraffic()
    }
  }

  GlobeController.prototype.fetchTraffic = async function() {
    if (this._timelineActive) return
    this._toast("Loading internet traffic...")
    try {
      const resp = await fetch("/api/internet_traffic")
      if (!resp.ok) return
      this._trafficData = await resp.json()
      const hasData = (this._trafficData.traffic?.length || 0) > 0 || (this._trafficData.attack_pairs?.length || 0) > 0
      this._handleBackgroundRefresh(resp, "internet-traffic", hasData, () => {
        if (this.trafficVisible && !this._timelineActive) this.fetchTraffic()
      })
      this.renderTraffic()
      this._markFresh("traffic")
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch internet traffic:", e)
    }
  }

  GlobeController.prototype.renderTraffic = function() {
    this._clearTrafficEntities()
    if (!this._trafficData) return

    const Cesium = window.Cesium
    const dataSource = this.getTrafficDataSource()
    dataSource.entities.suspendEvents()

    const CC = COUNTRY_CENTROIDS

    const traffic = this._trafficData.traffic || []
    const maxTraffic = traffic.length > 0 ? Math.max(...traffic.map(t => t.traffic || 0)) : 1

    // Traffic volume markers (blue-green gradient)
    traffic.forEach(t => {
      const centroid = CC[t.code]
      if (!centroid || !t.traffic) return

      const intensity = t.traffic / maxTraffic
      const pixelSize = 6 + intensity * 20
      // Blue (low) → green (high)
      const r = Math.round(30 * (1 - intensity))
      const g = Math.round(200 + 55 * intensity)
      const b = Math.round(220 * (1 - intensity) + 80)
      const color = Cesium.Color.fromBytes(r, g, b, 200)

      const entity = dataSource.entities.add({
        id: `traf-${t.code}`,
        position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 50),
        point: {
          pixelSize,
          color,
          outlineColor: color.withAlpha(0.3),
          outlineWidth: 3,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 1e7, 0.5),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: `${t.code} ${t.traffic.toFixed(1)}%`,
          font: "12px JetBrains Mono, monospace",
          fillColor: color.withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 3,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, -14),
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 8e6, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(1e5, 1.0, 1e7, 0),
        },
      })
      this._trafficEntities.push(entity)

      // Attack indicator ring (red) if country is attack target
      if (t.attack_target > 0.5) {
        const atkIntensity = Math.min(t.attack_target / 20, 1)
        const atkColor = cachedColor("#f44336")
        const ring = dataSource.entities.add({
          id: `traf-atk-${t.code}`,
          position: Cesium.Cartesian3.fromDegrees(centroid[1], centroid[0], 0),
          ellipse: {
            semiMinorAxis: 50000 + atkIntensity * 250000,
            semiMajorAxis: 50000 + atkIntensity * 250000,
            material: atkColor.withAlpha(0.06 + atkIntensity * 0.06),
            outline: true,
            outlineColor: atkColor.withAlpha(0.2 + atkIntensity * 0.2),
            outlineWidth: 1,
            height: 0,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            classificationType: Cesium.ClassificationType.BOTH,
          },
        })
        this._trafficEntities.push(ring)
      }
    })

    // DDoS attack arcs (origin → target) with labels and directional arrows
    const pairs = this._trafficData.attack_pairs || []

    // Build set of attacked country codes for cross-layer correlation
    const prevAttacked = this._attackedCountries || new Set()
    this._attackedCountries = new Set()
    pairs.forEach(p => { if (p.pct > 0.5) this._attackedCountries.add(p.target) })

    // Only re-render infra layers if attacked countries actually changed
    const attacksChanged = prevAttacked.size !== this._attackedCountries.size ||
      [...this._attackedCountries].some(c => !prevAttacked.has(c))
    if (attacksChanged) {
      if (this.powerPlantsVisible) this.renderPowerPlants()
      if (this.cablesVisible) this._refreshCableAttackHighlights()
    }
    this._updateThreatsPanel()

    if (!this.trafficArcsVisible) {
      dataSource.entities.resumeEvents(); this._requestRender()
      return
    }

    pairs.forEach((p, idx) => {
      const originC = CC[p.origin]
      const targetC = CC[p.target]
      if (!originC || !targetC) return

      const pct = p.pct || 1
      const arcWidth = Math.max(6, pct * 0.4)
      const arcAlpha = Math.min(0.3 + pct * 0.02, 0.8)

      // Build a raised geodesic arc with multiple segments for smooth curve
      const oLat = originC[0] * Math.PI / 180, oLng = originC[1] * Math.PI / 180
      const tLat = targetC[0] * Math.PI / 180, tLng = targetC[1] * Math.PI / 180
      const SEGS = 40
      const arcPositions = []
      for (let i = 0; i <= SEGS; i++) {
        const f = i / SEGS
        // Spherical interpolation (SLERP on the sphere surface)
        const d = Math.acos(Math.sin(oLat)*Math.sin(tLat) + Math.cos(oLat)*Math.cos(tLat)*Math.cos(tLng-oLng))
        if (d < 0.001) break // same point
        const A = Math.sin((1-f)*d)/Math.sin(d)
        const B = Math.sin(f*d)/Math.sin(d)
        const x = A*Math.cos(oLat)*Math.cos(oLng) + B*Math.cos(tLat)*Math.cos(tLng)
        const y = A*Math.cos(oLat)*Math.sin(oLng) + B*Math.cos(tLat)*Math.sin(tLng)
        const z = A*Math.sin(oLat) + B*Math.sin(tLat)
        const lat = Math.atan2(z, Math.sqrt(x*x+y*y)) * 180/Math.PI
        const lng = Math.atan2(y, x) * 180/Math.PI
        // Raise the arc in the middle (parabolic lift)
        const lift = Math.sin(f * Math.PI) * (200000 + d * 1500000)
        arcPositions.push(Cesium.Cartesian3.fromDegrees(lng, lat, lift))
      }
      if (arcPositions.length < 2) return

      // Arc line — dimmer base trail
      const arcColor = Cesium.Color.fromCssColorString("#f44336").withAlpha(arcAlpha * 0.5)
      const arc = dataSource.entities.add({
        id: `traf-arc-${idx}`,
        polyline: {
          positions: arcPositions,
          width: arcWidth,
          material: new Cesium.PolylineGlowMaterialProperty({
            glowPower: 0.15,
            color: arcColor,
          }),
        },
      })
      this._trafficEntities.push(arc)

      // Animated attack blobs — 1 to 4 based on severity, staggered along path
      if (this.trafficBlobsVisible) {
        const blobCount = Math.min(4, Math.max(1, Math.ceil(pct / 5)))
        const speed = 0.3 + Math.min(pct * 0.01, 0.4) // 0.3–0.7 full-path per second
        const blobSize = Math.max(7, Math.min(16, 5 + pct * 0.3))
        const blobColor = cachedColor("#ff1744")
        const glowColor = cachedColor("#ff5252")

        for (let b = 0; b < blobCount; b++) {
          const blob = dataSource.entities.add({
            id: `traf-blob-${idx}-${b}`,
            position: arcPositions[0],
            point: {
              pixelSize: blobSize,
              color: blobColor.withAlpha(0.9),
              outlineColor: glowColor.withAlpha(0.4),
              outlineWidth: 3,
              disableDepthTestDistance: Number.POSITIVE_INFINITY,
              scaleByDistance: new Cesium.NearFarScalar(5e5, 1.2, 1e7, 0.4),
            },
          })
          this._trafficEntities.push(blob)
          // Store animation metadata on the entity for the RAF loop
          blob._blobArc = arcPositions
          blob._blobPhase = b / blobCount
          blob._blobSpeed = speed
        }
      }

      // Label at midpoint of arc
      const midPos = arcPositions[Math.floor(SEGS / 2)]
      const label = dataSource.entities.add({
        id: `traf-lbl-${idx}`,
        position: midPos,
        label: {
          text: `${p.origin} → ${p.target}  ${pct.toFixed(1)}%`,
          font: "11px JetBrains Mono, monospace",
          fillColor: cachedColor("#ff8a80"),
          outlineColor: Cesium.Color.BLACK,
          outlineWidth: 4,
          style: Cesium.LabelStyle.FILL_AND_OUTLINE,
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: new Cesium.Cartesian2(0, -6),
          scaleByDistance: new Cesium.NearFarScalar(5e5, 1, 1.2e7, 0.4),
          translucencyByDistance: new Cesium.NearFarScalar(5e5, 1.0, 1.5e7, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      this._trafficEntities.push(label)
    })
    dataSource.entities.resumeEvents(); this._requestRender()

    // Blob animation is handled by the consolidated animate() loop
  }

  // Blob animation is now handled by the consolidated animate() loop

  GlobeController.prototype._clearTrafficEntities = function() {
    this._stopTrafficBlobAnim()
    const ds = this._ds["traffic"]
    if (ds) {
      ds.entities.suspendEvents()
      this._trafficEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents(); this._requestRender()
    }
    this._trafficEntities = []
    this._attackedCountries = null
    this._threatsActive = false
    this._clearCableAttackHighlights()
    if (this._syncRightPanels) this._syncRightPanels()
  }

  GlobeController.prototype._stopTrafficBlobAnim = function() {
    if (this._trafficBlobRaf) {
      cancelAnimationFrame(this._trafficBlobRaf)
      this._trafficBlobRaf = null
    }
  }

  GlobeController.prototype._removeTrafficBlobEntities = function() {
    const ds = this._ds["traffic"]
    if (!ds) return
    const kept = []
    ds.entities.suspendEvents()
    for (const e of this._trafficEntities) {
      if (e._blobArc) {
        ds.entities.remove(e)
      } else {
        kept.push(e)
      }
    }
    ds.entities.resumeEvents(); this._requestRender()
    this._trafficEntities = kept
  }

  GlobeController.prototype.showTrafficDetail = function(code) {
    if (!this._trafficData) return
    const t = this._trafficData.traffic?.find(x => x.code === code)
    if (!t) return

    const pairs = this._trafficData.attack_pairs || []
    const inbound = pairs.filter(p => p.target === code)
    const outbound = pairs.filter(p => p.origin === code)

    let attackHtml = ""
    if (inbound.length > 0) {
      attackHtml += `<div style="margin-top:8px;font:500 9px var(--gt-mono);color:#f44336;letter-spacing:1px;text-transform:uppercase;">Attacks targeting</div>`
      attackHtml += inbound.map(p => `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">${this._escapeHtml(p.origin_name)} → ${p.pct?.toFixed(1)}%</div>`).join("")
    }
    if (outbound.length > 0) {
      attackHtml += `<div style="margin-top:8px;font:500 9px var(--gt-mono);color:#ff9800;letter-spacing:1px;text-transform:uppercase;">Attacks originating</div>`
      attackHtml += outbound.map(p => `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">→ ${this._escapeHtml(p.target_name)} ${p.pct?.toFixed(1)}%</div>`).join("")
    }

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:#69f0ae;">
        <i class="fa-solid fa-globe" style="margin-right:6px;"></i>Internet Traffic
      </div>
      <div class="detail-country">${this._escapeHtml(t.name || t.code)}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Traffic Share</span>
          <span class="detail-value" style="color:#69f0ae;">${t.traffic?.toFixed(2)}%</span>
        </div>
        ${t.attack_target > 0 ? `<div class="detail-field">
          <span class="detail-label">Attack Target</span>
          <span class="detail-value" style="color:#f44336;">${t.attack_target?.toFixed(2)}%</span>
        </div>` : ""}
        ${t.attack_origin > 0 ? `<div class="detail-field">
          <span class="detail-label">Attack Origin</span>
          <span class="detail-value" style="color:#ff9800;">${t.attack_origin?.toFixed(2)}%</span>
        </div>` : ""}
      </div>
      ${attackHtml}
      ${this._trafficData.recorded_at ? `<div style="margin-top:8px;font:400 9px var(--gt-mono);color:var(--gt-text-dim);">Updated: ${new Date(this._trafficData.recorded_at).toLocaleString()}</div>` : ""}
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: Netscout / Arbor Networks</div>
    `
    this.detailPanelTarget.style.display = ""
  }
}
