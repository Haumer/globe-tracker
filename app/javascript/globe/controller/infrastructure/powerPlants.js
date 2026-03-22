import { getDataSource, createPowerPlantIcon, LABEL_DEFAULTS } from "../../utils"

export function applyPowerPlantsMethods(GlobeController) {
  GlobeController.prototype.getPowerPlantsDataSource = function() { return getDataSource(this.viewer, this._ds, "power-plants") }

  GlobeController.prototype.togglePowerPlants = function() {
    this.powerPlantsVisible = this.hasPowerPlantsToggleTarget && this.powerPlantsToggleTarget.checked
    if (this.powerPlantsVisible) {
      this._ensurePowerPlantData().then(() => { this.renderPowerPlants(); this._updateThreatsPanel() })
      if (!this._ppCameraCb) {
        this._ppCameraCb = () => { if (this.powerPlantsVisible) this.renderPowerPlants() }
        this.viewer.camera.moveEnd.addEventListener(this._ppCameraCb)
      }
    } else {
      this._clearPowerPlantEntities()
      if (this._ppCameraCb) { this.viewer.camera.moveEnd.removeEventListener(this._ppCameraCb); this._ppCameraCb = null }
      if (this._syncRightPanels) this._syncRightPanels()
    }
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._ensurePowerPlantData = async function() {
    if (this._powerPlantAll) return // already loaded
    this._toast("Loading power plants...")
    try {
      const resp = await fetch("/api/power_plants")
      if (!resp.ok) return
      const raw = await resp.json()
      // API returns arrays: [id, lat, lng, fuel, capacity, name, country_code]
      this._powerPlantAll = raw.map(r => ({
        id: r[0], lat: r[1], lng: r[2], fuel: r[3],
        capacity: r[4], name: r[5], country: r[6],
      }))
      this._markFresh("powerPlants")
      this._toastHide()
    } catch (e) {
      console.error("Failed to fetch power plants:", e)
    }
  }

  GlobeController.prototype.renderPowerPlants = function() {
    if (!this._powerPlantAll) return

    const Cesium = window.Cesium
    const dataSource = this.getPowerPlantsDataSource()
    const bounds = this.getViewportBounds()

    const fuelColors = {
      Coal: "#616161", Gas: "#ff9800", Oil: "#795548", Nuclear: "#fdd835",
      Hydro: "#42a5f5", Solar: "#ffca28", Wind: "#80cbc4", Biomass: "#8bc34a",
      Geothermal: "#e64a19", Waste: "#9e9e9e", Petcoke: "#424242",
      Cogeneration: "#ab47bc", Storage: "#00bcd4", Other: "#78909c",
    }

    // Filter to viewport, already sorted by capacity desc from API
    let visible = this._powerPlantAll
    if (bounds) {
      visible = visible.filter(p =>
        p.lat >= bounds.lamin && p.lat <= bounds.lamax &&
        p.lng >= bounds.lomin && p.lng <= bounds.lomax
      )
    }
    if (this.hasActiveFilter()) {
      visible = visible.filter(p => this.pointPassesFilter(p.lat, p.lng))
    }
    // Cap at 1500 entities for performance (largest first)
    visible = visible.slice(0, 1500)

    // Build set of IDs we want visible
    const wantIds = new Set(visible.map(p => `pp-${p.id}`))

    // Single atomic update — remove stale + add new within one suspend
    dataSource.entities.suspendEvents()

    // Remove entities no longer in viewport
    const keep = []
    for (const e of this._powerPlantEntities) {
      if (e.id?.startsWith("pp-atk-") || !wantIds.has(e.id)) {
        dataSource.entities.remove(e)
      } else {
        wantIds.delete(e.id) // already exists, don't re-add
        keep.push(e)
      }
    }
    this._powerPlantEntities = keep

    // Add only new entities
    visible.forEach(p => {
      if (!wantIds.has(`pp-${p.id}`)) return // already on screen
      const color = fuelColors[p.fuel] || "#78909c"
      const cesiumColor = Cesium.Color.fromCssColorString(color)
      const cap = p.capacity || 1
      const scale = Math.min(0.6 + Math.sqrt(cap) * 0.03, 1.8)
      const icon = createPowerPlantIcon(p.fuel, color)

      const entity = dataSource.entities.add({
        id: `pp-${p.id}`,
        position: Cesium.Cartesian3.fromDegrees(p.lng, p.lat, 50),
        billboard: {
          image: icon,
          scale,
          scaleByDistance: new Cesium.NearFarScalar(1e5, 1.2, 8e6, 0.3),
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          verticalOrigin: Cesium.VerticalOrigin.CENTER,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: p.name,
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
      this._powerPlantEntities.push(entity)

      // Cross-layer: attack warning ring if this country is under cyber attack
      if (this.trafficVisible && this._attackedCountries?.has(p.country)) {
        const atkRing = dataSource.entities.add({
          id: `pp-atk-${p.id}`,
          position: Cesium.Cartesian3.fromDegrees(p.lng, p.lat, 0),
          ellipse: {
            semiMinorAxis: 20000 + (p.capacity || 1) * 5,
            semiMajorAxis: 20000 + (p.capacity || 1) * 5,
            material: Cesium.Color.RED.withAlpha(0.06),
            outline: true,
            outlineColor: Cesium.Color.RED.withAlpha(0.35),
            outlineWidth: 1,
            height: 0,
            heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
            classificationType: Cesium.ClassificationType.BOTH,
          },
        })
        this._powerPlantEntities.push(atkRing)
      }
    })
    dataSource.entities.resumeEvents(); this._requestRender()
    this._powerPlantData = visible // for click lookups
  }

  GlobeController.prototype._clearPowerPlantEntities = function() {
    const ds = this._ds["power-plants"]
    if (ds) {
      ds.entities.suspendEvents()
      this._powerPlantEntities.forEach(e => ds.entities.remove(e))
      ds.entities.resumeEvents(); this._requestRender()
    }
    this._powerPlantEntities = []
  }

  GlobeController.prototype._updateThreatsPanel = function() {
    if (!this.hasThreatsContentTarget) return
    const attacked = this._attackedCountries
    if (!attacked?.size || !this._powerPlantAll?.length) {
      if (this._syncRightPanels) this._syncRightPanels()
      return
    }

    // Find all power plants in attacked countries
    const threatened = this._powerPlantAll
      .filter(p => attacked.has(p.country))
      .sort((a, b) => (b.capacity || 0) - (a.capacity || 0))
      .slice(0, 200)

    if (!threatened.length) {
      this._threatsActive = false
      if (this._syncRightPanels) this._syncRightPanels()
      return
    }

    this._threatsActive = true
    if (this._showRightPanel) this._showRightPanel("threats")
    if (this.hasThreatsCountTarget) {
      this.threatsCountTarget.textContent = `${threatened.length} target${threatened.length !== 1 ? "s" : ""}`
    }

    const pairs = this._trafficData?.attack_pairs || []
    const fuelColors = {
      Coal: "#616161", Gas: "#ff9800", Oil: "#795548", Nuclear: "#fdd835",
      Hydro: "#42a5f5", Solar: "#ffca28", Wind: "#80cbc4", Biomass: "#8bc34a",
      Geothermal: "#e64a19", Other: "#78909c",
    }

    // Group by country
    const byCountry = {}
    threatened.forEach(p => {
      if (!byCountry[p.country]) byCountry[p.country] = []
      byCountry[p.country].push(p)
    })

    const html = Object.entries(byCountry).map(([country, plants]) => {
      const countryAttacks = pairs.filter(p => p.target === country)
      const totalPct = countryAttacks.reduce((s, p) => s + (p.pct || 0), 0).toFixed(1)
      const origins = countryAttacks.map(p => p.origin_name || p.origin).join(", ")

      const plantRows = plants.slice(0, 15).map(p => {
        const color = fuelColors[p.fuel] || "#78909c"
        return `<div class="th-plant" data-action="click->globe#focusThreat" data-lat="${p.lat}" data-lng="${p.lng}" data-pp-id="${p.id}">
          <span class="th-fuel" style="color:${color}"><i class="fa-solid fa-bolt"></i></span>
          <span class="th-name">${this._escapeHtml(p.name)}</span>
          <span class="th-cap">${p.capacity ? p.capacity.toLocaleString() + " MW" : ""}</span>
          <span class="th-type" style="background:${color}20;color:${color}">${p.fuel}</span>
        </div>`
      }).join("")

      const moreCount = plants.length > 15 ? `<div class="th-more">+ ${plants.length - 15} more</div>` : ""

      return `<div class="th-country">
        <div class="th-country-header">
          <span class="th-country-name">${this._escapeHtml(country)}</span>
          <span class="th-attack-pct">${totalPct}% DDoS</span>
        </div>
        <div class="th-origins">from ${this._escapeHtml(origins)}</div>
        <div class="th-plants">${plantRows}${moreCount}</div>
      </div>`
    }).join("")

    this.threatsContentTarget.innerHTML = html
  }

  GlobeController.prototype.closeThreats = function() {
    this._threatsActive = false
    if (this._syncRightPanels) this._syncRightPanels()
  }

  GlobeController.prototype.focusThreat = function(event) {
    const lat = parseFloat(event.currentTarget.dataset.lat)
    const lng = parseFloat(event.currentTarget.dataset.lng)
    if (isNaN(lat) || isNaN(lng)) return
    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, 500000),
      duration: 1.0,
    })
    // Show detail if we have the plant data
    const ppId = event.currentTarget.dataset.ppId
    const pp = this._powerPlantData?.find(p => String(p.id) === ppId) ||
               this._powerPlantAll?.find(p => String(p.id) === ppId)
    if (pp) this.showPowerPlantDetail(pp)
  }

  GlobeController.prototype.showPowerPlantDetail = function(pp) {
    const fuelColors = {
      Coal: "#616161", Gas: "#ff9800", Oil: "#795548", Nuclear: "#fdd835",
      Hydro: "#42a5f5", Solar: "#ffca28", Wind: "#80cbc4", Biomass: "#8bc34a",
      Geothermal: "#e64a19", Other: "#78909c",
    }
    const color = fuelColors[pp.fuel] || "#78909c"

    // Compute national capacity share
    let shareHtml = ""
    if (pp.country && pp.capacity && this._powerPlantAll) {
      const nationalMw = this._powerPlantAll
        .filter(p => p.country === pp.country)
        .reduce((sum, p) => sum + (p.capacity || 0), 0)
      if (nationalMw > 0) {
        const pct = (pp.capacity / nationalMw * 100).toFixed(1)
        shareHtml = `
        <div class="detail-field">
          <span class="detail-label">National Share</span>
          <span class="detail-value">${pct}% of ${nationalMw.toLocaleString()} MW</span>
        </div>`
      }
    }

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${color};">
        <i class="fa-solid fa-plug" style="margin-right:6px;"></i>${this._escapeHtml(pp.name)}
      </div>
      <div class="detail-country">${this._escapeHtml(pp.country || "Unknown")}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Fuel</span>
          <span class="detail-value" style="color:${color};">${pp.fuel || "Unknown"}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Capacity</span>
          <span class="detail-value">${pp.capacity ? pp.capacity.toLocaleString() + " MW" : "—"}</span>
        </div>
        ${shareHtml}
      </div>
      ${this.trafficVisible && this._attackedCountries?.has(pp.country) ? `
        <div style="margin-top:10px;padding:6px 8px;background:rgba(244,67,54,0.1);border:1px solid rgba(244,67,54,0.3);border-radius:4px;">
          <div style="font:600 9px var(--gt-mono);color:#f44336;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">⚠ CYBER ATTACK TARGET</div>
          ${(this._trafficData?.attack_pairs || []).filter(p => p.target === pp.country).map(p =>
            `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">${this._escapeHtml(p.origin_name)} → ${p.pct?.toFixed(1)}%</div>`
          ).join("")}
        </div>
      ` : ""}
      ${this._connectionsPlaceholder()}
    `
    this.detailPanelTarget.style.display = ""
    this._fetchConnections("power_plant", pp.lat, pp.lng, { country_code: pp.country })

  }
}
