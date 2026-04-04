export function applyContextNodeBuilderMethods(GlobeController) {
  GlobeController.prototype._buildCommodityContext = function(item = {}, nodeRequest = null) {
    const symbol = item.symbol || item.title || item.name || nodeRequest?.id || "Commodity"
    const isUp = item.change_pct > 0
    const accentColor = item.change_pct > 0 ? "#4caf50" : item.change_pct < 0 ? "#f44336" : "#ffc107"
    const summaryBits = []

    if (item.price != null) summaryBits.push(`$${Number(item.price).toFixed(item.category === "currency" ? 4 : 2)}`)
    if (item.change_pct != null) summaryBits.push(`${isUp ? "+" : ""}${Number(item.change_pct).toFixed(2)}%`)
    if (item.recorded_at) summaryBits.push(this._timeAgo(new Date(item.recorded_at)))

    return {
      kind: "commodity",
      severity: item.change_pct != null && Math.abs(item.change_pct) >= 2 ? "high" : "medium",
      statusLabel: item.change_pct > 0 ? "up" : item.change_pct < 0 ? "down" : item.category || "market",
      icon: "fa-chart-line",
      accentColor,
      eyebrow: "MARKET CONTEXT",
      title: item.name || item.title || symbol,
      subtitle: item.region || item.category || "Commodity",
      summary: summaryBits.join(" · ") || "Durable market context and strategic flow exposure.",
      meta: [
        { label: "Symbol", value: symbol },
        item.unit ? { label: "Unit", value: item.unit } : null,
        item.category ? { label: "Category", value: item.category } : null,
      ].filter(Boolean),
      actions: [],
      nodeRequest: nodeRequest || { kind: "commodity", id: item.symbol || item.name || symbol },
      sections: [],
    }
  }

  GlobeController.prototype._buildNewsContext = function(ev) {
    const categoryColors = {
      conflict: "#f44336",
      unrest: "#ff9800",
      disaster: "#ff5722",
      health: "#e91e63",
      economy: "#ffc107",
      diplomacy: "#4caf50",
      cyber: "#7c4dff",
      other: "#90a4ae",
    }

    const color = categoryColors[ev.category] || "#90a4ae"
    const location = [...new Set((ev.name || "").split(",").map(part => part.trim()).filter(Boolean))].join(", ")
    const sourceName = (ev.publisher || ev.source || "").replace(/^GN:\s*/, "")
    const claimType = ev.claim_event_type ? ev.claim_event_type.replace(/_/g, " ") : null
    const verification = ev.claim_verification_status ? ev.claim_verification_status.replace(/_/g, " ") : null
    const actors = (ev.actors || []).map(actor => actor.role ? `${actor.name} (${actor.role.replace(/_/g, " ")})` : actor.name).filter(Boolean)
    const summaryBits = []
    if (ev.source_count) summaryBits.push(`${ev.source_count} sources`)
    if (ev.article_count) summaryBits.push(`${ev.article_count} articles`)
    if (ev.time) summaryBits.push(this._timeAgo(new Date(ev.time)))

    const nearby = (this._newsData || [])
      .filter(item => item.url !== ev.url && Math.abs(item.lat - ev.lat) < 1.0 && Math.abs(item.lng - ev.lng) < 1.0)
      .slice(0, 5)

    const evidenceRows = [
      sourceName ? { label: "Publisher", value: sourceName } : null,
      ev.origin_source ? { label: "Origin", value: ev.origin_source } : null,
      ev.claim_event_type ? { label: "Claim", value: ev.claim_event_type.replace(/_/g, " ") } : null,
      ev.claim_verification_status ? { label: "Verification", value: ev.claim_verification_status.replace(/_/g, " ") } : null,
      ev.claim_confidence != null ? { label: "Claim confidence", value: `${Math.round(ev.claim_confidence * 100)}%` } : null,
      actors.length ? { label: "Actors", value: actors.join(", ") } : null,
    ].filter(Boolean)

    const themeChips = (ev.themes || [])
      .map(theme => theme.replace(/^.*_/, "").replace(/([a-z])([A-Z])/g, "$1 $2").trim())
      .filter(theme => theme.length > 2 && theme.length < 25 && !/^[A-Z]{3,}$/.test(theme))
      .slice(0, 8)
      .map(theme => ({ label: theme.toLowerCase(), variant: "eq" }))

    return {
      kind: "news",
      severity: ev.threat === "critical" ? "critical" : ev.threat === "high" ? "high" : "medium",
      statusLabel: verification || ev.threat || ev.category || "news",
      icon: "fa-newspaper",
      accentColor: color,
      eyebrow: "NEWS CONTEXT",
      title: ev.title || ev.name || "Story cluster",
      subtitle: location || "Unknown location",
      summary: [claimType, summaryBits.join(" · ")].filter(Boolean).join(" · ") || "Reporting cluster in view.",
      meta: [
        { label: "Category", value: ev.category || "other" },
        ev.cluster_confidence != null ? { label: "Cluster confidence", value: `${Math.round(ev.cluster_confidence * 100)}%` } : null,
        ev.cluster_source_reliability != null ? { label: "Source reliability", value: `${Math.round(ev.cluster_source_reliability * 100)}%` } : null,
      ].filter(Boolean),
      coordinates: Number.isFinite(ev.lat) && Number.isFinite(ev.lng)
        ? { lat: ev.lat, lng: ev.lng, height: 300000 }
        : null,
      actions: [
        { label: "Focus", lat: ev.lat, lng: ev.lng, height: 300000, icon: "fa-location-crosshairs" },
        ev.url ? { label: "Read article", url: ev.url, icon: "fa-arrow-up-right-from-square" } : null,
      ].filter(Boolean),
      nodeRequest: ev.cluster_id ? { kind: "news_story_cluster", id: ev.cluster_id } : null,
      sections: [
        evidenceRows.length ? { title: "Evidence", rows: evidenceRows } : null,
        themeChips.length ? { title: "Themes", chips: themeChips } : null,
        nearby.length ? {
          title: "Nearby reporting",
          items: nearby.map(item => ({
            label: item.title || item.name || "Nearby story",
            meta: [item.publisher || item.source, item.time ? this._timeAgo(new Date(item.time)) : null].filter(Boolean).join(" · "),
            nodeRequest: item.cluster_id ? { kind: "news_story_cluster", id: item.cluster_id } : null,
            url: item.url,
          })),
        } : null,
      ].filter(Boolean),
    }
  }

  GlobeController.prototype._buildInsightContext = function(insight) {
    const entities = insight.entities || {}
    const evidenceRows = []
    const relatedItems = []
    const theaterName = entities.theater?.name || entities.pulse?.theater || null
    const insightIdx = this._insightIndex ? this._insightIndex(insight) : -1
    const affectedEntities = this._affectedInsightEntities ? this._affectedInsightEntities(insight) : []

    if (entities.earthquake?.magnitude != null) evidenceRows.push({ label: "Earthquake", value: `M${entities.earthquake.magnitude}` })
    if (entities.cables?.length) evidenceRows.push({ label: "Cables", value: `${entities.cables.length}` })
    if (entities.plants?.length) evidenceRows.push({ label: "Plants", value: `${entities.plants.length}` })
    if (entities.flights?.total) evidenceRows.push({ label: "Flights", value: `${entities.flights.total}` })
    if (entities.jamming?.percentage != null) evidenceRows.push({ label: "GPS jamming", value: `${entities.jamming.percentage.toFixed(0)}%` })
    if (entities.news?.count_24h) evidenceRows.push({ label: "News reports", value: `${entities.news.count_24h}` })
    if (entities.outages?.length) evidenceRows.push({ label: "Outages", value: `${entities.outages.length}` })
    if (entities.conflict?.count || entities.conflict?.events) evidenceRows.push({ label: "Conflict events", value: `${entities.conflict.count || entities.conflict.events}` })
    if (entities.weather?.event) evidenceRows.push({ label: "Weather", value: entities.weather.event })
    if (entities.chokepoint?.name) evidenceRows.push({ label: "Strategic node", value: `${entities.chokepoint.name} (${entities.chokepoint.status})` })
    if (theaterName) evidenceRows.push({ label: "Theater", value: theaterName })

    if (entities.chokepoint?.name) {
      relatedItems.push({
        label: entities.chokepoint.name,
        meta: `strategic node · ${entities.chokepoint.status || "unknown status"}`,
        nodeRequest: { kind: "chokepoint", id: entities.chokepoint.name },
      })
    }
    if (theaterName) {
      relatedItems.push({
        label: theaterName,
        meta: "conflict theater",
        nodeRequest: { kind: "theater", id: theaterName },
      })
    }
    ;(entities.commodities || []).slice(0, 4).forEach(commodity => {
      relatedItems.push({
        label: commodity.name || commodity.symbol,
        meta: [commodity.symbol, commodity.change_pct != null ? `${commodity.change_pct > 0 ? "+" : ""}${commodity.change_pct}%` : null].filter(Boolean).join(" · "),
        nodeRequest: commodity.symbol ? { kind: "commodity", id: commodity.symbol } : null,
      })
    })
    ;(entities.cables || []).slice(0, 5).forEach(cable => relatedItems.push({ label: cable.name, meta: "submarine cable" }))
    ;(entities.plants || []).slice(0, 5).forEach(plant => relatedItems.push({ label: plant.name, meta: plant.fuel ? `${plant.fuel} plant` : "power plant" }))
    ;(entities.headlines || []).slice(0, 4).forEach(headline => relatedItems.push({ label: headline, meta: "supporting headline" }))
    ;(entities.conflicts || []).slice(0, 4).forEach(conflict => relatedItems.push({ label: conflict.name || conflict.title || "Conflict", meta: "conflict signal" }))

    return {
      kind: "insight",
      severity: insight.severity || "medium",
      statusLabel: insight.severity || insight.type || "insight",
      icon: "fa-brain",
      accentColor: { critical: "#f44336", high: "#ff9800", medium: "#ffc107", low: "#4caf50" }[insight.severity || "medium"],
      eyebrow: "CROSS-LAYER INSIGHT",
      title: insight.title || "Insight",
      subtitle: theaterName || (insight.type ? insight.type.replace(/_/g, " ") : ""),
      summary: insight.description || "",
      meta: [
        insight.detected_at ? { label: "Detected", value: this._timeAgo(new Date(insight.detected_at)) } : null,
        insight.lat != null && insight.lng != null ? { label: "Location", value: `${insight.lat.toFixed(2)}, ${insight.lng.toFixed(2)}` } : null,
      ].filter(Boolean),
      coordinates: Number.isFinite(insight.lat) && Number.isFinite(insight.lng)
        ? { lat: insight.lat, lng: insight.lng, height: 500000 }
        : null,
      actions: [
        insight.lat != null && insight.lng != null
          ? { label: "Focus", lat: insight.lat, lng: insight.lng, height: 500000, icon: "fa-location-crosshairs" }
          : null,
        insightIdx >= 0 && affectedEntities.length
          ? {
              label: this._affectedInsightActionLabel
                ? this._affectedInsightActionLabel(affectedEntities)
                : "Show affected entities",
              icon: "fa-crosshairs",
              handler: "showAffectedInsightEntities",
              insightIdx,
            }
          : null,
      ].filter(Boolean),
      casePayload: this._caseSourcePayloadForInsight ? this._caseSourcePayloadForInsight(insight) : null,
      nodeRequest: entities.chokepoint?.name
        ? { kind: "chokepoint", id: entities.chokepoint.name }
        : theaterName
          ? { kind: "theater", id: theaterName }
          : null,
      sections: [
        evidenceRows.length ? { title: "Evidence", rows: evidenceRows } : null,
        relatedItems.length ? { title: "Related", items: relatedItems } : null,
      ].filter(Boolean),
    }
  }

  GlobeController.prototype._buildTheaterContext = function(zoneLike) {
    const zone = typeof zoneLike === "string" ? (this._findConflictZoneForTheater(zoneLike) || { theater: zoneLike }) : (zoneLike || {})
    const theaterIdentifier = zone.theater || (typeof zoneLike === "string" ? zoneLike : null)
    const theaterName = theaterIdentifier || zone.situation_name || zone.name || "Conflict theater"
    const trend = zone.escalation_trend || zone.trend
    const pulseScore = zone.pulse_score || zone.score
    const summaryBits = []

    if (pulseScore) summaryBits.push(`Pulse ${pulseScore}`)
    if (zone.count_24h) summaryBits.push(`${zone.count_24h} reports / 24h`)
    if (zone.source_count) summaryBits.push(`${zone.source_count} sources`)
    if (trend) summaryBits.push(trend.replace(/_/g, " "))

    const context = {
      kind: "theater",
      severity: pulseScore >= 80 ? "critical" : pulseScore >= 60 ? "high" : pulseScore >= 40 ? "medium" : "low",
      statusLabel: trend || (pulseScore ? `pulse ${pulseScore}` : "monitoring"),
      icon: "fa-layer-group",
      accentColor: pulseScore >= 80 ? "#f44336" : pulseScore >= 60 ? "#ff9800" : pulseScore >= 40 ? "#ffc107" : "#4fc3f7",
      eyebrow: "THEATER CONTEXT",
      title: theaterName,
      subtitle: theaterIdentifier && zone.situation_name ? zone.situation_name : "Regional pressure and corroborating signals",
      summary: summaryBits.join(" · ") || "Regional pressure and corroborating reporting in this theater.",
      meta: [
        pulseScore ? { label: "Pulse", value: `${pulseScore}` } : null,
        zone.story_count ? { label: "Stories", value: `${zone.story_count}` } : null,
        zone.spike_ratio ? { label: "Spike", value: `${zone.spike_ratio}x` } : null,
      ].filter(Boolean),
      coordinates: Number.isFinite(zone.lat) && Number.isFinite(zone.lng)
        ? { lat: zone.lat, lng: zone.lng, height: 1200000 }
        : null,
      actions: zone.lat != null && zone.lng != null ? [
        { label: "Focus", lat: zone.lat, lng: zone.lng, height: 1200000, icon: "fa-location-crosshairs" },
      ] : [],
      casePayload: this._caseSourcePayloadForTheater ? this._caseSourcePayloadForTheater(zone) : null,
      nodeRequest: theaterIdentifier ? { kind: "theater", id: theaterIdentifier } : null,
      theaterIdentifier,
      zoneKey: zone.cell_key || null,
      zoneData: zone,
      theaterBriefStatus: "idle",
      theaterBrief: null,
      sections: [],
    }

    const cached = this._theaterBriefCache?.get(this._theaterBriefCacheKey?.(context))
    if (cached && this._applyTheaterBriefPayload) this._applyTheaterBriefPayload(context, cached)

    this._hydrateTheaterContextSections(context)
    return context
  }

  GlobeController.prototype._buildChokepointContext = function(cp) {
    const flowRows = Object.entries(cp.flows || {})
      .filter(([, flow]) => flow?.pct)
      .map(([flowType, flow]) => ({ label: flowType.replace(/_/g, " "), value: `${flow.pct}% of world` }))

    const marketChips = (cp.commodity_signals || []).map(signal => {
      const delta = signal.change_pct == null ? "" : ` ${signal.change_pct > 0 ? "+" : ""}${signal.change_pct}%`
      return { label: `${signal.symbol}${delta}`, variant: signal.change_pct > 0 ? "fire" : signal.change_pct < 0 ? "eq" : "outage" }
    })
    const marketItems = (cp.commodity_signals || []).map(signal => ({
      label: signal.name || signal.symbol,
      meta: [signal.symbol, signal.change_pct == null ? null : `${signal.change_pct > 0 ? "+" : ""}${signal.change_pct}%`].filter(Boolean).join(" · "),
      nodeRequest: signal.symbol ? { kind: "commodity", id: signal.symbol } : null,
    }))

    const pressureItems = []
    ;(cp.conflict_pulse || []).forEach(pulse => pressureItems.push({
      label: pulse.theater || `${pulse.trend} pressure`,
      meta: [pulse.trend ? `score ${pulse.score} · ${pulse.trend}` : `score ${pulse.score}`, pulse.headline].filter(Boolean).join(" · "),
      nodeRequest: pulse.theater ? { kind: "theater", id: pulse.theater } : null,
    }))
    ;(cp.risk_factors || []).slice(0, 6).forEach(risk => pressureItems.push({ label: risk, meta: "risk factor" }))

    return {
      kind: "chokepoint",
      severity: cp.status === "critical" ? "critical" : cp.status === "elevated" ? "high" : cp.status === "monitoring" ? "medium" : "low",
      statusLabel: cp.status || "monitoring",
      icon: "fa-anchor",
      accentColor: { critical: "#f44336", elevated: "#ff9800", monitoring: "#ffc107", normal: "#4fc3f7" }[cp.status] || "#4fc3f7",
      eyebrow: "STRATEGIC NODE",
      title: cp.name || "Chokepoint",
      subtitle: cp.status ? cp.status.toUpperCase() : "",
      summary: cp.description || "",
      meta: [
        cp.ships_nearby?.total != null ? { label: "Ships", value: `${cp.ships_nearby.total}` } : null,
        cp.ships_nearby?.tankers != null ? { label: "Tankers", value: `${cp.ships_nearby.tankers}` } : null,
        this._chokepointSnapshotStatus ? { label: "Snapshot", value: this._statusLabel(this._chokepointSnapshotStatus, "snapshot") } : null,
      ].filter(Boolean),
      coordinates: Number.isFinite(cp.lat) && Number.isFinite(cp.lng)
        ? { lat: cp.lat, lng: cp.lng, height: 1000000 }
        : null,
      actions: cp.lat != null && cp.lng != null ? [
        { label: "Focus", lat: cp.lat, lng: cp.lng, height: 1000000, icon: "fa-location-crosshairs" },
      ] : [],
      nodeRequest: cp.name ? { kind: "chokepoint", id: cp.name } : null,
      sections: [
        flowRows.length ? { title: "Flows", rows: flowRows } : null,
        marketChips.length ? { title: "Market signals", chips: marketChips } : null,
        marketItems.length ? { title: "Market context", items: marketItems } : null,
        pressureItems.length ? { title: "Pressure", items: pressureItems } : null,
      ].filter(Boolean),
    }
  }
}
