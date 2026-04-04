export function applyContextNodeCasePayloadMethods(GlobeController) {
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
}
