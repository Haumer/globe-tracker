import { encodeState } from "globe/deeplinks"

export function applyContextNodeCasePayloadMethods(GlobeController) {
  GlobeController.prototype._caseReturnToGlobePath = function(payload = {}) {
    const params = new URLSearchParams()

    if (payload?.object_kind && payload?.object_identifier) {
      params.set("focus_kind", `${payload.object_kind}`)
      params.set("focus_id", `${payload.object_identifier}`)
      if (payload.title) params.set("focus_title", `${payload.title}`)
    }

    const hash = encodeState(this) || window.location.hash || ""
    const query = params.toString()
    return `/${query ? `?${query}` : ""}${hash}`
  }

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

    const returnTo = this._caseReturnToGlobePath(payload)
    if (returnTo) params.set("return_to", returnTo)

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
        cell_key: zone.cell_key,
        pulse_score: pulseScore,
        escalation_trend: zone.escalation_trend || zone.trend,
        count_24h: zone.count_24h,
        story_count: zone.story_count,
        source_count: zone.source_count,
        spike_ratio: zone.spike_ratio,
        detected_at: zone.detected_at,
        situation_name: zone.situation_name,
      },
    }
  }

  GlobeController.prototype._caseSourcePayloadForStrike = function(strike = {}) {
    const identifier = strike.id || strike.external_id || [strike.lat, strike.lng, strike.time].filter(Boolean).join(":")
    if (!identifier) return null

    const isVerified = strike?.detectionKind === "verified_strike" || strike.strikeConfidence === "verified" || !!strike.gcMatch
    const sourceUrls = Array.isArray(strike?.gcMatch?.source_urls) ? strike.gcMatch.source_urls : []

    return {
      object_kind: "strike",
      object_identifier: `${identifier}`,
      title: isVerified ? (strike.gcMatch?.title || "Verified strike") : "Heat signature",
      summary: [
        strike.gcMatch?.region || strike.location_name,
        strike.satellite,
        strike.time ? this._timeAgo(new Date(strike.time)) : null,
      ].filter(Boolean).join(" · "),
      object_type: isVerified ? "strike" : "heat_signature",
      latitude: Number.isFinite(strike.lat) ? strike.lat : null,
      longitude: Number.isFinite(strike.lng) ? strike.lng : null,
      source_context: {
        severity: isVerified ? "high" : "medium",
        strike_confidence: strike.strikeConfidence,
        detection_kind: strike.detectionKind || (isVerified ? "verified_strike" : "heat_signature"),
        frp: strike.frp,
        brightness: strike.brightness,
        satellite: strike.satellite,
        instrument: strike.instrument,
        gc_region: strike.gcMatch?.region,
        gc_source_url: strike.gcMatch?.source_url,
        gc_source_count: sourceUrls.length || null,
        detected_at: strike.time,
      },
    }
  }
}
