export function applySatDetailMethods(GlobeController) {
  GlobeController.prototype.showSatelliteDetail = function(satData) {
    this._focusedSelection = { type: "sat", id: satData.norad_id }
    this._renderSelectionTray()
    const sat = window.satellite
    const now = new Date()
    const satrec = sat.twoline2satrec(satData.tle_line1, satData.tle_line2)
    const posVel = sat.propagate(satrec, now)
    const gmst = sat.gstime(now)

    let altKm = "—"
    let speedKms = "—"
    if (posVel.position) {
      const posGd = sat.eciToGeodetic(posVel.position, gmst)
      altKm = Math.round(posGd.height).toLocaleString() + " km"
    }
    if (posVel.velocity) {
      const v = posVel.velocity
      const speed = Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
      speedKms = Math.round(speed * 10) / 10 + " km/s"
    }

    const operatorHtml = satData.operator ? `
        <div class="detail-field">
          <span class="detail-label">Operator</span>
          <span class="detail-value">${satData.operator}</span>
        </div>` : ""
    const missionHtml = satData.mission_type ? `
        <div class="detail-field">
          <span class="detail-label">Mission</span>
          <span class="detail-value">${satData.mission_type.replace(/_/g, " ")}</span>
        </div>` : ""

    // Enrichment fields — UCS for regular sats, orbital analysis for classified
    const isClassified = satData.category === "analyst"
    const enrichmentFields = [
      ["Country", satData.country_owner],
      ["Users", satData.users],
      ["Purpose", satData.purpose],
      ["Orbit", satData.orbit_class],
      ["Launched", satData.launch_date],
      ["Launch Site", satData.launch_site],
      ["Vehicle", satData.launch_vehicle],
      isClassified ? ["Co-orbital Group", satData.contractor] : ["Contractor", satData.contractor],
      ["Lifetime", satData.expected_lifetime ? satData.expected_lifetime + " yrs" : null],
    ].filter(([, v]) => v).map(([label, value]) => `
        <div class="detail-field">
          <span class="detail-label">${label}</span>
          <span class="detail-value">${this._escapeHtml(value)}</span>
        </div>`).join("")

    // Classified badge + orbital analysis callout
    const classifiedBanner = isClassified ? `
      <div class="classified-banner">
        <span class="classified-badge">CLASSIFIED</span>
        <span class="classified-label">Unacknowledged payload — orbital analysis</span>
      </div>` : ""

    const analysisCallout = isClassified && satData.detailed_purpose ? `
      <div class="orbital-analysis-callout">
        <div class="oac-icon"><i class="fa-solid fa-satellite-dish"></i></div>
        <div class="oac-text">${this._escapeHtml(satData.detailed_purpose)}</div>
      </div>` : ""

    const subtitlePurpose = !isClassified && satData.purpose
      ? '<div style="font:500 10px var(--gt-mono);color:var(--gt-text-dim);margin:-4px 0 8px;">' + this._escapeHtml(satData.detailed_purpose || satData.purpose) + '</div>'
      : ""

    const categoryLabel = isClassified ? "ANALYST" : satData.category.toUpperCase()
    const operatorSuffix = satData.country_owner ? " — " + satData.country_owner : (satData.operator ? " — " + satData.operator : "")

    this.detailContentTarget.innerHTML = `
      ${classifiedBanner}
      <div class="detail-callsign">${satData.name}</div>
      <div class="detail-country">${categoryLabel}${operatorSuffix}</div>
      ${subtitlePurpose}
      ${analysisCallout}
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">NORAD ID</span>
          <span class="detail-value">${satData.norad_id}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Altitude</span>
          <span class="detail-value">${altKm}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Speed</span>
          <span class="detail-value">${speedKms}</span>
        </div>
        ${operatorHtml}
        ${missionHtml}
        ${enrichmentFields}
      </div>
      ${this.selectedCountries.size > 0 ? `
      <button class="detail-track-btn ${this._satFootprintCountryMode ? 'tracking' : ''}"
              data-action="click->globe#toggleSatFootprintCountryMode">
        ${this._satFootprintCountryMode ? 'Show Radial Footprint' : 'Map to Selected Countries'}
      </button>` : ''}
      <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showGroundEvents" data-norad="${satData.norad_id}">
        <i class="fa-solid fa-crosshairs" style="margin-right:4px;"></i>Show Ground Events in Footprint
      </button>
      <button class="detail-track-btn" style="background:rgba(129,199,132,0.15);border-color:rgba(129,199,132,0.3);color:#81c784;" data-action="click->globe#predictSatPasses" data-sat-tle1="${this._escapeHtml(satData.tle_line1)}" data-sat-tle2="${this._escapeHtml(satData.tle_line2)}" data-sat-name="${this._escapeHtml(satData.name)}">
        <i class="fa-solid fa-binoculars" style="margin-right:4px;"></i>Predict Visible Passes
      </button>
      <div class="sat-passes-result" data-globe-sat-passes></div>
    `
    this.detailPanelTarget.style.display = ""

    // Show footprint for this satellite
    this.selectSatFootprint(satData.norad_id)
  }

  // ── Satellite Pass Predictions ──
  GlobeController.prototype.predictSatPasses = function(event) {
    const btn = event.currentTarget
    const tle1 = btn.dataset.satTle1
    const tle2 = btn.dataset.satTle2
    const satName = btn.dataset.satName
    const resultsEl = this.detailContentTarget.querySelector("[data-globe-sat-passes]")
    if (!resultsEl || !tle1 || !tle2) return

    // Get observer location from camera center
    const Cesium = window.Cesium
    const carto = this.viewer.camera.positionCartographic
    const obsLat = Cesium.Math.toDegrees(carto.latitude)
    const obsLng = Cesium.Math.toDegrees(carto.longitude)
    const obsAltKm = 0 // ground level

    resultsEl.innerHTML = '<div style="font:400 10px var(--gt-mono);color:#888;padding:6px 0;">Computing passes from camera center...</div>'

    try {
      const sat = window.satellite
      const satrec = sat.twoline2satrec(tle1, tle2)
      const observerGd = {
        longitude: sat.degreesToRadians(obsLng),
        latitude: sat.degreesToRadians(obsLat),
        height: obsAltKm,
      }

      const passes = []
      const now = new Date()
      const stepMs = 30 * 1000 // 30-second steps
      const horizon = 48 * 60 * 60 * 1000 // look ahead 48 hours
      let inPass = false
      let passStart = null
      let maxEl = 0

      for (let t = 0; t < horizon; t += stepMs) {
        const time = new Date(now.getTime() + t)
        const posVel = sat.propagate(satrec, time)
        if (!posVel.position) continue

        const gmst = sat.gstime(time)
        const posEcf = sat.eciToEcf(posVel.position, gmst)
        const lookAngles = sat.ecfToLookAngles(observerGd, posEcf)
        const elevDeg = sat.radiansToDegrees(lookAngles.elevation)

        if (elevDeg > 0) {
          if (!inPass) {
            inPass = true
            passStart = time
            maxEl = elevDeg
          } else {
            maxEl = Math.max(maxEl, elevDeg)
          }
        } else if (inPass) {
          // Pass ended
          passes.push({
            start: passStart,
            end: time,
            maxElevation: maxEl,
            duration: (time - passStart) / 1000,
          })
          inPass = false
          maxEl = 0
          if (passes.length >= 10) break
        }
      }

      if (passes.length === 0) {
        resultsEl.innerHTML = '<div style="font:400 10px var(--gt-mono);color:#888;padding:6px 0;">No visible passes in next 48 hours from this location.</div>'
        return
      }

      let html = `<div class="sat-passes-header">
        <i class="fa-solid fa-binoculars" style="color:#81c784;margin-right:4px;"></i>
        PASSES FROM ${obsLat.toFixed(1)}°, ${obsLng.toFixed(1)}°
      </div>`

      passes.forEach((pass, i) => {
        const startStr = pass.start.toISOString().slice(11, 16)
        const endStr = pass.end.toISOString().slice(11, 16)
        const dateStr = pass.start.toISOString().slice(5, 10)
        const durMin = Math.round(pass.duration / 60)
        const elStr = pass.maxElevation.toFixed(0)
        const quality = pass.maxElevation > 60 ? "excellent" : pass.maxElevation > 30 ? "good" : "low"

        // Time until pass
        const untilMs = pass.start - now
        let untilStr
        if (untilMs < 60000) untilStr = "NOW"
        else if (untilMs < 3600000) untilStr = `in ${Math.round(untilMs / 60000)}m`
        else untilStr = `in ${Math.round(untilMs / 3600000)}h`

        html += `<div class="sat-pass-row sat-pass--${quality}">
          <div class="sat-pass-time">${dateStr} ${startStr}–${endStr} UTC</div>
          <div class="sat-pass-meta">
            <span class="sat-pass-until">${untilStr}</span>
            <span class="sat-pass-dur">${durMin}min</span>
            <span class="sat-pass-el">${elStr}° max</span>
          </div>
        </div>`
      })

      resultsEl.innerHTML = html
    } catch (e) {
      console.warn("Pass prediction failed:", e)
      resultsEl.innerHTML = '<div style="font:400 10px var(--gt-mono);color:#f44336;padding:6px 0;">Pass prediction failed.</div>'
    }
  }
}
