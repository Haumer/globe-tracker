import { applyConflictPulseInteractionMethods } from "globe/controller/infrastructure/conflict_pulse_interactions"
import { applyConflictPulseRenderingMethods } from "globe/controller/infrastructure/conflict_pulse_rendering"

export function applyConflictPulseMethods(GlobeController) {
  applyConflictPulseRenderingMethods(GlobeController)
  applyConflictPulseInteractionMethods(GlobeController)

  GlobeController.prototype.toggleSituations = function() {
    this.situationsVisible = this.hasSituationsToggleTarget && this.situationsToggleTarget.checked
    this._strikeArcsVisible = this.hasStrikeArcsToggleTarget && this.strikeArcsToggleTarget.checked
    this._hexTheaterVisible = this.hasHexTheaterToggleTarget && this.hexTheaterToggleTarget.checked
    if (this.situationsVisible) {
      this._startConflictPulse()
    } else {
      this._stopConflictPulse({ clearData: true })
    }
    this._updateStats()
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._startConflictPulse = function() {
    if (this._conflictPulseInterval) clearInterval(this._conflictPulseInterval)
    if (!this.situationsVisible) return
    if (!this._timelineActive) this._fetchConflictPulse()
    this._conflictPulseInterval = setInterval(() => {
      if (this.situationsVisible && !this._timelineActive) this._fetchConflictPulse()
    }, 10 * 60 * 1000)
  }

  GlobeController.prototype._stopConflictPulse = function({ clearData = false } = {}) {
    if (this._conflictPulseInterval) {
      clearInterval(this._conflictPulseInterval)
      this._conflictPulseInterval = null
    }
    this._conflictPulseFetchToken += 1
    this._clearConflictPulseEntities()
    if (clearData) {
      this._conflictPulseData = []
      this._conflictPulseZones = []
      this._strategicSituationData = []
      this._strikeArcData = []
      this._hexCellData = []
      this._conflictPulsePrev = {}
      this._conflictPulsePrevScores = {}
      this._conflictPulseSnapshotStatus = null
      this._highlightedTheater = null
      this._hexLayerAutoEnabled = false
      this._renderSituationPanel()
      if (this._syncRightPanels) this._syncRightPanels()
    }
  }

  GlobeController.prototype._fetchConflictPulse = async function() {
    if (!this.situationsVisible || this._timelineActive) return
    const fetchToken = ++this._conflictPulseFetchToken
    try {
      const resp = await fetch("/api/conflict_pulse")
      if (fetchToken !== this._conflictPulseFetchToken || !this.situationsVisible || this._timelineActive) return
      if (!resp.ok) return
      const data = await resp.json()
      if (fetchToken !== this._conflictPulseFetchToken || !this.situationsVisible || this._timelineActive) return
      const zones = data.zones || []
      this._conflictPulseSnapshotStatus = data.snapshot_status || "ready"

      // Detect new surges — compare to previous state
      const prev = this._conflictPulsePrev || {}
      zones.forEach(zone => {
        const prevZone = prev[zone.cell_key]
        if (!prevZone && zone.escalation_trend === "surging") {
          // Brand new surging zone
          this._toastConflictPulse(zone)
        } else if (prevZone && prevZone.escalation_trend !== "surging" && zone.escalation_trend === "surging") {
          // Escalated to surging
          this._toastConflictPulse(zone)
        } else if (!prevZone && zone.pulse_score >= 70) {
          // High-scoring new zone
          this._toastConflictPulse(zone)
        }
      })

      // Cache current state for next comparison
      this._conflictPulsePrev = {}
      zones.forEach(z => { this._conflictPulsePrev[z.cell_key] = z })

      this._conflictPulseData = zones
      this._conflictPulseZones = zones
      this._strategicSituationData = data.strategic_situations || []
      this._strikeArcData = data.strike_arcs || []
      this._hexCellData = data.hex_cells || []
      this._renderConflictPulse()
      this._renderSituationPanel()
      this._markFresh("situations")
      if (this._syncRightPanels) this._syncRightPanels()
    } catch (e) {
      console.warn("Conflict pulse fetch failed:", e)
    }
  }

  GlobeController.prototype._toastConflictPulse = function(zone) {
    const headline = zone.top_headlines?.[0] || "Developing situation detected"
    const trend = zone.escalation_trend.toUpperCase()
    const el = document.getElementById("gt-toast")
    if (!el) return

    clearTimeout(this._toastTimer)
    el.classList.remove("visible", "gt-toast--success", "gt-toast--error")
    el.innerHTML = ""
    el.classList.add("gt-toast--error") // red styling for urgency

    const container = document.createElement("div")
    container.style.cssText = "display:flex;flex-direction:column;gap:4px;max-width:400px;cursor:pointer;"
    container.innerHTML = `
      <div style="font:600 10px var(--gt-mono,monospace);letter-spacing:1px;color:#ff5252;">${trend} — CONFLICT PULSE ${zone.pulse_score}</div>
      <div style="font:400 11px var(--gt-mono,monospace);color:#fff;line-height:1.3;">${headline.slice(0, 100)}</div>
      <div style="font:400 9px var(--gt-mono,monospace);color:#aaa;">${zone.count_24h} reports · ${zone.source_count} sources · Click to focus</div>
    `
    container.addEventListener("click", () => {
      this._flyToConflictPulse(zone)
      this._toastHide()
    })

    const closeBtn = document.createElement("button")
    closeBtn.className = "gt-toast-close"
    closeBtn.innerHTML = "&times;"
    closeBtn.setAttribute("aria-label", "Dismiss")
    closeBtn.addEventListener("click", (e) => { e.stopPropagation(); this._toastHide() })

    el.appendChild(container)
    el.appendChild(closeBtn)
    el.style.pointerEvents = "auto"
    el.classList.add("visible")

    // Auto-hide after 15 seconds (longer than normal toast — this is important)
    this._toastTimer = setTimeout(() => el.classList.remove("visible"), 15000)
  }
}
