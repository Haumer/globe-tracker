export function applyGeographyCaptureMethods(GlobeController) {
  GlobeController.prototype.toggleRecording = function() {
    if (this._mediaRecorder && this._mediaRecorder.state === "recording") this._stopRecording()
    else this._startRecording()
  }

  GlobeController.prototype._startRecording = function() {
    const canvas = this.viewer.scene.canvas
    const stream = canvas.captureStream(30)
    const mimeType = MediaRecorder.isTypeSupported("video/webm;codecs=vp9")
      ? "video/webm;codecs=vp9"
      : "video/webm;codecs=vp8"

    this._recordedChunks = []
    this._mediaRecorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: 8_000_000 })
    this._mediaRecorder.ondataavailable = event => {
      if (event.data.size > 0) this._recordedChunks.push(event.data)
    }

    this._mediaRecorder.onstop = () => {
      const blob = new Blob(this._recordedChunks, { type: mimeType })
      const url = URL.createObjectURL(blob)
      const link = document.createElement("a")
      link.href = url
      link.download = `globe-${new Date().toISOString().slice(0, 19).replace(/:/g, "-")}.webm`
      link.click()
      URL.revokeObjectURL(url)
      this._recordedChunks = []
    }

    this._mediaRecorder.start(1000)
    this._recordingStart = Date.now()
    if (this.hasRecordBtnTarget) this.recordBtnTarget.classList.add("recording")
    if (this.hasRecordIconTarget) this.recordIconTarget.className = "fa-solid fa-stop"
    this._recordingTimerInterval = setInterval(() => this._updateRecordingTimer(), 1000)
  }

  GlobeController.prototype._stopRecording = function() {
    if (this._mediaRecorder) {
      this._mediaRecorder.stop()
      this._mediaRecorder = null
    }
    if (this._recordingTimerInterval) {
      clearInterval(this._recordingTimerInterval)
      this._recordingTimerInterval = null
    }
    if (this.hasRecordBtnTarget) this.recordBtnTarget.classList.remove("recording")
    if (this.hasRecordIconTarget) this.recordIconTarget.className = "fa-solid fa-circle"
    document.getElementById("record-timer")?.remove()
  }

  GlobeController.prototype._updateRecordingTimer = function() {
    const elapsed = Math.floor((Date.now() - this._recordingStart) / 1000)
    const min = String(Math.floor(elapsed / 60)).padStart(2, "0")
    const sec = String(elapsed % 60).padStart(2, "0")

    let badge = document.getElementById("record-timer")
    if (!badge) {
      badge = document.createElement("div")
      badge.id = "record-timer"
      const strip = document.getElementById("bottom-strip")
      const controls = strip?.querySelector(".bs-controls")
      ;(controls || strip)?.appendChild(badge)
    }
    badge.textContent = `${min}:${sec}`
  }

  GlobeController.prototype.takeScreenshot = function() {
    const canvas = this.viewer.scene.canvas
    this.viewer.scene.render()

    canvas.toBlob(blob => {
      if (!blob) return
      const url = URL.createObjectURL(blob)
      const link = document.createElement("a")
      link.href = url
      link.download = `globe-${new Date().toISOString().slice(0, 19).replace(/:/g, "-")}.png`
      link.click()
      URL.revokeObjectURL(url)
    }, "image/png")
  }

  GlobeController.prototype.toggleTrains = function() {
    // Placeholder.
  }

  GlobeController.prototype._generateAreaReport = async function() {
    const container = document.getElementById("area-report-content")
    if (!container) return

    const bounds = this.getFilterBounds()
    if (!bounds) {
      container.innerHTML = `<div style="font:400 10px monospace;color:#888;padding:8px 0;">Select a country or draw a circle first.</div>`
      return
    }

    container.innerHTML = `<div style="font:400 10px monospace;color:#888;padding:8px 0;">Generating report...</div>`

    try {
      const params = new URLSearchParams(bounds)
      const response = await fetch(`/api/area_report?${params}`)
      if (!response.ok) {
        container.innerHTML = ""
        return
      }
      const report = await response.json()
      container.innerHTML = this._renderAreaReport(report)
    } catch (error) {
      console.warn("Area report failed:", error)
      container.innerHTML = ""
    }
  }

  GlobeController.prototype._renderAreaReport = function(report) {
    const snapshotStatus = report.snapshot_status || "ready"
    let html = `<div style="margin-top:10px;border-top:1px solid #333;padding-top:8px;">`
    html += `<div style="display:flex;align-items:center;justify-content:space-between;gap:8px;flex-wrap:wrap;margin-bottom:8px;">
      <div style="font:600 9px monospace;color:#4fc3f7;letter-spacing:1px;text-transform:uppercase;">AREA REPORT</div>
      ${this._statusChip(snapshotStatus, this._statusLabel(snapshotStatus, "snapshot"))}
    </div>`

    if (report.flights) {
      const flights = report.flights
      html += this._reportSection("fa-plane", "#4fc3f7", "Aviation", [
        `${this._escapeHtml(flights.total)} flights (${this._escapeHtml(flights.military)} military, ${this._escapeHtml(flights.civilian)} civilian)`,
        flights.emergency > 0 ? `<span style="color:#f44336;">${this._escapeHtml(flights.emergency)} emergency</span>` : null,
        flights.top_countries ? `Top: ${Object.entries(flights.top_countries).map(([country, count]) => `${this._escapeHtml(country)} (${this._escapeHtml(count)})`).join(", ")}` : null,
      ])
    }

    if (report.earthquakes) {
      const earthquakes = report.earthquakes
      html += this._reportSection("fa-house-crack", "#ff7043", "Seismic (7d)", [
        `${this._escapeHtml(earthquakes.total)} earthquakes, avg M${this._escapeHtml(earthquakes.avg_magnitude)}`,
        `Strongest: M${this._escapeHtml(earthquakes.max_magnitude)} ${this._escapeHtml(earthquakes.max_title)}`,
        earthquakes.tsunami_warnings > 0 ? `<span style="color:#f44336;">${this._escapeHtml(earthquakes.tsunami_warnings)} tsunami warnings</span>` : null,
      ])
    }

    if (report.fires) {
      const fires = report.fires
      html += this._reportSection("fa-fire", "#ff5722", "Active Fires (48h)", [
        `${this._escapeHtml(fires.total)} hotspots${fires.high_confidence > 0 ? ` (${this._escapeHtml(fires.high_confidence)} high confidence)` : ""}`,
        fires.max_frp ? `Max fire power: ${this._escapeHtml(fires.max_frp)} MW` : null,
        fires.satellites?.length > 0 ? `Detected by: ${fires.satellites.map(satellite => this._escapeHtml(satellite)).join(", ")}` : null,
      ])
    }

    if (report.conflicts) {
      const conflicts = report.conflicts
      html += this._reportSection("fa-crosshairs", "#f44336", "Conflicts", [
        `${this._escapeHtml(conflicts.total)} events, ${this._escapeHtml(conflicts.casualties)} casualties`,
        conflicts.conflicts.map(conflict => this._escapeHtml(conflict)).join(", "),
      ])
    }

    if (report.jamming) {
      const jamming = report.jamming
      html += this._reportSection("fa-satellite-dish", "#ff9800", "GPS Jamming", [
        jamming.high_cells > 0 ? `${this._escapeHtml(jamming.high_cells)} high-intensity cells` : null,
        jamming.medium_cells > 0 ? `${this._escapeHtml(jamming.medium_cells)} medium-intensity cells` : null,
      ])
    }

    if (report.infrastructure) {
      const infrastructure = report.infrastructure
      const infraItems = [
        `${this._escapeHtml(infrastructure.power_plants)} power plants (${this._escapeHtml(infrastructure.total_capacity_mw?.toLocaleString())} MW)`,
        infrastructure.nuclear > 0 ? `<span style="color:#fdd835;">${this._escapeHtml(infrastructure.nuclear)} nuclear</span>` : null,
        infrastructure.submarine_cables > 0 ? `${this._escapeHtml(infrastructure.submarine_cables)} submarine cables` : null,
        infrastructure.fuel_mix ? Object.entries(infrastructure.fuel_mix).map(([fuel, count]) => `${this._escapeHtml(fuel)}: ${this._escapeHtml(count)}`).join(", ") : null,
      ]
      if (infrastructure.country_shares?.length > 0) {
        infraItems.push(`<span style="color:#fdd835;font-weight:600;">National capacity share:</span>`)
        infrastructure.country_shares.forEach(share => {
          infraItems.push(`${this._escapeHtml(share.country)}: ${this._escapeHtml(share.area_mw?.toLocaleString())} / ${this._escapeHtml(share.national_mw?.toLocaleString())} MW (${this._escapeHtml(share.pct)}%)`)
        })
      }
      html += this._reportSection("fa-bolt", "#fdd835", "Infrastructure", infraItems)
    }

    if (report.anomalies?.length > 0) {
      const items = report.anomalies.map(anomaly => `<span style="color:${this._escapeHtml(anomaly.color)};">${this._escapeHtml(anomaly.title)}</span>`)
      html += this._reportSection("fa-triangle-exclamation", "#f44336", "Active Anomalies", items)
    }

    const sections = [report.flights, report.earthquakes, report.fires, report.conflicts, report.jamming, report.infrastructure, report.anomalies]
    if (sections.every(section => !section)) {
      html += `<div style="font:400 10px monospace;color:#666;padding:4px 0;">No significant data in this area.</div>`
    }

    html += `</div>`
    return html
  }

  GlobeController.prototype._reportSection = function(icon, color, title, items) {
    const filtered = items.filter(Boolean)
    if (filtered.length === 0) return ""
    return `<div style="margin-bottom:8px;padding:5px 7px;background:rgba(255,255,255,0.03);border-left:3px solid ${color};border-radius:0 4px 4px 0;">
      <div style="display:flex;align-items:center;gap:5px;margin-bottom:3px;">
        <i class="fa-solid ${icon}" style="color:${color};font-size:10px;"></i>
        <span style="font:600 10px monospace;color:${color};">${this._escapeHtml(title)}</span>
      </div>
      ${filtered.map(item => `<div style="font:400 10px monospace;color:#aaa;padding:1px 0;">${item}</div>`).join("")}
    </div>`
  }
}
