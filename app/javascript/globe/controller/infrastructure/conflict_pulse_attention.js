const ATTENTION_STATES = {
  armed_conflict_critical: {
    severity: "critical",
    label: "Severe armed conflict",
    fill: "#7f1d1d",
    stroke: "#ef4444",
    text: "#fecaca",
    alpha: 0.42,
  },
  armed_conflict_active: {
    severity: "high",
    label: "Active armed conflict",
    fill: "#9a3412",
    stroke: "#fb923c",
    text: "#fed7aa",
    alpha: 0.34,
  },
  strategic_pressure: {
    severity: "high",
    label: "Strategic pressure",
    fill: "#92400e",
    stroke: "#f59e0b",
    text: "#fde68a",
    alpha: 0.36,
  },
  security_disruption_high: {
    severity: "high",
    label: "High disruption",
    fill: "#854d0e",
    stroke: "#facc15",
    text: "#fef08a",
    alpha: 0.26,
  },
  elevated_attention: {
    severity: "elevated",
    label: "Elevated attention",
    fill: "#475569",
    stroke: "#cbd5e1",
    text: "#e2e8f0",
    alpha: 0.16,
  },
  watch: {
    severity: "watch",
    label: "Watch",
    fill: "#334155",
    stroke: "#94a3b8",
    text: "#cbd5e1",
    alpha: 0.07,
  },
}

const CONTEXT_LABELS = {
  kinetic_conflict: "Armed conflict",
  strategic_pressure: "Strategic corridor pressure",
  public_order_or_security: "Public order / security",
}

const CONTEXT_CODES = {
  kinetic_conflict: "WAR",
  strategic_pressure: "FLOW",
  public_order_or_security: "SEC",
}

function toNumber(value) {
  const numeric = Number(value || 0)
  return Number.isFinite(numeric) ? numeric : 0
}

export function attentionContext(zone) {
  if (zone?.attention_state === "strategic_pressure") return "strategic_pressure"
  return zone?.analysis_context || "public_order_or_security"
}

export function attentionContextLabel(zone) {
  return CONTEXT_LABELS[attentionContext(zone)] || "Security / disruption"
}

export function attentionContextCode(zone) {
  return CONTEXT_CODES[attentionContext(zone)] || "OBS"
}

export function attentionAnchorLabel(zone) {
  const code = attentionContextCode(zone)
  const reports = toNumber(zone?.count_24h)
  const weighted = toNumber(zone?.weighted_24h)
  const sources = toNumber(zone?.source_count)
  const activity = Math.round(reports || weighted || sources || 0)

  return activity > 0 ? `${code} ${activity}` : code
}

export function isArmedConflictAttention(zone) {
  return attentionContext(zone) === "kinetic_conflict"
}

export function attentionState(zone) {
  if (zone?.attention_state && ATTENTION_STATES[zone.attention_state]) return zone.attention_state

  const score = toNumber(zone?.pulse_score)
  const weighted24h = toNumber(zone?.weighted_24h)
  const signals = zone?.cross_layer_signals || {}
  const armed = isArmedConflictAttention(zone)
  const strikeEvidence = toNumber(signals.verified_strike_reports_7d) > 0 || toNumber(signals.strike_signals_7d) > 0

  if (armed && (strikeEvidence || score >= 90 || weighted24h >= 20)) return "armed_conflict_critical"
  if (armed && (score >= 55 || toNumber(signals.known_conflict_zone) > 0)) return "armed_conflict_active"
  if (score >= 80) return "security_disruption_high"
  if (score >= 55) return "elevated_attention"
  return "watch"
}

export function attentionSeverityLabel(zone) {
  return ATTENTION_STATES[attentionState(zone)]?.label || ATTENTION_STATES.watch.label
}

export function attentionSeverity(zone) {
  return ATTENTION_STATES[attentionState(zone)]?.severity || "watch"
}

export function attentionPalette(zone) {
  const state = ATTENTION_STATES[attentionState(zone)] || ATTENTION_STATES.watch
  return {
    fill: state.fill,
    stroke: state.stroke,
    label: state.text,
  }
}

export function attentionSurfaceAlpha(zone) {
  return ATTENTION_STATES[attentionState(zone)]?.alpha || ATTENTION_STATES.watch.alpha
}

export function shouldRenderAttentionSurface(zone, rank = 0) {
  const score = Number(zone?.pulse_score || 0)
  if (rank < 10 && score >= 35) return true
  if (score >= 55) return true
  if (isArmedConflictAttention(zone) && score >= 30) return true
  return false
}

export function attentionEvidenceItems(zone) {
  const items = []
  const signals = zone?.cross_layer_signals || {}
  const contextLabel = attentionContextLabel(zone).toLowerCase()

  if (zone?.strategic_context?.name) items.push({ key: "strategic_context", label: `${zone.strategic_context.name} strategic node` })
  if (zone?.count_24h) items.push({ key: "reports", label: `${zone.count_24h} reports in 24h` })
  if (zone?.source_count) items.push({ key: "sources", label: `${zone.source_count} sources` })
  if (Number(zone?.spike_ratio || 0) >= 1.5) items.push({ key: "spike", label: `${zone.spike_ratio}x reporting spike` })
  items.push({ key: "context", label: `${contextLabel} context` })

  if (Number(signals.verified_strike_reports_7d || 0) > 0) {
    items.push({ key: "verified_strikes", label: `${signals.verified_strike_reports_7d} verified strike reports in 7d` })
  }
  if (Number(signals.strike_signals_7d || 0) > 0) {
    items.push({ key: "strike_signals", label: `${signals.strike_signals_7d} strike-linked signals in 7d` })
  }
  if (signals.military_flights) items.push({ key: "military_flights", label: `${signals.military_flights} military flights nearby` })
  if (signals.gps_jamming) items.push({ key: "gps_jamming", label: `${signals.gps_jamming}% GPS interference nearby` })
  if (signals.internet_outage) items.push({ key: "internet_outage", label: `major internet outage: ${signals.internet_outage}` })
  if (signals.fire_hotspots && isArmedConflictAttention(zone)) items.push({ key: "fire_hotspots", label: `${signals.fire_hotspots} fire hotspots near conflict area` })
  if (signals.known_conflict_zone) items.push({ key: "known_conflict_zone", label: `${signals.known_conflict_zone} historical conflict records nearby` })

  return items
}

export function attentionAssessment(zone) {
  const name = zone?.situation_name || zone?.theater || "This region"
  const severity = attentionSeverityLabel(zone).toLowerCase()
  const evidence = attentionEvidenceItems(zone).slice(0, 4).map(item => item.label).join(", ")
  const evidenceText = evidence || "recent reporting"

  if (attentionState(zone) === "strategic_pressure") {
    const strategicName = zone?.strategic_context?.name || name
    return `${name} is shaded as ${severity}, not as a second war region. The read is connected to ${strategicName} and driven by ${evidenceText}.`
  }

  if (isArmedConflictAttention(zone)) {
    return `${name} is shaded as ${severity}. The read is driven by ${evidenceText}; strike and fire layers are only used because this is classified as an armed-conflict context.`
  }

  return `${name} is shaded for ${severity}, not as a war zone. The read is driven by ${evidenceText}; strike and fire layers are not treated as corroboration unless the context changes to armed conflict.`
}

function normalizeName(value) {
  return `${value || ""}`.trim().toLowerCase()
}

function approxDistanceKm(a, b) {
  const lat1 = Number(a?.lat)
  const lng1 = Number(a?.lng)
  const lat2 = Number(b?.lat)
  const lng2 = Number(b?.lng)
  if (![lat1, lng1, lat2, lng2].every(Number.isFinite)) return Number.POSITIVE_INFINITY

  const dlat = (lat1 - lat2) * 111
  const meanLat = ((lat1 + lat2) / 2) * Math.PI / 180
  const dlng = (lng1 - lng2) * 111 * Math.max(Math.cos(meanLat), 0.1)
  return Math.sqrt(dlat ** 2 + dlng ** 2)
}

function strategicMatchForZone(zone, strategicSituations) {
  const zoneName = normalizeName(zone?.situation_name)
  const candidates = Array.isArray(strategicSituations) ? strategicSituations : []

  return candidates.find(item => {
    if (!["critical", "elevated"].includes(`${item?.status || ""}`)) return false
    if (zoneName && normalizeName(item?.name) === zoneName) return true
    return approxDistanceKm(zone, item) <= 180
  })
}

export function decorateAttentionZones(zones = [], strategicSituations = []) {
  return zones.map(zone => {
    const strategic = strategicMatchForZone(zone, strategicSituations)
    if (!strategic) return zone

    return {
      ...zone,
      attention_state: "strategic_pressure",
      strategic_context: {
        id: strategic.id || strategic.node_id || strategic.name,
        name: strategic.name,
        status: strategic.status,
        score: strategic.strategic_score,
      },
    }
  })
}
