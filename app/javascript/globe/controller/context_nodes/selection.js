export function applyContextNodeSelectionMethods(GlobeController) {
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
      if (typeof this.showChokepointDetail === "function") {
        this.showChokepointDetail(nodeRequest.id, { contextOnly: true })
        return
      }
      this._setSelectedContext(this._buildGenericNodeContext(nodeRequest, fallback))
      return
    }

    if (nodeRequest.kind === "pipeline") {
      if (typeof this.showPipelineDetail === "function") {
        this.showPipelineDetail(nodeRequest.id)
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
}
