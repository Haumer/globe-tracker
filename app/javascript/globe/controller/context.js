export function applyContextMethods(GlobeController) {
  GlobeController.prototype._setSelectedContext = function(context) {
    this._selectedContext = context || null
    this._selectedContextRequestKey = context?.nodeRequest
      ? `${context.nodeRequest.kind}:${context.nodeRequest.id}`
      : null
    if (this._selectedContext?.nodeRequest) {
      this._selectedContext.nodeContextStatus = "loading"
      this._selectedContext.nodeContext = null
      this._loadSelectedContextNode(this._selectedContext.nodeRequest, this._selectedContextRequestKey)
    }
    this._renderSelectedContext()
    if (context) this._showRightPanel("context")
    else if (this._syncRightPanels) this._syncRightPanels()
  }

  GlobeController.prototype._loadSelectedContextNode = async function(nodeRequest, requestKey) {
    try {
      const params = new URLSearchParams({
        kind: nodeRequest.kind,
        id: nodeRequest.id,
      })
      const resp = await fetch(`/api/node_context?${params.toString()}`)
      if (!this._selectedContext || this._selectedContextRequestKey !== requestKey) return

      if (!resp.ok) {
        this._selectedContext.nodeContextStatus = "error"
        this._renderSelectedContext()
        return
      }

      this._selectedContext.nodeContext = await resp.json()
      this._selectedContext.nodeContextStatus = "ready"
      this._renderSelectedContext()
    } catch (_error) {
      if (!this._selectedContext || this._selectedContextRequestKey !== requestKey) return
      this._selectedContext.nodeContextStatus = "error"
      this._renderSelectedContext()
    }
  }

  GlobeController.prototype._renderSelectedContext = function() {
    if (!this.hasContextContentTarget) return

    const context = this._selectedContext
    if (!context) {
      this.contextContentTarget.innerHTML = '<div class="insight-empty">Select a story, theater, insight, or strategic node to inspect related evidence here.</div>'
      return
    }

    const meta = (context.meta || [])
      .filter(item => item?.value)
      .map(item => `
        <div class="detail-field">
          <span class="detail-label">${this._escapeHtml(item.label)}</span>
          <span class="detail-value">${this._escapeHtml(item.value)}</span>
        </div>
      `)
      .join("")

    const sections = [...(context.sections || []), ...this._durableContextSections(context)]
      .map(section => this._renderContextSection(section))
      .join("")

    const actions = (context.actions || [])
      .map(action => this._renderContextAction(action))
      .join("")

    this.contextContentTarget.innerHTML = `
      <div class="insight-card insight-card--${this._escapeHtml(context.severity || "medium")}">
        <div class="insight-card-severity">
          <i class="fa-solid ${this._escapeHtml(context.icon || "fa-circle-info")}" style="color:${this._escapeHtml(context.accentColor || "#4fc3f7")};"></i>
        </div>
        <div class="insight-card-body">
          <div class="insight-card-type">${this._escapeHtml(context.eyebrow || "CONTEXT")}</div>
          <div class="insight-card-title">${this._escapeHtml(context.title || "Selected context")}</div>
          ${context.subtitle ? `<div class="insight-card-desc" style="margin-top:4px;color:rgba(226,232,240,0.78);">${this._escapeHtml(context.subtitle)}</div>` : ""}
          ${context.summary ? `<div class="insight-card-desc">${this._escapeHtml(context.summary)}</div>` : ""}
          ${meta ? `<div class="detail-grid" style="margin-top:10px;">${meta}</div>` : ""}
          ${actions ? `<div class="insight-card-actions" style="margin-top:10px;">${actions}</div>` : ""}
          ${sections}
        </div>
      </div>
    `
  }

  GlobeController.prototype._renderContextSection = function(section) {
    if (!section) return ""

    const rows = (section.rows || [])
      .filter(row => row?.value)
      .map(row => `
        <div style="display:flex;justify-content:space-between;gap:10px;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
          <span style="font:600 10px var(--gt-mono);color:rgba(200,210,225,0.6);text-transform:uppercase;letter-spacing:0.6px;">${this._escapeHtml(row.label)}</span>
          <span style="font:500 11px 'DM Sans',sans-serif;color:#f8fafc;text-align:right;">${this._escapeHtml(row.value)}</span>
        </div>
      `)
      .join("")

    const items = (section.items || [])
      .filter(item => item?.label)
      .map(item => {
        const itemBody = `
          <div style="font:500 11px 'DM Sans',sans-serif;color:#f8fafc;line-height:1.35;">${this._escapeHtml(item.label)}</div>
          ${item.meta ? `<div style="font:500 9px var(--gt-mono);color:rgba(200,210,225,0.45);margin-top:2px;">${this._escapeHtml(item.meta)}</div>` : ""}
        `

        if (item.nodeRequest?.kind && item.nodeRequest?.id) {
          return `
            <div style="padding:6px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
              <button
                type="button"
                data-action="click->globe#selectContextNode"
                data-kind="${this._escapeHtml(item.nodeRequest.kind)}"
                data-id="${this._escapeHtml(item.nodeRequest.id)}"
                data-title="${this._escapeHtml(item.label)}"
                data-summary="${this._escapeHtml(item.meta || "")}"
                style="display:block;width:100%;padding:0;border:0;background:none;text-align:left;cursor:pointer;"
              >
                ${itemBody}
              </button>
            </div>
          `
        }

        if (item.url) {
          return `
            <div style="padding:6px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
              <a href="${this._safeUrl(item.url)}" target="_blank" rel="noopener" style="display:block;text-decoration:none;">
                ${itemBody}
              </a>
            </div>
          `
        }

        return `
          <div style="padding:6px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
            ${itemBody}
          </div>
        `
      })
      .join("")

    const chips = (section.chips || [])
      .filter(Boolean)
      .map(chip => `<span class="ins-chip ins-chip--${this._escapeHtml(chip.variant || "eq")}">${this._escapeHtml(chip.label)}</span>`)
      .join("")

    const body = rows || items || chips || section.html || ""
    if (!body) return ""

    return `
      <div style="margin-top:12px;">
        <div style="font:600 9px var(--gt-mono);color:rgba(200,210,225,0.45);letter-spacing:1px;text-transform:uppercase;margin-bottom:6px;">
          ${this._escapeHtml(section.title || "Section")}
        </div>
        ${chips ? `<div class="insight-card-chips">${chips}</div>` : ""}
        ${rows || items ? `<div>${rows || items}</div>` : ""}
        ${section.html || ""}
      </div>
    `
  }

  GlobeController.prototype._durableContextSections = function(context) {
    if (!context?.nodeRequest) return []
    if (context.nodeContextStatus === "loading") {
      return [{ title: "Graph context", html: '<div class="insight-empty">Loading durable node context…</div>' }]
    }
    if (context.nodeContextStatus === "error") {
      return [{ title: "Graph context", html: '<div class="insight-empty">Durable node context is unavailable for this selection.</div>' }]
    }
    if (context.nodeContextStatus !== "ready" || !context.nodeContext) return []

    const payload = context.nodeContext
    const sections = []

    if ((payload.memberships || []).length) {
      sections.push({
        title: "Canonical actors",
        items: payload.memberships.map(membership => ({
          label: membership.node?.name || membership.role,
          meta: [membership.role, membership.confidence != null ? `${Math.round(membership.confidence * 100)}%` : null].filter(Boolean).join(" · "),
          nodeRequest: this._nodeRequestForGraphNode(membership.node),
        })),
      })
    }

    if ((payload.evidence || []).length) {
      sections.push({
        title: "Durable evidence",
        items: payload.evidence.map(item => ({
          label: item.label,
          meta: [item.role, item.meta].filter(Boolean).join(" · "),
          nodeRequest: this._nodeRequestForEvidence(item),
          url: item.url,
        })),
      })
    }

    if ((payload.relationships || []).length) {
      sections.push({
        title: "Relationships",
        items: payload.relationships.map(rel => ({
          label: rel.node?.name || rel.relation_type,
          meta: [
            rel.relation_type?.replace(/_/g, " "),
            rel.confidence != null ? `${Math.round(rel.confidence * 100)}%` : null,
            rel.evidence?.length ? rel.evidence.map(ev => ev.label).filter(Boolean).slice(0, 2).join(" · ") : null,
          ].filter(Boolean).join(" · "),
          nodeRequest: this._nodeRequestForGraphNode(rel.node),
        })),
      })
    }

    return sections
  }

  GlobeController.prototype._renderContextAction = function(action) {
    if (action.url) {
      return `<a class="insight-action-btn" href="${this._safeUrl(action.url)}" target="_blank" rel="noopener"><i class="fa-solid ${this._escapeHtml(action.icon || "fa-arrow-up-right-from-square")}"></i> ${this._escapeHtml(action.label)}</a>`
    }

    if (action.lat != null && action.lng != null) {
      return `<button class="insight-action-btn" data-action="click->globe#focusContextLocation" data-lat="${action.lat}" data-lng="${action.lng}" data-height="${action.height || 500000}"><i class="fa-solid ${this._escapeHtml(action.icon || "fa-location-crosshairs")}"></i> ${this._escapeHtml(action.label)}</button>`
    }

    return ""
  }

  GlobeController.prototype.focusContextLocation = function(event) {
    const lat = parseFloat(event.currentTarget.dataset.lat)
    const lng = parseFloat(event.currentTarget.dataset.lng)
    const height = parseFloat(event.currentTarget.dataset.height || "500000")
    if (isNaN(lat) || isNaN(lng)) return

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lng, lat, height),
      duration: 1.2,
    })
  }

  GlobeController.prototype.selectContextNode = function(event) {
    const kind = event.currentTarget.dataset.kind
    const id = event.currentTarget.dataset.id
    if (!kind || !id) return

    this._focusContextNode(
      { kind, id },
      {
        title: event.currentTarget.dataset.title,
        summary: event.currentTarget.dataset.summary,
      }
    )
  }

  GlobeController.prototype._focusContextNode = function(nodeRequest, fallback = {}) {
    if (!nodeRequest?.kind || !nodeRequest?.id) return

    if (nodeRequest.kind === "theater") {
      this._setTheaterSelectedContext(nodeRequest.id)
      return
    }

    if (nodeRequest.kind === "chokepoint") {
      const chokepoint = this._findChokepointById(nodeRequest.id)
      if (chokepoint) {
        this._setSelectedContext(this._buildChokepointContext(chokepoint))
        return
      }
    }

    if (nodeRequest.kind === "news_story_cluster") {
      const story = (this._newsData || []).find(item => `${item.cluster_id || ""}` === `${nodeRequest.id}`)
      if (story) {
        this._setSelectedContext(this._buildNewsContext(story))
        return
      }
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
    return (this._commodityData || []).find(item => {
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
      actions: insight.lat != null && insight.lng != null ? [
        { label: "Focus", lat: insight.lat, lng: insight.lng, height: 500000, icon: "fa-location-crosshairs" },
      ] : [],
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
      actions: zone.lat != null && zone.lng != null ? [
        { label: "Focus", lat: zone.lat, lng: zone.lng, height: 1200000, icon: "fa-location-crosshairs" },
      ] : [],
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
