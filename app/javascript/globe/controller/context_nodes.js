export function applyContextNodeMethods(GlobeController) {
  GlobeController.prototype._caseIntakePathForPayload = function(payload = {}) {
    if (!payload?.object_kind || !payload?.object_identifier || !payload?.title) return null

    const params = new URLSearchParams()
    Object.entries(payload).forEach(([key, value]) => {
      if (key === "source_context") return
      if (value === undefined || value === null || value === "") return
      params.set(`source_object[${key}]`, `${value}`)
    })

    Object.entries(payload.source_context || {}).forEach(([key, value]) => {
      if (value === undefined || value === null || value === "") return
      params.set(`source_object[source_context][${key}]`, `${value}`)
    })

    return `/cases/new?${params.toString()}`
  }

  GlobeController.prototype._caseSourcePayloadForInsight = function(insight) {
    if (!insight) return null

    const entities = insight.entities || {}
    const theaterName = entities.theater?.name || entities.pulse?.theater || null
    const preferredNode = entities.primary_node?.kind && entities.primary_node?.id
      ? { kind: entities.primary_node.kind, id: entities.primary_node.id }
      : null
    const nodeRequest = preferredNode || (entities.chokepoint?.name
      ? { kind: "chokepoint", id: entities.chokepoint.name }
      : theaterName
        ? { kind: "theater", id: theaterName }
        : null)

    const detectedAt = insight.detected_at || insight.created_at || "undated"
    const objectKind = nodeRequest?.kind || "insight"
    const objectIdentifier = nodeRequest?.id || `${insight.type || "insight"}:${detectedAt}:${insight.title || "signal"}`
    const objectType = nodeRequest ? nodeRequest.kind : (insight.type || "insight")

    return {
      object_kind: objectKind,
      object_identifier: objectIdentifier,
      title: insight.title || "Insight",
      summary: insight.description || "",
      object_type: objectType,
      latitude: Number.isFinite(insight.lat) ? insight.lat : null,
      longitude: Number.isFinite(insight.lng) ? insight.lng : null,
      source_context: {
        severity: insight.severity || "medium",
        insight_type: insight.type,
        detected_at: insight.detected_at,
        theater: theaterName,
      },
    }
  }

  GlobeController.prototype._caseSourcePayloadForTheater = function(zoneLike) {
    const zone = typeof zoneLike === "string" ? (this._findConflictZoneForTheater(zoneLike) || { theater: zoneLike }) : (zoneLike || {})
    const theaterIdentifier = zone.theater || (typeof zoneLike === "string" ? zoneLike : null)
    const theaterName = theaterIdentifier || zone.situation_name || zone.name
    if (!theaterName) return null

    const pulseScore = zone.pulse_score || zone.score || 0
    const severity = pulseScore >= 80 ? "critical" : pulseScore >= 60 ? "high" : pulseScore >= 40 ? "medium" : "low"

    return {
      object_kind: "theater",
      object_identifier: theaterIdentifier || theaterName,
      title: theaterName,
      summary: [zone.situation_name, zone.escalation_trend, zone.count_24h ? `${zone.count_24h} reports / 24h` : null].filter(Boolean).join(" · "),
      object_type: "theater",
      latitude: Number.isFinite(zone.lat) ? zone.lat : null,
      longitude: Number.isFinite(zone.lng) ? zone.lng : null,
      source_context: {
        severity,
        pulse_score: pulseScore,
        escalation_trend: zone.escalation_trend || zone.trend,
        story_count: zone.story_count,
        source_count: zone.source_count,
      },
    }
  }

  GlobeController.prototype._focusContextNode = function(nodeRequest, fallback = {}) {
    if (!nodeRequest?.kind || !nodeRequest?.id) return

    if (nodeRequest.kind === "theater") {
      const zone = this._findConflictZoneForTheater(nodeRequest.id)
      if (zone) {
        this._setTheaterSelectedContext(nodeRequest.id, zone)
      } else {
        this._setSelectedContext(this._buildGenericNodeContext(nodeRequest, fallback))
      }
      return
    }

    if (nodeRequest.kind === "chokepoint") {
      const chokepoint = this._findChokepointById(nodeRequest.id)
      if (chokepoint) {
        this._setSelectedContext(this._buildChokepointContext(chokepoint))
        return
      }
      this._setSelectedContext(this._buildGenericNodeContext(nodeRequest, fallback))
      return
    }

    if (nodeRequest.kind === "news_story_cluster") {
      const story = (this._newsData || []).find(item => `${item.cluster_id || ""}` === `${nodeRequest.id}`)
      if (story) {
        this._setSelectedContext(this._buildNewsContext(story))
        return
      }
      this._setSelectedContext(this._buildGenericNodeContext(nodeRequest, fallback))
      return
    }

    if (nodeRequest.kind === "commodity") {
      const commodity = this._findCommodityById(nodeRequest.id)
      this._setSelectedContext(this._buildCommodityContext(commodity || fallback, nodeRequest))
      return
    }

    if (nodeRequest.kind === "entity") {
      this._setSelectedContext(this._buildGenericNodeContext(nodeRequest, fallback))
      return
    }

    this._setSelectedContext(this._buildGenericNodeContext(nodeRequest, fallback))
  }

  GlobeController.prototype._normalizeContextIdentifier = function(value) {
    return (value || "")
      .toString()
      .trim()
      .toLowerCase()
  }

  GlobeController.prototype._findChokepointById = function(identifier) {
    const raw = this._normalizeContextIdentifier(identifier)
    return (this._chokepointData || []).find(cp => {
      const candidates = [
        cp.id,
        cp.name,
        cp.name?.replace(/\s+/g, "_"),
      ].filter(Boolean)
      return candidates.some(candidate => this._normalizeContextIdentifier(candidate) === raw)
    }) || null
  }

  GlobeController.prototype._findCommodityById = function(identifier) {
    const raw = this._normalizeContextIdentifier(identifier)
    const marketItems = [...(this._commodityData || []), ...(this._marketBenchmarkData || [])]
    return marketItems.find(item => {
      const candidates = [
        item.symbol,
        item.name,
        item.symbol ? `commodity:${item.symbol.toLowerCase()}` : null,
      ].filter(Boolean)
      return candidates.some(candidate => this._normalizeContextIdentifier(candidate) === raw)
    }) || null
  }

  GlobeController.prototype._nodeRequestForGraphNode = function(node) {
    if (!node) return null

    if (node.node_type === "entity") {
      if (node.entity_type === "theater") return { kind: "theater", id: node.canonical_key || node.name }
      if (node.entity_type === "commodity") return { kind: "commodity", id: node.canonical_key || node.name }
      if (node.entity_type === "corridor" && node.canonical_key?.startsWith("corridor:chokepoint:")) {
        return { kind: "chokepoint", id: node.canonical_key.split(":").pop() }
      }
      if (node.canonical_key) return { kind: "entity", id: node.canonical_key }
    }

    if (node.node_type === "event" && node.canonical_key?.startsWith("news-story-cluster:")) {
      return { kind: "news_story_cluster", id: node.canonical_key.replace(/^news-story-cluster:/, "") }
    }

    return null
  }

  GlobeController.prototype._nodeRequestForEvidence = function(item) {
    if (!item) return null
    if (item.type === "news_story_cluster" && item.cluster_key) {
      return { kind: "news_story_cluster", id: item.cluster_key }
    }
    if (item.type === "commodity_price" && item.symbol) {
      return { kind: "commodity", id: item.symbol }
    }
    return null
  }

  GlobeController.prototype._buildGenericNodeContext = function(nodeRequest, fallback = {}) {
    return {
      kind: "graph",
      severity: "medium",
      icon: fallback.icon || "fa-circle-nodes",
      accentColor: fallback.accentColor || "#4fc3f7",
      eyebrow: fallback.eyebrow || "GRAPH CONTEXT",
      title: fallback.title || nodeRequest.id,
      subtitle: fallback.subtitle || "",
      summary: fallback.summary || "Loading durable graph context for this node.",
      meta: [],
      actions: [],
      nodeRequest,
      coordinates: Number.isFinite(fallback.lat) && Number.isFinite(fallback.lng)
        ? { lat: fallback.lat, lng: fallback.lng, height: fallback.height || 450000 }
        : null,
      sections: [],
    }
  }

  GlobeController.prototype._findConflictZoneForTheater = function(theater) {
    if (!theater) return null

    const zones = [...(this._conflictPulseZones || []), ...(this._conflictPulseData || [])]
      .filter(zone => zone?.theater === theater)

    if (!zones.length) return null

    return zones.sort((a, b) => {
      const pulseDiff = (b.pulse_score || 0) - (a.pulse_score || 0)
      if (pulseDiff !== 0) return pulseDiff
      return (b.count_24h || 0) - (a.count_24h || 0)
    })[0]
  }

  GlobeController.prototype._setTheaterSelectedContext = function(theater, zone = null) {
    if (!theater || !this._buildTheaterContext || !this._setSelectedContext) return

    const resolvedZone = zone || this._findConflictZoneForTheater(theater) || { theater }
    this._setSelectedContext(this._buildTheaterContext(resolvedZone))
  }

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
      icon: "fa-newspaper",
      accentColor: color,
      eyebrow: "NEWS CONTEXT",
      title: ev.title || ev.name || "Story cluster",
      subtitle: location || "Unknown location",
      summary: summaryBits.join(" · "),
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
      icon: "fa-brain",
      accentColor: { critical: "#f44336", high: "#ff9800", medium: "#ffc107", low: "#4caf50" }[insight.severity || "medium"],
      eyebrow: "CROSS-LAYER INSIGHT",
      title: insight.title || "Insight",
      subtitle: insight.type ? insight.type.replace(/_/g, " ") : "",
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
    const signals = zone.cross_layer_signals || {}
    const signalChips = []
    const reportingItems = []
    const summaryBits = []

    if (zone.count_24h) summaryBits.push(`${zone.count_24h} reports / 24h`)
    if (zone.source_count) summaryBits.push(`${zone.source_count} sources`)
    if (trend) summaryBits.push(trend)

    if (signals.military_flights) signalChips.push({ label: `${signals.military_flights} military flights`, variant: "flight" })
    if (signals.gps_jamming) signalChips.push({ label: `${signals.gps_jamming}% jamming`, variant: "jam" })
    if (signals.internet_outage) signalChips.push({ label: `outage: ${signals.internet_outage}`, variant: "outage" })
    if (signals.fire_hotspots) signalChips.push({ label: `${signals.fire_hotspots} fires`, variant: "fire" })
    if (signals.known_conflict_zone) signalChips.push({ label: `${signals.known_conflict_zone} historical incidents`, variant: "conf" })

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

    return {
      kind: "theater",
      severity: pulseScore >= 80 ? "critical" : pulseScore >= 60 ? "high" : pulseScore >= 40 ? "medium" : "low",
      icon: "fa-layer-group",
      accentColor: pulseScore >= 80 ? "#f44336" : pulseScore >= 60 ? "#ff9800" : pulseScore >= 40 ? "#ffc107" : "#4fc3f7",
      eyebrow: "THEATER CONTEXT",
      title: theaterName,
      subtitle: theaterIdentifier && zone.situation_name ? zone.situation_name : "Regional pressure and corroborating signals",
      summary: summaryBits.join(" · ") || "Durable relationships and supporting reporting for this theater.",
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
      sections: [
        signalChips.length ? { title: "Signals", chips: signalChips } : null,
        reportingItems.length ? { title: "Reporting", items: reportingItems } : null,
      ].filter(Boolean),
    }
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
