import { findCountryAtPoint } from "../../utils"
import {
  renderConflictPulseDetailHtml,
  renderHexDetailHtml,
  renderSituationPanelHtml,
  renderStrategicSituationDetailHtml,
  renderStrikeArcDetailHtml,
} from "./conflict_pulse_presenters"

export function applyConflictPulseInteractionMethods(GlobeController) {
  GlobeController.prototype._flyToConflictPulse = function(zone) {
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat, 1500000),
      duration: 1.5,
    })
    this.showConflictPulseDetail(zone)
  }

  GlobeController.prototype._flyToStrategicSituation = function(item) {
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(item.lng, item.lat, 1400000),
      duration: 1.5,
    })
    this.showStrategicSituationDetail(item)
  }

  GlobeController.prototype.showConflictPulseDetail = function(zone) {
    if (this._buildTheaterContext && this._setSelectedContext) {
      this._setSelectedContext(this._buildTheaterContext(zone))
    }
    this.detailContentTarget.innerHTML = renderConflictPulseDetailHtml(this, zone)
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("conflict", zone.lat, zone.lng)
  }

  GlobeController.prototype.showStrategicSituationDetail = function(item) {
    if (item?.kind && item?.node_id && this._focusContextNode) {
      this._focusContextNode(
        { kind: item.kind, id: item.node_id },
        {
          title: item.name,
          summary: item.pressure_summary || [item.theater, `${item.direct_cluster_count || 0} corroborated clusters`].filter(Boolean).join(" · "),
        }
      )
    }
    this.detailContentTarget.innerHTML = renderStrategicSituationDetailHtml(this, item)
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype.showStrategicSituationFromList = function(event) {
    const id = event.currentTarget.dataset.id
    const item = (this._strategicSituationData || []).find(entry =>
      `${entry.id || entry.node_id || entry.name}` === `${id}`
    )
    if (!item) return
    this._flyToStrategicSituation(item)
  }

  GlobeController.prototype.revealPulseConnections = function(event) {
    const btn = event.currentTarget

    if (btn.dataset.revealed === "true") {
      (this._revealedLayers || []).forEach(toggle => this._disableLayer(toggle))
      this._revealedLayers = []
      if (this._revealedCountry) {
        this.selectedCountries.delete(this._revealedCountry)
        this._updateSelectedCountriesBbox()
        this.updateBorderColors()
        this._updateDeselectBtn()
        this._revealedCountry = null
      }
      btn.dataset.revealed = "false"
      btn.innerHTML = `<i class="fa-solid fa-eye" style="margin-right:4px;"></i>Explore This Area`
      btn.style.background = "rgba(244,67,54,0.2)"
      btn.style.borderColor = "rgba(244,67,54,0.4)"
      btn.style.color = "#f44336"
      this._toast("Layers hidden", "success")
      return
    }

    const lat = parseFloat(btn.dataset.lat)
    const lng = parseFloat(btn.dataset.lng)
    let signals = {}
    try {
      signals = JSON.parse(btn.dataset.signals)
    } catch {}

    const Cesium = window.Cesium

    btn.innerHTML = `<i class="fa-solid fa-spinner fa-spin" style="margin-right:4px;"></i>Flying to area...`
    btn.disabled = true

    this._revealedLayers = []
    this._revealedCountry = null

    if (!this.bordersLoaded && this.loadBorders) {
      this.loadBorders()
    }

    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, 400000),
      duration: 1.5,
      complete: () => {
        if (this._countryFeatures?.length) {
          const countryName = findCountryAtPoint(this._countryFeatures, lat, lng)
          if (countryName && !this.selectedCountries.has(countryName)) {
            if (!this.bordersVisible && this.hasBordersToggleTarget) {
              this.bordersToggleTarget.checked = true
              this.toggleBorders()
              this._revealedLayers.push("bordersToggle")
            }
            this.toggleCountrySelection(countryName)
            this._revealedCountry = countryName
          }
        }

        const enabled = []

        if (signals.gps_jamming) {
          this._enableLayer("gpsJammingToggle")
          this._revealedLayers.push("gpsJammingToggle")
          enabled.push("GPS jamming")
        }
        if (signals.internet_outage) {
          this._enableLayer("outagesToggle")
          this._revealedLayers.push("outagesToggle")
          enabled.push("internet outages")
        }

        this._enableLayer("conflictsToggle")
        this._revealedLayers.push("conflictsToggle")
        enabled.push("conflicts")

        this._enableLayer("newsToggle")
        this._revealedLayers.push("newsToggle")
        enabled.push("news")

        btn.innerHTML = `<i class="fa-solid fa-eye-slash" style="margin-right:4px;"></i>Hide Layers`
        btn.style.background = "rgba(76,175,80,0.2)"
        btn.style.borderColor = "rgba(76,175,80,0.4)"
        btn.style.color = "#4caf50"
        btn.disabled = false
        btn.dataset.revealed = "true"

        const countryLabel = this._revealedCountry ? ` (${this._revealedCountry})` : ""
        this._toast(`Exploring${countryLabel}`, "success")
      },
    })
  }

  GlobeController.prototype.showStrikeArcDetail = function(arc) {
    this.detailContentTarget.innerHTML = renderStrikeArcDetailHtml(this, arc)
    this.detailPanelTarget.style.display = ""
  }

  GlobeController.prototype._enableLayer = function(toggleName) {
    const targetName = `${toggleName}Target`
    const hasTarget = `has${toggleName[0].toUpperCase()}${toggleName.slice(1)}Target`
    if (this[hasTarget]) {
      const toggle = this[targetName]
      if (toggle && !toggle.checked) {
        toggle.checked = true
        toggle.dispatchEvent(new Event("change"))
      }
    }
  }

  GlobeController.prototype._disableLayer = function(toggleName) {
    const targetName = `${toggleName}Target`
    const hasTarget = `has${toggleName[0].toUpperCase()}${toggleName.slice(1)}Target`
    if (this[hasTarget]) {
      const toggle = this[targetName]
      if (toggle && toggle.checked) {
        toggle.checked = false
        toggle.dispatchEvent(new Event("change"))
      }
    }
  }

  GlobeController.prototype.pulseSignalClick = function(event) {
    const signal = event.currentTarget.dataset.signal
    const lat = parseFloat(event.currentTarget.dataset.lat)
    const lng = parseFloat(event.currentTarget.dataset.lng)
    if (isNaN(lat) || isNaN(lng)) return

    const Cesium = window.Cesium

    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, 500000),
      duration: 1.0,
      complete: () => {
        const layerToggles = {
          flights: "flightsToggle",
          gpsJamming: "gpsJammingToggle",
          fires: "firesToggle",
          conflicts: "conflictsToggle",
        }
        const toggle = layerToggles[signal]
        if (toggle) this._enableLayer(toggle)
      },
    })
  }

  GlobeController.prototype._findHexAtPosition = function(lat, lng) {
    if (!this._hexCellData?.length) return null
    for (const cell of this._hexCellData) {
      if (!cell.vertices || cell.vertices.length !== 6) continue
      if (cell.intensity < 0.01) continue
      const lats = cell.vertices.map(v => v[0])
      const lngs = cell.vertices.map(v => v[1])
      if (lat < Math.min(...lats) || lat > Math.max(...lats)) continue
      if (lng < Math.min(...lngs) || lng > Math.max(...lngs)) continue
      let inside = false
      for (let i = 0, j = 5; i < 6; j = i++) {
        const yi = cell.vertices[i][0], xi = cell.vertices[i][1]
        const yj = cell.vertices[j][0], xj = cell.vertices[j][1]
        if (((yi > lat) !== (yj > lat)) && (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
          inside = !inside
        }
      }
      if (inside) return cell
    }
    return null
  }

  GlobeController.prototype.toggleStrikeArcs = function() {
    this._strikeArcsVisible = this.hasStrikeArcsToggleTarget && this.strikeArcsToggleTarget.checked
    if (this.situationsVisible) this._renderConflictPulse()
    this._savePrefs()
  }

  GlobeController.prototype.toggleHexTheater = function() {
    this._hexTheaterVisible = this.hasHexTheaterToggleTarget && this.hexTheaterToggleTarget.checked
    if (this.situationsVisible) this._renderConflictPulse()
    this._savePrefs()
  }

  GlobeController.prototype._timeAgo = function(date) {
    const seconds = Math.floor((Date.now() - date.getTime()) / 1000)
    if (seconds < 60) return "just now"
    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return `${minutes}m ago`
    const hours = Math.floor(minutes / 60)
    if (hours < 24) return `${hours}h ago`
    const days = Math.floor(hours / 24)
    return `${days}d ago`
  }

  GlobeController.prototype._showHexDetail = function(cell) {
    const situation = cell.situation || "Unlinked area"
    const theater = cell.theater || ""
    const zone = cell.zone_key
      ? this._conflictPulseData?.find(z => z.cell_key === cell.zone_key)
      : null

    let localName = ""
    if (this._countryFeatures) {
      try {
        const country = findCountryAtPoint(this._countryFeatures, cell.lat, cell.lng)
        if (country) localName = country
      } catch (e) {}
    }
    if (!localName) {
      localName = `${cell.lat.toFixed(1)}°, ${cell.lng.toFixed(1)}°`
    }

    let headlinesHtml = ""
    if (zone) {
      const articles = zone.top_articles || []
      const headlines = articles.length > 0
        ? articles.slice(0, 3).map(a => {
            const timeAgo = a.published_at ? this._timeAgo(new Date(a.published_at)) : ""
            return `<a href="${this._safeUrl(a.url)}" target="_blank" rel="noopener" style="display:block;text-decoration:none;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
              <div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.3;">${this._escapeHtml(a.title?.substring(0, 70))}</div>
              <div style="font:400 9px var(--gt-mono,monospace);color:#666;margin-top:2px;">${this._escapeHtml(a.publisher || a.source || "")} · ${timeAgo}</div>
            </a>`
          }).join("")
        : (zone.top_headlines || []).slice(0, 3).map(h =>
            `<div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.4;padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.05);">${this._escapeHtml(h?.substring(0, 70))}</div>`
          ).join("")
      if (headlines) {
        headlinesHtml = `<div style="margin-top:8px;">
          <div style="font:600 9px var(--gt-mono);text-transform:uppercase;letter-spacing:1px;color:rgba(255,152,0,0.6);margin-bottom:6px;">Related Headlines</div>
          ${headlines}
        </div>`
      }
    }

    const connectionParts = [localName]
    if (situation && situation !== localName && situation !== "Unlinked area") connectionParts.push(situation)
    if (theater) connectionParts.push(theater)
    const connectionHtml = connectionParts.length > 1
      ? `<div style="font:400 10px var(--gt-mono,monospace);color:rgba(255,152,0,0.5);margin:4px 0 6px;letter-spacing:0.3px;">${connectionParts.map(p => this._escapeHtml(p)).join(" → ")}</div>`
      : ""

    this.detailContentTarget.innerHTML = renderHexDetailHtml(this, cell, zone, localName, connectionHtml, headlinesHtml)
    this.detailPanelTarget.style.display = ""

    if (theater) {
      this._highlightedTheater = null
      this.highlightTheater({ currentTarget: { dataset: { theater, skipContext: "true" } } })
      this._rippleFromHex(cell)
    }
  }

  GlobeController.prototype._rippleFromHex = function(clickedCell) {
    if (!this._hexCellData?.length) return
    const Cesium = window.Cesium
    const ds = this._ds["conflictPulse"]
    if (!ds) return

    if (this._rippleFrame) {
      cancelAnimationFrame(this._rippleFrame)
      this._rippleFrame = null
    }

    const siblings = []
    let maxDist = 0
    this._hexCellData.forEach((h, i) => {
      if (h.theater !== clickedCell.theater) return
      const d = Math.sqrt((h.lat - clickedCell.lat) ** 2 + (h.lng - clickedCell.lng) ** 2)
      maxDist = Math.max(maxDist, d)
      siblings.push({ idx: i, dist: d })
    })
    if (!siblings.length) return

    const speed = maxDist / 1.2
    const waveFront = 4.0
    const startTime = performance.now()
    const totalDuration = 2000

    const highlightColor = Cesium.Color.fromCssColorString("#ff6d00")
    const dimColor = Cesium.Color.fromCssColorString("#ff6d00")

    const animate = () => {
      const elapsed = (performance.now() - startTime) / 1000
      const waveDist = elapsed * speed

      siblings.forEach(s => {
        const entity = ds.entities.getById(`cpulse-hex-${s.idx}`)
        if (!entity?.polygon) return

        const delta = waveDist - s.dist

        if (delta < 0) {
          entity.polygon.material = dimColor.withAlpha(0.08)
          entity.polygon.outlineColor = dimColor.withAlpha(0.15)
        } else if (delta < waveFront) {
          const bandT = delta / waveFront
          const flash = 1.0 - bandT * 0.5
          entity.polygon.material = highlightColor.withAlpha(0.3 + flash * 0.5)
          entity.polygon.outlineColor = highlightColor.withAlpha(0.5 + flash * 0.5)
        } else {
          entity.polygon.material = highlightColor.withAlpha(0.5)
          entity.polygon.outlineColor = highlightColor.withAlpha(0.85)
        }
      })

      this._requestRender()

      if (performance.now() - startTime < totalDuration) {
        this._rippleFrame = requestAnimationFrame(animate)
      } else {
        this._rippleFrame = null
      }
    }

    this._rippleFrame = requestAnimationFrame(animate)
  }

  GlobeController.prototype.flyToConflictZone = function(event) {
    const key = event.currentTarget.dataset.zoneKey
    const zone = this._conflictPulseData?.find(z => z.cell_key === key)
    if (!zone) return
    this._flyToConflictPulse(zone)
    if (zone.theater) {
      this.highlightTheater({ currentTarget: { dataset: { theater: zone.theater, skipContext: "true" } } })
    }
  }

  GlobeController.prototype.highlightTheater = function(event) {
    const theater = event.currentTarget.dataset.theater
    const skipContext = event.currentTarget.dataset.skipContext === "true"
    if (!theater || this._highlightedTheater === theater) {
      this._highlightedTheater = null
      if (this._hexLayerAutoEnabled) {
        this._hexTheaterVisible = false
        this._strikeArcsVisible = false
        if (this.hasHexTheaterToggleTarget) this.hexTheaterToggleTarget.checked = false
        if (this.hasStrikeArcsToggleTarget) this.strikeArcsToggleTarget.checked = false
        this._hexLayerAutoEnabled = false
      }
      this._renderConflictPulse()
      return
    }
    this._highlightedTheater = theater
    if (!skipContext && this._setTheaterSelectedContext) this._setTheaterSelectedContext(theater)

    if (!this._hexTheaterVisible) {
      this._hexTheaterVisible = true
      this._strikeArcsVisible = true
      if (this.hasHexTheaterToggleTarget) this.hexTheaterToggleTarget.checked = true
      if (this.hasStrikeArcsToggleTarget) this.strikeArcsToggleTarget.checked = true
      this._hexLayerAutoEnabled = true
      this._renderConflictPulse()
    }

    const Cesium = window.Cesium
    const ds = this._ds["conflictPulse"]
    if (!ds) return

    this._conflictPulseEntities.forEach(entity => {
      if (!entity.polygon) return
      const props = entity.properties
      const entityTheater = props?.theater?.getValue()
      const isMatch = entityTheater === theater

      entity.polygon.material = Cesium.Color.fromCssColorString(isMatch ? "#ff6d00" : "#444").withAlpha(isMatch ? 0.6 : 0.03)
      entity.polygon.outlineColor = Cesium.Color.fromCssColorString(isMatch ? "#ff6d00" : "#333").withAlpha(isMatch ? 0.9 : 0.05)
    })

    this._conflictPulseEntities.forEach(entity => {
      if (!entity.point && !entity.label && !entity.ellipse) return
      const entityId = `${entity.id || ""}`
      if (!entityId.startsWith("cpulse-")) return
      if (entityId.startsWith("cpulse-strat-") || entityId.startsWith("cpulse-arc-") || entityId.startsWith("cpulse-hex-")) return
      const zoneKey = decodeURIComponent(entityId.replace(/^cpulse-(?:lbl-|ring-|core-|pulse-)?/, ""))
      const zone = this._conflictPulseData?.find(item => `${item.cell_key}` === zoneKey)
      if (!zone) return
      const isMatch = zone.theater === theater
      if (entity.point) {
        entity.point.color = entity.point.color?.getValue?.(Cesium.JulianDate.now())?.withAlpha(isMatch ? 1.0 : 0.15)
      }
      if (entity.label) {
        entity.label.fillColor = Cesium.Color.WHITE.withAlpha(isMatch ? 1.0 : 0.1)
      }
    })

    this._requestRender()
  }

  GlobeController.prototype._renderSituationPanel = function() {
    const list = this.hasSitListTarget ? this.sitListTarget : null
    const countEl = this.hasSitCountTarget ? this.sitCountTarget : null
    if (!list) return
    if (!this.situationsVisible) {
      if (countEl) countEl.textContent = ""
      list.innerHTML = ""
      return
    }

    const zones = this._conflictPulseZones || []
    const strategic = this._strategicSituationData || []
    const snapshotStatus = this._conflictPulseSnapshotStatus || "pending"
    if (!this._sitExpanded) this._sitExpanded = {}
    const rendered = renderSituationPanelHtml(this, zones, strategic, snapshotStatus, this._sitExpanded)
    if (countEl) {
      const base = `${rendered.countSummary.zones} theater${rendered.countSummary.zones !== 1 ? "s" : ""}`
      const strategicSuffix = rendered.countSummary.strategic ? ` · ${rendered.countSummary.strategic} strategic` : ""
      const suffix = rendered.countSummary.snapshotStatus === "ready" ? "" : ` · ${this._statusLabel(rendered.countSummary.snapshotStatus, "snapshot")}`
      countEl.textContent = `${base}${strategicSuffix}${suffix}`
    }
    list.innerHTML = rendered.html
  }

  GlobeController.prototype.toggleSitTheater = function(event) {
    const header = event.currentTarget
    const theater = header.closest(".sit-theater")
    if (!theater) return
    const body = theater.querySelector(".sit-theater-body")
    const arrow = header.querySelector(".sit-theater-arrow")
    if (!body) return
    const hidden = body.style.display === "none"
    body.style.display = hidden ? "" : "none"
    if (arrow) arrow.textContent = hidden ? "▾" : "▸"
    theater.classList.toggle("sit-theater--collapsed", !hidden)
  }

  GlobeController.prototype.toggleSitZone = function(event) {
    const key = event.currentTarget.dataset.zoneKey
    if (!this._sitExpanded) this._sitExpanded = {}
    const current = this._sitExpanded[key] || "collapsed"
    const next = current === "collapsed" ? "summary" : current === "summary" ? "expanded" : "collapsed"
    this._sitExpanded[key] = next
    this._renderSituationPanel()
  }

  GlobeController.prototype.exploreSituation = function(event) {
    const key = event.currentTarget.dataset.zoneKey
    const zone = this._conflictPulseZones?.find(z => z.cell_key === key)
    if (!zone) return

    const signals = zone.cross_layer_signals || {}
    const Cesium = window.Cesium

    this._savedExploreCamera = {
      position: Cesium.Cartesian3.clone(this.viewer.camera.position),
      heading: this.viewer.camera.heading,
      pitch: this.viewer.camera.pitch,
      roll: this.viewer.camera.roll,
    }

    this._exploreRevealedLayers = []

    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat, 800000),
      duration: 1.5,
      complete: () => {
        const layerMap = {
          military_flights: "flightsToggle",
          gps_jamming: "gpsJammingToggle",
          fire_hotspots: "firesToggle",
          known_conflict_zone: "conflictsToggle",
          internet_outage: "internetOutagesToggle",
        }
        for (const [signal, toggle] of Object.entries(layerMap)) {
          if (signals[signal]) {
            this._enableLayer(toggle)
            this._exploreRevealedLayers.push(toggle)
          }
        }
        this._toast(`Exploring ${zone.situation_name || "situation"}`, "success")
      },
    })
  }
}
