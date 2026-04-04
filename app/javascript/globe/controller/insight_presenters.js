const INSIGHT_SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, low: 3 }

const INSIGHT_SEVERITY_ICONS = {
  critical: "fa-circle-exclamation",
  high: "fa-triangle-exclamation",
  medium: "fa-circle-info",
  low: "fa-circle-check",
}

export const INSIGHT_SEVERITY_COLORS = {
  critical: "#f44336",
  high: "#ff9800",
  medium: "#ffc107",
  low: "#4caf50",
}

export const INSIGHT_TYPE_ICONS = {
  earthquake_infrastructure: "\u26A0",
  earthquake_pipeline: "\u26A0",
  jamming_flights: "\u{1F4E1}",
  electronic_warfare: "\u{1F4E1}",
  conflict_military: "\u2694",
  fire_infrastructure: "\u{1F525}",
  fire_pipeline: "\u{1F525}",
  cable_outage: "\u{1F50C}",
  outage_currency_stress: "\u{1F4B1}",
  emergency_squawk: "\u{1F6A8}",
  ship_cable_proximity: "\u2693",
  information_blackout: "\u{1F50C}",
  airspace_clearing: "\u{2708}",
  weather_disruption: "\u26C8",
  conflict_pulse: "\u{1F4A5}",
  chokepoint_disruption: "\u2693",
  chokepoint_market_stress: "\u{1F4C8}",
  supply_chain_vulnerability: "\u2699",
  country_chokepoint_dependency: "\u26FD",
  convergence: "\u{1F310}",
}

const INSIGHT_TYPE_LABELS = {
  earthquake_infrastructure: "QUAKE + INFRA",
  earthquake_pipeline: "QUAKE + PIPELINE",
  jamming_flights: "JAMMING + AIR",
  electronic_warfare: "ELECTRONIC WARFARE",
  conflict_military: "CONFLICT + MIL",
  fire_infrastructure: "FIRE + INFRA",
  fire_pipeline: "FIRE + PIPELINE",
  cable_outage: "OUTAGE + CABLE",
  outage_currency_stress: "OUTAGE + FX",
  emergency_squawk: "EMERGENCY SQUAWK",
  ship_cable_proximity: "SHIP + CABLE",
  information_blackout: "INFO BLACKOUT",
  airspace_clearing: "AIRSPACE + MIL",
  weather_disruption: "WEATHER + AIR",
  conflict_pulse: "DEVELOPING",
  chokepoint_disruption: "CHOKEPOINT",
  chokepoint_market_stress: "CHOKEPOINT + MARKET",
  supply_chain_vulnerability: "SUPPLY CHAIN",
  country_chokepoint_dependency: "COUNTRY + ROUTE",
  convergence: "CONVERGENCE",
}

const CONVERGENCE_LAYER_CHIP_COLORS = {
  earthquake: "eq",
  fire: "fire",
  conflict: "conf",
  military_flight: "flight",
  jamming: "jam",
  natural_event: "event",
  news: "news",
  nuclear_plant: "plant",
  submarine_cable: "cable",
}

export function renderInsightFeedHtml(controller, insights, snapshotStatus) {
  const statusBanner = snapshotStatus === "ready"
    ? ""
    : `<div style="margin-bottom:10px;display:flex;align-items:center;gap:6px;flex-wrap:wrap;">${controller._statusChip(snapshotStatus, controller._statusLabel(snapshotStatus, "snapshot"))}</div>`

  const sortedInsights = insights
    .map((insight, idx) => ({ insight, idx }))
    .sort((a, b) => (INSIGHT_SEVERITY_ORDER[a.insight.severity] || 3) - (INSIGHT_SEVERITY_ORDER[b.insight.severity] || 3))

  return statusBanner + sortedInsights.map(({ insight, idx }) => renderInsightFeedCard(controller, insight, idx)).join("")
}

export function renderInsightDetailHtml(controller, insight) {
  const sev = insight.severity || "medium"
  const sevColor = INSIGHT_SEVERITY_COLORS[sev] || INSIGHT_SEVERITY_COLORS.medium
  const typeLabel = (insight.type || "insight").replace(/_/g, " ").toUpperCase()
  const description = insight.description || ""
  const coordStr = (insight.lat != null && insight.lng != null)
    ? `${insight.lat.toFixed(2)}, ${insight.lng.toFixed(2)}`
    : "Global"
  const insightIdx = controller._insightIndex(insight)
  const affectedEntities = controller._affectedInsightEntities(insight)

  let entitiesHtml = ""
  if (insight.entities) {
    const ents = insight.entities
    const items = []
    if (ents.earthquakes?.count) items.push(`${ents.earthquakes.count} earthquakes (max M${ents.earthquakes.max_mag || "?"})`)
    if (ents.fires) items.push(`${ents.fires.count} fire hotspots`)
    if (ents.conflict) items.push(`${ents.conflict.count || ents.conflict.events || ""} conflict events`)
    if (ents.outages?.length) items.push(`${ents.outages.length} internet outages`)
    if (ents.currency) items.push(`Currency: ${ents.currency.symbol} ${ents.currency.change_pct > 0 ? "+" : ""}${ents.currency.change_pct.toFixed(2)}%`)
    if (ents.country) items.push(`Country: ${ents.country.name}`)
    if (ents.sectors?.length) items.push(`Sector: ${ents.sectors[0].name} ${ents.sectors[0].share_pct}%`)
    if (ents.dependencies?.length) items.push(`Dependency: ${ents.dependencies[0].commodity_name} (${ents.dependencies[0].dependency_score})`)
    if (ents.exposures?.length) items.push(`Exposure: ${ents.exposures[0].commodity_name} via ${ents.exposures[0].chokepoint_name}`)
    if (ents.flight) items.push(`Flight ${ents.flight.callsign || ents.flight.icao24} (${ents.flight.squawk || "EMG"})`)
    if (ents.ship) items.push(`Ship: ${ents.ship.name || ents.ship.mmsi}`)
    if (ents.cable) items.push(`Cable: ${ents.cable.name}`)
    if (ents.nordo) items.push(`${ents.nordo.count} NORDO aircraft`)
    if (ents.notams?.length) items.push(`${ents.notams.length} NOTAMs`)
    if (ents.pipelines?.length) items.push(`${ents.pipelines.length} pipelines`)
    if (ents.satellite) items.push(`Satellite: ${ents.satellite.name}`)
    if (ents.weather) items.push(`Weather: ${ents.weather.event}`)
    if (ents.chokepoint) items.push(`Chokepoint: ${ents.chokepoint.name} (${ents.chokepoint.status})`)
    if (items.length) {
      entitiesHtml = `<div style="margin-top:6px;font-size:11px;color:var(--gt-text-sec);">${items.map(item => `<div style="padding:2px 0;">- ${controller._escapeHtml(item)}</div>`).join("")}</div>`
    }
  }

  const affectedEntitiesHtml = affectedEntities.length && insightIdx >= 0
    ? `
      <div style="margin-top:10px;">
        <div class="detail-label" style="margin-bottom:6px;">Affected Entities</div>
        <div style="display:flex;flex-wrap:wrap;gap:6px;">
          ${affectedEntities.map(entity => `
            <button
              type="button"
              class="insight-action-btn"
              data-action="click->globe#focusAffectedInsightEntity"
              data-insight-idx="${insightIdx}"
              data-entity-kind="${controller._escapeHtml(entity.kind)}"
            >
              <i class="fa-solid ${controller._escapeHtml(entity.icon)}"></i> ${controller._escapeHtml(entity.label)}
            </button>
          `).join("")}
        </div>
      </div>
    `
    : ""

  const casePath = controller._caseIntakePathForPayload?.(controller._caseSourcePayloadForInsight?.(insight))
  const caseActionHtml = casePath
    ? `
      <div style="margin-top:10px;">
        <a class="insight-action-btn" href="${controller._safeUrl(casePath)}">
          <i class="fa-solid fa-folder-plus"></i> Create case
        </a>
      </div>
    `
    : ""

  return `
    <div class="detail-callsign" style="color:${sevColor};">
      <i class="fa-solid fa-brain" style="margin-right:6px;"></i>${typeLabel}
    </div>
    <div style="display:flex;gap:6px;align-items:center;margin-bottom:4px;">
      <span style="font-size:10px;font-weight:600;text-transform:uppercase;padding:2px 6px;border-radius:3px;background:${sevColor}22;color:${sevColor};border:1px solid ${sevColor}44;">${sev}</span>
    </div>
    <div class="detail-country">${controller._escapeHtml(insight.title)}</div>
    <div style="font-size:12px;line-height:1.4;color:var(--gt-text-sec);margin:6px 0;">${controller._escapeHtml(description)}</div>
    <div class="detail-grid">
      <div class="detail-field">
        <span class="detail-label">Location</span>
        <span class="detail-value">${coordStr}</span>
      </div>
    </div>
    ${entitiesHtml}
    ${caseActionHtml}
    ${affectedEntitiesHtml}
  `
}

function renderInsightFeedCard(controller, insight, idx) {
  const sev = insight.severity || "medium"
  const icon = INSIGHT_SEVERITY_ICONS[sev] || "fa-circle-info"
  const typeLabel = INSIGHT_TYPE_LABELS[insight.type] || insight.type.replace(/_/g, " ").toUpperCase()
  const hasLocation = insight.lat != null && insight.lng != null
  const affectedEntities = controller._affectedInsightEntities(insight)
  const affectedActionLabel = controller._affectedInsightActionLabel(affectedEntities)
  const chips = buildInsightChips(controller, insight)
  const casePath = controller._caseIntakePathForPayload?.(controller._caseSourcePayloadForInsight?.(insight))

  return `<div class="insight-card insight-card--${sev}" data-insight-idx="${idx}">
    <div class="insight-card-severity">
      <i class="fa-solid ${icon}"></i>
    </div>
    <div class="insight-card-body">
      <div class="insight-card-type">${typeLabel}</div>
      <div class="insight-card-title">${controller._escapeHtml(insight.title)}</div>
      <div class="insight-card-desc">${controller._escapeHtml(insight.description)}</div>
      ${chips ? `<div class="insight-card-chips">${chips}</div>` : ""}
      <div class="insight-card-actions">
        ${hasLocation ? `<button class="insight-action-btn" data-action="click->globe#focusInsight" data-insight-idx="${idx}"><i class="fa-solid fa-location-crosshairs"></i> Focus</button>` : ""}
        ${affectedEntities.length ? `<button class="insight-action-btn" data-action="click->globe#showAffectedInsightEntities" data-insight-idx="${idx}"><i class="fa-solid fa-crosshairs"></i> ${controller._escapeHtml(affectedActionLabel)}</button>` : ""}
        ${casePath ? `<a class="insight-action-btn" href="${controller._safeUrl(casePath)}"><i class="fa-solid fa-folder-plus"></i> Create case</a>` : ""}
      </div>
    </div>
  </div>`
}

function buildInsightChips(controller, insight) {
  if (insight.type === "convergence" && insight.layers) {
    let chips = ""
    insight.layers.forEach(layer => {
      const cls = CONVERGENCE_LAYER_CHIP_COLORS[layer] || "eq"
      const label = layer.replace(/_/g, " ")
      const entities = insight.entities?.[layer]
      const count = entities?.count || (Array.isArray(entities) ? entities.length : "")
      chips += `<span class="ins-chip ins-chip--${cls}">${count ? `${count} ` : ""}${label}</span>`
    })
    if (insight.layer_count) {
      chips = `<span class="ins-chip ins-chip--conf">${insight.layer_count} layers</span>${chips}`
    }
    return chips
  }

  const entities = insight.entities
  if (!entities) return ""

  let chips = ""
  if (entities.earthquake) chips += `<span class="ins-chip ins-chip--eq">M${entities.earthquake.magnitude}</span>`
  if (entities.cables?.length) chips += `<span class="ins-chip ins-chip--cable">${entities.cables.length} cable${entities.cables.length > 1 ? "s" : ""}</span>`
  if (entities.plants?.length) chips += `<span class="ins-chip ins-chip--plant">${entities.plants.length} plant${entities.plants.length > 1 ? "s" : ""}</span>`
  if (entities.flights) chips += `<span class="ins-chip ins-chip--flight">${entities.flights.total || entities.flights.military || 0} flights</span>`
  if (entities.jamming) chips += `<span class="ins-chip ins-chip--jam">${entities.jamming.percentage?.toFixed(0)}% jam</span>`
  if (entities.fires) chips += `<span class="ins-chip ins-chip--fire">${entities.fires.count} fires</span>`
  if (entities.outages?.length) chips += `<span class="ins-chip ins-chip--outage">${entities.outages.length} outage${entities.outages.length > 1 ? "s" : ""}</span>`
  if (entities.currency) chips += `<span class="ins-chip ins-chip--${entities.currency.change_pct > 0 ? "fire" : "eq"}">${entities.currency.symbol} ${entities.currency.change_pct > 0 ? "+" : ""}${entities.currency.change_pct.toFixed(2)}%</span>`
  if (entities.conflict) chips += `<span class="ins-chip ins-chip--conf">${entities.conflict.count || entities.conflict.events} events</span>`
  if (entities.flight) chips += `<span class="ins-chip ins-chip--flight">${entities.flight.squawk || "EMG"} ${entities.flight.callsign || entities.flight.icao24}</span>`
  if (entities.ship) chips += `<span class="ins-chip ins-chip--cable">${entities.ship.name || entities.ship.mmsi}</span>`
  if (entities.cable && !entities.cables) chips += `<span class="ins-chip ins-chip--cable">${entities.cable.name} (${entities.cable.distance_km}km)</span>`
  if (entities.nordo) chips += `<span class="ins-chip ins-chip--jam">${entities.nordo.count} NORDO</span>`
  if (entities.notams?.length) chips += `<span class="ins-chip ins-chip--flight">${entities.notams.length} NOTAMs</span>`
  if (entities.pipelines?.length) chips += `<span class="ins-chip ins-chip--cable">${entities.pipelines.length} pipeline${entities.pipelines.length > 1 ? "s" : ""}</span>`
  if (entities.satellite) chips += `<span class="ins-chip ins-chip--plant">${entities.satellite.name}</span>`
  if (entities.hotspot) chips += `<span class="ins-chip ins-chip--conf">${entities.hotspot.label}</span>`
  if (entities.weather) chips += `<span class="ins-chip ins-chip--outage">${entities.weather.event}</span>`
  if (entities.conflicts?.length) chips += `<span class="ins-chip ins-chip--conf">${entities.conflicts.length} conflicts</span>`
  if (entities.pulse) chips += `<span class="ins-chip ins-chip--conf">${entities.pulse.score} pulse · ${entities.pulse.trend}</span>`
  if (entities.news?.count_24h) chips += `<span class="ins-chip ins-chip--fire">${entities.news.count_24h} reports · ${entities.news.sources} sources</span>`
  if (entities.headlines?.length) chips += entities.headlines.map(headline => `<span class="ins-chip ins-chip--eq" style="white-space:normal;text-align:left;font-size:8px;line-height:1.2;">${headline.slice(0, 60)}</span>`).join("")
  if (entities.cross_layer?.military_flights) chips += `<span class="ins-chip ins-chip--flight">${entities.cross_layer.military_flights} mil flights</span>`
  if (entities.cross_layer?.gps_jamming) chips += `<span class="ins-chip ins-chip--jam">${entities.cross_layer.gps_jamming}% jamming</span>`
  if (entities.cross_layer?.internet_outage) chips += `<span class="ins-chip ins-chip--outage">outage: ${entities.cross_layer.internet_outage}</span>`
  if (entities.cross_layer?.fire_hotspots) chips += `<span class="ins-chip ins-chip--fire">${entities.cross_layer.fire_hotspots} fires</span>`
  if (entities.chokepoint) chips += `<span class="ins-chip ins-chip--cable">${entities.chokepoint.name} (${entities.chokepoint.status})</span>`
  if (entities.country) chips += `<span class="ins-chip ins-chip--outage">${entities.country.name}</span>`
  if (entities.sectors?.length) entities.sectors.forEach(sector => { chips += `<span class="ins-chip ins-chip--plant">${sector.name} ${sector.share_pct}%</span>` })
  if (entities.dependencies?.length) entities.dependencies.forEach(dependency => { chips += `<span class="ins-chip ins-chip--outage">${dependency.commodity_name}${dependency.estimated ? " est." : ""}</span>` })
  if (entities.modeled_inputs?.length) entities.modeled_inputs.forEach(input => { chips += `<span class="ins-chip ins-chip--plant">${input.input_name}${input.estimated ? " est." : ""}</span>` })
  if (entities.exposures?.length) entities.exposures.forEach(exposure => { chips += `<span class="ins-chip ins-chip--cable">${exposure.chokepoint_name} ${exposure.exposure_score}</span>` })
  if (entities.ships?.total) chips += `<span class="ins-chip ins-chip--cable">${entities.ships.total} ships (${entities.ships.tankers || 0} tankers)</span>`
  if (entities.flows) Object.entries(entities.flows).forEach(([key, value]) => { if (value.pct) chips += `<span class="ins-chip ins-chip--outage">${value.pct}% world ${key}</span>` })
  if (entities.commodities?.length) entities.commodities.forEach(commodity => { if (commodity.change_pct) chips += `<span class="ins-chip ins-chip--${commodity.change_pct > 0 ? "fire" : "eq"}">${commodity.symbol} ${commodity.change_pct > 0 ? "+" : ""}${commodity.change_pct}%</span>` })
  return chips
}
