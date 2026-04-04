export function applyContextNodeTheaterDossierMethods(GlobeController) {
  GlobeController.prototype._theaterFallbackAssessment = function(zone = {}) {
    const trend = (zone.escalation_trend || zone.trend || "active").replace(/_/g, " ")
    const reports = zone.count_24h ? `${zone.count_24h} reports in the last 24h` : "recent reporting"
    const sources = zone.source_count ? `from ${zone.source_count} sources` : "with limited source depth"
    const pulse = zone.pulse_score ? `Pulse ${zone.pulse_score}` : "Current pressure"
    const spike = zone.spike_ratio ? `Spike ratio is ${zone.spike_ratio}x versus baseline.` : ""

    return `${pulse} indicates ${trend} pressure in this theater, supported by ${reports} ${sources}. ${spike}`.trim()
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

  GlobeController.prototype._theaterAssessmentHtml = function(context) {
    const brief = context.theaterBrief || {}
    const derivedConfidence = this._theaterDerivedConfidence(context.zoneData || {})
    const confidenceLevel = brief.confidence_level || derivedConfidence.level
    const confidenceRationale = brief.confidence_rationale || derivedConfidence.rationale
    const whyItems = Array(brief.why_we_believe_it || [])
    const derivedWhyItems = whyItems.length ? whyItems : this._theaterDerivedWhyBeliefItems(context.zoneData || {})
    const generatedAgo = context.theaterBriefGeneratedAt ? this._timeAgo(new Date(context.theaterBriefGeneratedAt)) : null

    let stateHtml = ""
    if (context.theaterBriefStatus === "ready" && generatedAgo) {
      stateHtml = `<div class="context-brief-state">Stored AI brief · ${this._escapeHtml(generatedAgo)}</div>`
    } else if (["loading", "pending"].includes(context.theaterBriefStatus)) {
      stateHtml = '<div class="context-brief-state">Generating stored AI brief from current theater evidence…</div>'
    } else if (context.theaterBriefStatus === "error") {
      stateHtml = '<div class="context-brief-state context-brief-state--error">AI brief unavailable. Showing live factual assessment.</div>'
    }

    return `
      <div class="context-brief">
        <div class="context-brief-group">
          <div class="context-brief-label">Current read</div>
          <div class="context-brief-body">${this._escapeHtml(brief.assessment || this._theaterFallbackAssessment(context.zoneData || {}))}</div>
        </div>
        ${derivedWhyItems.length ? `
          <div class="context-brief-group">
            <div class="context-brief-label">Why this read</div>
            ${this._contextBulletListHtml(derivedWhyItems)}
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

  GlobeController.prototype._hydrateTheaterContextSections = function(context) {
    if (!context || context.kind !== "theater") return context

    const zone = context.zoneData || {}
    const signals = zone.cross_layer_signals || {}
    const reportingItems = this._theaterReportingItems(zone)
    const signalChips = []

    if (signals.military_flights) signalChips.push({ label: `${signals.military_flights} military flights`, variant: "flight" })
    if (signals.gps_jamming) signalChips.push({ label: `${signals.gps_jamming}% jamming`, variant: "jam" })
    if (signals.internet_outage) signalChips.push({ label: `${signals.internet_outage}`, variant: "outage" })
    if (signals.fire_hotspots) signalChips.push({ label: `${signals.fire_hotspots} fires`, variant: "fire" })
    if (signals.known_conflict_zone) signalChips.push({ label: `${signals.known_conflict_zone} prior incidents`, variant: "conf" })

    const corroborationRows = [
      zone.pulse_score ? { label: "Pulse", value: `${zone.pulse_score}` } : null,
      zone.escalation_trend ? { label: "Trend", value: zone.escalation_trend.replace(/_/g, " ") } : null,
      zone.count_24h ? { label: "Reports / 24h", value: `${zone.count_24h}` } : null,
      zone.source_count ? { label: "Sources", value: `${zone.source_count}` } : null,
      zone.story_count ? { label: "Story clusters", value: `${zone.story_count}` } : null,
      zone.spike_ratio ? { label: "Spike", value: `${zone.spike_ratio}x` } : null,
      zone.detected_at ? { label: "Updated", value: this._timeAgo(new Date(zone.detected_at)) } : null,
    ].filter(Boolean)

    const developmentBullets = Array(context.theaterBrief?.key_developments || [])
    const watchNextItems = Array(context.theaterBrief?.watch_next || [])
    const watchList = watchNextItems.length ? watchNextItems : this._theaterWatchNextItems(zone)

    context.sections = [
      { title: "Assessment", html: this._theaterAssessmentHtml(context) },
      (developmentBullets.length || reportingItems.length) ? {
        title: "Key developments",
        html: developmentBullets.length ? this._contextBulletListHtml(developmentBullets) : "",
        items: reportingItems,
      } : null,
      (corroborationRows.length || signalChips.length) ? {
        title: "Corroboration",
        rows: corroborationRows,
        chips: signalChips,
      } : null,
      watchList.length ? {
        title: "Watch next",
        html: this._contextBulletListHtml(watchList),
      } : null,
    ].filter(Boolean)

    return context
  }
}
