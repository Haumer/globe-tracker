export function applyContextNodeTheaterDossierMethods(GlobeController) {
  GlobeController.prototype._theaterFallbackAssessment = function(zone = {}) {
    const trend = (zone.escalation_trend || zone.trend || "active").replace(/_/g, " ")
    const signals = zone.cross_layer_signals || {}
    const signalNames = []
    if (signals.military_flights) signalNames.push("military aviation")
    if (signals.gps_jamming) signalNames.push("GPS jamming")
    if (signals.internet_outage) signalNames.push("communications disruption")
    if (signals.fire_hotspots) signalNames.push("thermal activity")

    const corroboration = signalNames.length >= 2
      ? `Cross-layer corroboration from ${signalNames.join(", ")} reinforces the ${trend} read.`
      : signalNames.length === 1
        ? `${signalNames[0].charAt(0).toUpperCase() + signalNames[0].slice(1)} provides partial corroboration.`
        : "No cross-layer corroboration available — read is based on reporting volume alone."

    const depth = (zone.source_count || 0) >= 4
      ? "Source depth is adequate for a sustained assessment."
      : "Source depth is still thin; treat this read as provisional."

    return `Theater is in a ${trend} posture. ${corroboration} ${depth}`.trim()
  }

  GlobeController.prototype._theaterDerivedConfidence = function(zone = {}) {
    const score = zone.pulse_score || 0
    const sources = zone.source_count || 0
    const stories = zone.story_count || 0

    if (score >= 70 && sources >= 4 && stories >= 3) {
      return {
        level: "high",
        rationale: "Multiple recent sources and story clusters support the current escalation read.",
      }
    }
    if (sources >= 2 || stories >= 2) {
      return {
        level: "medium",
        rationale: "The read is supported by some corroboration, but fresh independent confirmation is still useful.",
      }
    }
    return {
      level: "low",
      rationale: "Source depth is still thin, so the current read should be treated as provisional.",
    }
  }

  GlobeController.prototype._theaterDerivedWhyBeliefItems = function(zone = {}) {
    const items = []
    const signals = zone.cross_layer_signals || {}

    if (zone.count_24h || zone.source_count) {
      const bits = []
      if (zone.count_24h) bits.push(`${zone.count_24h} reports in the last 24h`)
      if (zone.source_count) bits.push(`${zone.source_count} sources`)
      if (bits.length) items.push(bits.join(" across "))
    }

    if (zone.story_count) {
      items.push(`${zone.story_count} story cluster${zone.story_count === 1 ? "" : "s"} are carrying the theater`)
    }

    if (zone.spike_ratio) {
      items.push(`Reporting is running at ${zone.spike_ratio}x baseline`)
    }

    if (signals.military_flights) {
      items.push(`${signals.military_flights} nearby military flight signal${signals.military_flights === 1 ? "" : "s"} support the read`)
    }
    if (signals.gps_jamming) {
      items.push(`${signals.gps_jamming}% GPS jamming adds electronic-warfare corroboration`)
    }
    if (signals.internet_outage) {
      items.push(`Communications disruption is present nearby (${signals.internet_outage})`)
    }
    if (signals.fire_hotspots) {
      items.push(`${signals.fire_hotspots} fire hotspots provide physical disruption corroboration`)
    }

    const leadArticle = (zone.top_articles || [])[0]
    if (leadArticle?.title) {
      items.push(`Lead reporting is centered on "${leadArticle.title}"`)
    }

    return items.slice(0, 4)
  }

  GlobeController.prototype._theaterReportingItems = function(zone = {}) {
    const reportingItems = []

    ;(zone.top_articles || []).slice(0, 4).forEach(article => {
      reportingItems.push({
        label: article.title || "Related story",
        meta: [article.publisher || article.source, article.published_at ? this._timeAgo(new Date(article.published_at)) : null].filter(Boolean).join(" · "),
        nodeRequest: article.cluster_id ? { kind: "news_story_cluster", id: article.cluster_id } : null,
        url: article.url,
      })
    })

    ;(zone.top_headlines || []).slice(0, Math.max(0, 4 - reportingItems.length)).forEach(headline => {
      reportingItems.push({ label: headline, meta: "supporting headline" })
    })

    return reportingItems
  }

  GlobeController.prototype._theaterWatchNextItems = function(zone = {}) {
    const signals = zone.cross_layer_signals || {}
    const items = []

    if (["surging", "escalating"].includes(zone.escalation_trend)) {
      items.push("A further rise in report volume or spike ratio would confirm sustained escalation.")
    }
    if (signals.military_flights) {
      items.push("Additional military flight activity near the theater would reinforce the operational tempo read.")
    }
    if (signals.gps_jamming) {
      items.push("Persistent or expanding GPS jamming would indicate wider disruption around the theater.")
    }
    if (signals.internet_outage) {
      items.push("Sustained communications outages would strengthen the case for infrastructure or control pressure.")
    }
    if ((zone.source_count || 0) < 3) {
      items.push("Independent follow-on reporting is needed to raise confidence in the current assessment.")
    } else {
      items.push("A drop-off in fresh corroborating reporting over the next cycle would weaken the escalation signal.")
    }

    return [...new Set(items)].slice(0, 3)
  }

  GlobeController.prototype._contextBulletListHtml = function(items = []) {
    const rows = (items || [])
      .map(item => `${item}`.trim())
      .filter(Boolean)
      .map(item => `<li>${this._escapeHtml(item)}</li>`)
      .join("")

    return rows ? `<ul class="context-bullet-list">${rows}</ul>` : ""
  }

  // ── Proximity helpers (JS-computed, no LLM) ─────────────────

  GlobeController.prototype._theaterNearbyInfrastructure = function(lat, lng, radiusKm = 300) {
    const result = { chokepoints: [], powerPlants: 0, cameras: [], militaryBases: 0 }
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return result

    const degThreshold = radiusKm / 111

    function nearby(pLat, pLng) {
      return Math.abs(pLat - lat) < degThreshold && Math.abs(pLng - lng) < degThreshold
    }

    ;(this._chokepointData || []).forEach(cp => {
      if (nearby(cp.lat, cp.lng)) {
        result.chokepoints.push({ name: cp.name || "Unnamed chokepoint", status: cp.status || "monitoring" })
      }
    })

    result.powerPlants = (this._powerPlantAll || []).filter(p => nearby(p.lat, p.lng)).length

    ;(this._cameraMarkers || []).forEach(cam => {
      const cLat = cam.lat ?? cam.latitude
      const cLng = cam.lng ?? cam.longitude
      if (cLat != null && cLng != null && nearby(cLat, cLng)) {
        result.cameras.push({ title: cam.title || cam.name, mode: cam.mode || "unknown" })
      }
    })

    result.militaryBases = (this._militaryBaseEntities || []).filter(b => {
      const bLat = b.lat ?? b.latitude
      const bLng = b.lng ?? b.longitude
      return bLat != null && bLng != null && nearby(bLat, bLng)
    }).length

    return result
  }

  GlobeController.prototype._theaterSoWhatLines = function(zone, nearby) {
    const lines = []

    if (nearby.chokepoints.length) {
      const critical = nearby.chokepoints.filter(c => c.status === "critical")
      if (critical.length) {
        lines.push(`${critical.map(c => c.name).join(", ")} — critical chokepoint${critical.length > 1 ? "s" : ""} within range. Transit risk is elevated.`)
      } else {
        lines.push(`${nearby.chokepoints.map(c => c.name).join(", ")} within range (${nearby.chokepoints[0].status}).`)
      }
    }

    if (nearby.powerPlants > 0) {
      lines.push(`${nearby.powerPlants} power plant${nearby.powerPlants > 1 ? "s" : ""} within range — energy infrastructure exposure.`)
    }

    if (nearby.cameras.length) {
      const live = nearby.cameras.filter(c => c.mode === "realtime" || c.mode === "live")
      if (live.length) {
        lines.push(`${live.length} live camera${live.length > 1 ? "s" : ""} available for visual confirmation.`)
      } else {
        lines.push(`${nearby.cameras.length} camera${nearby.cameras.length > 1 ? "s" : ""} nearby — none live (${nearby.cameras[0].mode}).`)
      }
    } else {
      lines.push("No cameras within range.")
    }

    if (nearby.militaryBases > 0) {
      lines.push(`${nearby.militaryBases} known military installation${nearby.militaryBases > 1 ? "s" : ""} nearby.`)
    }

    return lines
  }

  // ── Recommended actions (JS-computed from layer state + signals) ──

  GlobeController.prototype._theaterRecommendedActions = function(zone, nearby) {
    const actions = []
    const signals = zone.cross_layer_signals || {}

    // Latest trigger event
    const leadArticle = (zone.top_articles || [])[0]
    if (leadArticle) {
      actions.push({
        label: "View latest trigger event",
        detail: leadArticle.title || "Recent report",
        icon: "fa-solid fa-newspaper",
        action: "openArticle",
        url: leadArticle.url,
        nodeRequest: leadArticle.cluster_id ? { kind: "news_story_cluster", id: leadArticle.cluster_id } : null,
      })
    }

    // Layer suggestions based on signals present + layer not enabled
    if (signals.gps_jamming && !this.gpsJammingVisible) {
      actions.push({
        label: "Enable GPS Jamming layer",
        detail: `${signals.gps_jamming}% jamming detected nearby`,
        icon: "fa-solid fa-satellite-dish",
        action: "enableLayer",
        toggle: "gpsJammingToggle",
      })
    }

    if (signals.military_flights && !this._milFlightsActive) {
      actions.push({
        label: "Enable Military Flights filter",
        detail: `${signals.military_flights} military flight signal${signals.military_flights > 1 ? "s" : ""}`,
        icon: "fa-solid fa-jet-fighter",
        action: "enableLayer",
        toggle: "militaryFlightsToggle",
      })
    }

    if (signals.internet_outage && !this.outagesVisible) {
      actions.push({
        label: "Enable Internet Outages layer",
        detail: `${signals.internet_outage}`,
        icon: "fa-solid fa-wifi",
        action: "enableLayer",
        toggle: "outagesToggle",
      })
    }

    if (signals.fire_hotspots && !this.fireHotspotsVisible) {
      actions.push({
        label: "Enable Fire Hotspots layer",
        detail: `${signals.fire_hotspots} thermal anomal${signals.fire_hotspots > 1 ? "ies" : "y"}`,
        icon: "fa-solid fa-fire",
        action: "enableLayer",
        toggle: "fireHotspotsToggle",
      })
    }

    // Cameras
    if (nearby.cameras.length > 0) {
      const live = nearby.cameras.filter(c => c.mode === "realtime" || c.mode === "live")
      actions.push({
        label: "Check nearby cameras",
        detail: live.length
          ? `${live.length} live, ${nearby.cameras.length - live.length} other`
          : `${nearby.cameras.length} camera${nearby.cameras.length > 1 ? "s" : ""} (${nearby.cameras[0].mode})`,
        icon: "fa-solid fa-video",
        action: "showCameras",
      })
    } else if (!this.camerasVisible) {
      actions.push({
        label: "Enable Cameras layer",
        detail: "No cameras loaded — enable to check coverage",
        icon: "fa-solid fa-video",
        action: "enableLayer",
        toggle: "camerasToggle",
      })
    }

    // Infrastructure
    if (nearby.chokepoints.length || nearby.powerPlants) {
      const parts = []
      if (nearby.chokepoints.length) parts.push(`${nearby.chokepoints.length} chokepoint${nearby.chokepoints.length > 1 ? "s" : ""}`)
      if (nearby.powerPlants) parts.push(`${nearby.powerPlants} power plant${nearby.powerPlants > 1 ? "s" : ""}`)
      actions.push({
        label: "Review nearby infrastructure",
        detail: parts.join(", "),
        icon: "fa-solid fa-industry",
        action: "enableInfra",
      })
    }

    return actions
  }

  // ── Delta tracker (client-side memory) ──────────────────────

  GlobeController.prototype._theaterDeltaSnapshot = function(zone) {
    return {
      pulse_score: zone.pulse_score || 0,
      count_24h: zone.count_24h || 0,
      source_count: zone.source_count || 0,
      spike_ratio: zone.spike_ratio || 0,
      story_count: zone.story_count || 0,
      signals: { ...(zone.cross_layer_signals || {}) },
      ts: Date.now(),
    }
  }

  GlobeController.prototype._theaterTrackDelta = function(zone) {
    const key = zone.cell_key || zone.theater || zone.situation_name
    if (!key) return null

    this._theaterDeltaStore ||= new Map()
    const current = this._theaterDeltaSnapshot(zone)
    const previous = this._theaterDeltaStore.get(key)
    this._theaterDeltaStore.set(key, current)

    if (!previous) return null

    const elapsed = current.ts - previous.ts
    if (elapsed < 30_000) return null // less than 30s, too soon

    const changes = []
    const pulseDelta = current.pulse_score - previous.pulse_score
    if (pulseDelta !== 0) {
      const arrow = pulseDelta > 0 ? "↑" : "↓"
      changes.push(`Pulse ${current.pulse_score} ${arrow} from ${previous.pulse_score}`)
    }

    const reportDelta = current.count_24h - previous.count_24h
    if (reportDelta > 0) {
      changes.push(`${reportDelta} new report${reportDelta > 1 ? "s" : ""} (${current.count_24h} total)`)
    }

    const sourceDelta = current.source_count - previous.source_count
    if (sourceDelta > 0) {
      changes.push(`${sourceDelta} new source${sourceDelta > 1 ? "s" : ""} (${current.source_count} total)`)
    }

    const spikeDelta = current.spike_ratio - previous.spike_ratio
    if (Math.abs(spikeDelta) >= 0.3) {
      const arrow = spikeDelta > 0 ? "↑" : "↓"
      changes.push(`Spike ratio ${current.spike_ratio}x ${arrow} from ${previous.spike_ratio}x`)
    }

    // New signals that weren't present before
    const prevSignals = previous.signals || {}
    const curSignals = current.signals || {}
    for (const [key, val] of Object.entries(curSignals)) {
      if (val && !prevSignals[key]) {
        const label = key.replace(/_/g, " ")
        changes.push(`${label} just appeared`)
      }
    }
    // Signals that disappeared
    for (const [key, val] of Object.entries(prevSignals)) {
      if (val && !curSignals[key]) {
        const label = key.replace(/_/g, " ")
        changes.push(`${label} no longer detected`)
      }
    }

    if (!changes.length) return null

    const mins = Math.round(elapsed / 60_000)
    const timeLabel = mins < 2 ? "just now" : mins < 60 ? `in the last ${mins}m` : `in the last ${Math.round(mins / 60)}h`

    return { changes, timeLabel }
  }

  // ── Section renderers ──────────────────────────────────────

  GlobeController.prototype._theaterSituationHtml = function(context) {
    const brief = context.theaterBrief || {}
    const zone = context.zoneData || {}
    const derivedConfidence = this._theaterDerivedConfidence(zone)
    const confidenceLevel = brief.confidence_level || derivedConfidence.level
    const confidenceRationale = brief.confidence_rationale || derivedConfidence.rationale
    const assessment = brief.assessment || this._theaterFallbackAssessment(zone)

    const generatedAgo = context.theaterBriefGeneratedAt ? this._timeAgo(new Date(context.theaterBriefGeneratedAt)) : null
    let stateHtml = ""
    if (context.theaterBriefStatus === "ready" && generatedAgo) {
      stateHtml = `<div class="context-brief-state">Stored AI brief · ${this._escapeHtml(generatedAgo)}</div>`
    } else if (["loading", "pending"].includes(context.theaterBriefStatus)) {
      stateHtml = '<div class="context-brief-state">Generating AI brief from current evidence…</div>'
    } else if (context.theaterBriefStatus === "error") {
      stateHtml = '<div class="context-brief-state context-brief-state--error">AI brief unavailable. Showing live factual read.</div>'
    }

    const lat = parseFloat(zone.lat)
    const lng = parseFloat(zone.lng)
    const nearby = this._theaterNearbyInfrastructure(lat, lng)
    const soWhatLines = this._theaterSoWhatLines(zone, nearby)
    const delta = this._theaterTrackDelta(zone)

    let deltaHtml = ""
    if (delta) {
      deltaHtml = `
        <div class="context-brief-group">
          <div class="context-brief-label">Changed ${this._escapeHtml(delta.timeLabel)}</div>
          ${this._contextBulletListHtml(delta.changes)}
        </div>
      `
    }

    return `
      <div class="context-brief">
        <div class="context-brief-group">
          <div class="context-brief-body">${this._escapeHtml(assessment)}</div>
        </div>
        ${deltaHtml}
        ${soWhatLines.length ? `
          <div class="context-brief-group">
            <div class="context-brief-label">So what</div>
            ${this._contextBulletListHtml(soWhatLines)}
          </div>
        ` : ""}
        <div class="context-brief-confidence">
          <span class="context-brief-confidence-level context-brief-confidence-level--${this._escapeHtml(confidenceLevel)}">${this._escapeHtml(confidenceLevel)} confidence</span>
          <span class="context-brief-confidence-text">${this._escapeHtml(confidenceRationale || "")}</span>
        </div>
        ${stateHtml}
      </div>
    `
  }

  GlobeController.prototype._theaterActionsHtml = function(context) {
    const zone = context.zoneData || {}
    const lat = parseFloat(zone.lat)
    const lng = parseFloat(zone.lng)
    const nearby = this._theaterNearbyInfrastructure(lat, lng)
    const actions = this._theaterRecommendedActions(zone, nearby)

    if (!actions.length) return ""

    const rows = actions.map(item => {
      let attrs = ""
      if (item.action === "enableLayer") {
        attrs = `data-action="click->globe#theaterEnableLayer" data-toggle="${this._escapeHtml(item.toggle)}"`
      } else if (item.action === "showCameras") {
        attrs = `data-action="click->globe#theaterShowCameras"`
      } else if (item.action === "enableInfra") {
        attrs = `data-action="click->globe#theaterEnableInfra"`
      } else if (item.action === "openArticle" && item.url) {
        return `<a class="theater-action-row" href="${this._safeUrl(item.url)}" target="_blank" rel="noopener">
          <i class="${this._escapeHtml(item.icon)} theater-action-icon" aria-hidden="true"></i>
          <div class="theater-action-copy">
            <div class="theater-action-label">${this._escapeHtml(item.label)}</div>
            <div class="theater-action-detail">${this._escapeHtml(item.detail)}</div>
          </div>
          <i class="fa-solid fa-chevron-right theater-action-arrow" aria-hidden="true"></i>
        </a>`
      }

      return `<button class="theater-action-row" type="button" ${attrs}>
        <i class="${this._escapeHtml(item.icon)} theater-action-icon" aria-hidden="true"></i>
        <div class="theater-action-copy">
          <div class="theater-action-label">${this._escapeHtml(item.label)}</div>
          <div class="theater-action-detail">${this._escapeHtml(item.detail)}</div>
        </div>
        <i class="fa-solid fa-chevron-right theater-action-arrow" aria-hidden="true"></i>
      </button>`
    }).join("")

    return rows
  }

  GlobeController.prototype._theaterDeepDiveHtml = function(context) {
    const zone = context.zoneData || {}
    const brief = context.theaterBrief || {}
    const signals = zone.cross_layer_signals || {}
    const reportingItems = this._theaterReportingItems(zone)
    const signalChips = []

    if (signals.military_flights) signalChips.push({ label: `${signals.military_flights} military flights`, variant: "flight" })
    if (signals.gps_jamming) signalChips.push({ label: `${signals.gps_jamming}% jamming`, variant: "jam" })
    if (signals.internet_outage) signalChips.push({ label: `${signals.internet_outage}`, variant: "outage" })
    if (signals.fire_hotspots) signalChips.push({ label: `${signals.fire_hotspots} fires`, variant: "fire" })
    if (signals.known_conflict_zone) signalChips.push({ label: `${signals.known_conflict_zone} prior incidents`, variant: "conf" })

    const whyItems = Array(brief.why_we_believe_it || [])
    const derivedWhyItems = whyItems.length ? whyItems : this._theaterDerivedWhyBeliefItems(zone)
    const watchNextItems = Array(brief.watch_next || [])
    const watchList = watchNextItems.length ? watchNextItems : this._theaterWatchNextItems(zone)
    const developmentBullets = Array(brief.key_developments || [])

    const blocks = []

    if (derivedWhyItems.length) {
      blocks.push(`<details class="theater-deep-section">
        <summary class="theater-deep-summary">Evidence basis</summary>
        <div class="theater-deep-body">${this._contextBulletListHtml(derivedWhyItems)}</div>
      </details>`)
    }

    if (developmentBullets.length) {
      blocks.push(`<details class="theater-deep-section">
        <summary class="theater-deep-summary">Key developments (${developmentBullets.length})</summary>
        <div class="theater-deep-body">${this._contextBulletListHtml(developmentBullets)}</div>
      </details>`)
    }

    if (signalChips.length) {
      const chipsHtml = signalChips.map(chip =>
        `<span class="sit-chip sit-chip--${this._escapeHtml(chip.variant)}">${this._escapeHtml(chip.label)}</span>`
      ).join("")
      blocks.push(`<details class="theater-deep-section">
        <summary class="theater-deep-summary">Corroboration signals</summary>
        <div class="theater-deep-body"><div class="sit-zone-chips">${chipsHtml}</div></div>
      </details>`)
    }

    if (watchList.length) {
      blocks.push(`<details class="theater-deep-section">
        <summary class="theater-deep-summary">Watch next</summary>
        <div class="theater-deep-body">${this._contextBulletListHtml(watchList)}</div>
      </details>`)
    }

    return blocks.join("")
  }

  // ── Action click handlers ──────────────────────────────────

  GlobeController.prototype.theaterEnableLayer = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    const toggle = event?.currentTarget?.dataset?.toggle
    if (toggle) this._enableLayer(toggle)
  }

  GlobeController.prototype.theaterShowCameras = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    if (!this.camerasVisible) this._enableLayer("camerasToggle")
    this._showRightPanel?.("cameras")
  }

  GlobeController.prototype.theaterEnableInfra = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    if (!this.chokepointsVisible) this._enableLayer("chokepointsToggle")
    if (!this.powerPlantsVisible) this._enableLayer("powerPlantsToggle")
  }

  // ── Main hydration ─────────────────────────────────────────

  GlobeController.prototype._hydrateTheaterContextSections = function(context) {
    if (!context || context.kind !== "theater") return context

    context.sections = [
      { title: "Situation", html: this._theaterSituationHtml(context) },
      { title: "Recommended actions", html: this._theaterActionsHtml(context), variant: "actions" },
      { title: "Deep dive", html: this._theaterDeepDiveHtml(context), variant: "deep-dive" },
    ].filter(s => s && s.html)

    return context
  }
}
