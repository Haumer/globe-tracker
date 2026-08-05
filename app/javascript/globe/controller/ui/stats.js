import {
  attentionAnchorLabel,
  attentionContextLabel,
  attentionPalette,
  attentionSeverityLabel,
} from "globe/controller/infrastructure/conflict_pulse_attention"

export function applyUiStatMethods(GlobeController) {
  GlobeController.prototype._updateStats = function() {
    // Attention region count from conflict pulse zones
    const regionCount = (this._conflictPulseData || []).length
    updateStat("stat-theaters", regionCount)

    // News article count
    const newsCount = (this._newsData || []).length
    updateStat("stat-news", newsCount)

    // Insight count
    const insightCount = (this._insightsData || []).length
    updateStat("stat-insights", insightCount)

    // Legacy stat IDs still referenced by some code paths — update silently if present
    updateStat("stat-flights", this.flightData?.size || 0)
    updateStat("stat-sats", this.satelliteEntities?.size || 0)
    updateStat("stat-ships", this.shipData?.size || 0)

    const eventCount = (this.earthquakesVisible ? this._earthquakeData.length : 0) +
      (this.naturalEventsVisible ? this._naturalEventData.length : 0) +
      (this.camerasVisible ? this._webcamData.length : 0) +
      (this.powerPlantsVisible ? this._powerPlantData.length : 0) +
      (this.conflictsVisible ? this._conflictData.length : 0) +
      (this.fireHotspotsVisible ? this._fireHotspotData.length : 0)
    updateStat("stat-events", eventCount)

    this._syncQuickBar()
    this._updateSatBadge()
    this._updateAttentionHud?.()
  }

  GlobeController.prototype._updateAttentionHud = function() {
    const hud = document.getElementById("attention-hud")
    const body = document.getElementById("attention-hud-body")
    if (!hud || !body) return

    const zones = [...(this._conflictPulseData || [])]
      .sort((a, b) => Number(b?.pulse_score || 0) - Number(a?.pulse_score || 0))
    const surfaces = [...(this._situationSurfaceData || [])]
      .sort((a, b) => Number(b?.attention_score || 0) - Number(a?.attention_score || 0))

    if (!zones.length && !surfaces.length) {
      hud.style.display = "none"
      body.innerHTML = ""
      return
    }

    const topZone = zones[0]
    const topSurface = surfaces[0]
    const title = topZone?.situation_name || topZone?.theater || topSurface?.label || "Live attention"
    const subtitle = topZone
      ? `${attentionSeverityLabel(topZone)} / ${attentionContextLabel(topZone)}`
      : `${topSurface?.severity_tier || "watch"} / ${topSurface?.scope || "surface"}`
    const reports24h = zones.reduce((sum, zone) => sum + Number(zone?.count_24h || 0), 0)
    const sources = zones.reduce((sum, zone) => sum + Number(zone?.source_count || 0), 0)
    const severeSurfaces = surfaces.filter(surface => ["critical", "high"].includes(surface?.severity_tier)).length
    const rows = zones.slice(0, 4).map(zone => {
      const key = this._escapeHtml(`${zone.cell_key || ""}`)
      const tone = attentionPalette(zone).stroke
      return `
        <button type="button" class="attention-hud__row" data-action="click->globe#focusAttentionHudZone" data-zone-key="${key}" style="--row-tone:${tone};">
          <span class="attention-hud__row-code">${this._escapeHtml(attentionAnchorLabel(zone))}</span>
          <span class="attention-hud__row-title">${this._escapeHtml(zone.situation_name || zone.theater || "Attention region")}</span>
          <span class="attention-hud__row-value">${Math.round(Number(zone.pulse_score || 0))}</span>
        </button>
      `
    }).join("")

    body.innerHTML = `
      <div class="attention-hud__primary">
        <div class="attention-hud__title">${this._escapeHtml(title)}</div>
        <div class="attention-hud__subtitle">${this._escapeHtml(subtitle)}</div>
        <div class="attention-hud__metrics">
          <div class="attention-hud__metric">
            <div class="attention-hud__metric-label">Reports 24h</div>
            <div class="attention-hud__metric-value">${formatCompact(reports24h)}</div>
          </div>
          <div class="attention-hud__metric">
            <div class="attention-hud__metric-label">Sources</div>
            <div class="attention-hud__metric-value">${formatCompact(sources)}</div>
          </div>
          <div class="attention-hud__metric">
            <div class="attention-hud__metric-label">Surfaces</div>
            <div class="attention-hud__metric-value">${formatCompact(severeSurfaces)}</div>
          </div>
        </div>
      </div>
      <div class="attention-hud__list">${rows}</div>
    `
    hud.style.display = ""
  }

  GlobeController.prototype.focusAttentionHudZone = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()

    const key = event?.currentTarget?.dataset?.zoneKey
    const zone = (this._conflictPulseData || []).find(item => `${item.cell_key || ""}` === `${key || ""}`)
    if (!zone) return

    this._flyToConflictPulse?.(zone)
  }

  GlobeController.prototype._updateClock = function() {
    const clock = document.getElementById("stat-clock")
    if (!clock) return
    clock.textContent = new Date().toUTCString().slice(17, 22)
  }

  GlobeController.prototype._initTooltips = function() {
    const tip = document.getElementById("gt-tooltip")
    if (!tip) return
    this._tipEl = tip

    const gap = 8
    let currentEl = null

    const show = event => {
      const target = event.target
      if (!target?.closest) return
      const element = target.closest("[data-tip]")
      if (!element || element === currentEl) return
      currentEl = element
      const text = element.getAttribute("data-tip")
      if (!text) return

      tip.textContent = text
      tip.style.left = "-9999px"
      tip.style.top = "-9999px"
      tip.style.opacity = "1"
      tip.style.display = "block"

      const tipW = tip.offsetWidth
      const tipH = tip.offsetHeight
      const pos = element.getAttribute("data-tip-pos") || "above"
      const rect = element.getBoundingClientRect()

      let left
      let top
      if (pos === "right") {
        left = rect.right + gap
        top = rect.top + rect.height / 2 - tipH / 2
      } else if (pos === "below") {
        left = rect.left + rect.width / 2 - tipW / 2
        top = rect.bottom + gap
      } else {
        left = rect.left + rect.width / 2 - tipW / 2
        top = rect.top - tipH - gap
      }

      if (left < 4) left = 4
      if (left + tipW > window.innerWidth - 4) left = window.innerWidth - tipW - 4
      if (top < 4) top = 4

      tip.style.left = `${left}px`
      tip.style.top = `${top}px`
    }

    const hide = event => {
      const target = event.target
      const element = target?.closest ? target.closest("[data-tip]") : null
      if (element !== currentEl) return
      tip.style.opacity = "0"
      currentEl = null
    }

    document.addEventListener("pointerenter", show, true)
    document.addEventListener("pointerleave", hide, true)
    document.addEventListener("mouseover", show)
    document.addEventListener("mouseout", hide)
  }
}

function formatCompact(value) {
  const number = Number(value || 0)
  if (!Number.isFinite(number)) return "0"
  if (number >= 1000) return `${(number / 1000).toFixed(number >= 10000 ? 0 : 1)}K`
  return `${Math.round(number)}`
}

function updateStat(id, count, callback) {
  const element = document.getElementById(id)
  if (!element) return
  element.textContent = count.toLocaleString()
  callback?.()
}
