const TREND_COLORS = {
  surging: "#f44336",
  active: "#f44336",
  escalating: "#ff9800",
  elevated: "#ffc107",
  baseline: "#66bb6a",
}

const TREND_ARROWS = {
  surging: "▲",
  escalating: "↗",
  active: "●",
  elevated: "→",
  baseline: "↓",
}

const STRATEGIC_STATUS_COLORS = {
  critical: "#ff7043",
  elevated: "#ffca28",
  monitoring: "#26c6da",
}

export function renderConflictPulseDetailHtml(controller, zone) {
  const color = TREND_COLORS[zone.escalation_trend] || "#ff9800"
  const crossLayerSignals = zone.cross_layer_signals || {}
  const signalHtml = buildConflictSignalHtml(controller, zone, crossLayerSignals)
  const tierHtml = Object.entries(zone.tier_breakdown || {})
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([tier, count]) => `<span style="color:#888;">${tier}:</span>${count}`)
    .join(" ")

  const articles = zone.top_articles || []
  const headlinesHtml = articles.length > 0
    ? articles.map(article => renderConflictArticle(controller, article)).join("")
    : (zone.top_headlines || []).map(headline =>
      `<div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.4;padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.05);">${controller._escapeHtml(headline)}</div>`
    ).join("")

  const spikeBar = Math.min(zone.spike_ratio / 5.0, 1.0) * 100
  const toneBar = Math.min(Math.abs(zone.avg_tone) / 10.0, 1.0) * 100

  return `
    <div class="detail-callsign" style="color:${color};">
      <i class="fa-solid fa-bolt" style="margin-right:6px;"></i>${zone.situation_name ? controller._escapeHtml(zone.situation_name) : "DEVELOPING SITUATION"}
    </div>
    <div style="display:inline-block;padding:2px 8px;border-radius:3px;background:${color};color:#000;font:700 10px var(--gt-mono,monospace);letter-spacing:1px;margin-bottom:8px;">
      ${zone.escalation_trend.toUpperCase()} — PULSE ${zone.pulse_score}
    </div>

    <div class="detail-grid">
      <div class="detail-field">
        <span class="detail-label">Reports (24h)</span>
        <span class="detail-value" style="color:${color};">${zone.count_24h}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Reports (7d)</span>
        <span class="detail-value">${zone.count_7d}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Sources</span>
        <span class="detail-value">${zone.source_count}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Stories</span>
        <span class="detail-value">${zone.story_count}</span>
      </div>
    </div>

    <div style="margin:8px 0;">
      <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:4px;">FREQUENCY SPIKE</div>
      <div style="display:flex;align-items:center;gap:8px;">
        <div style="flex:1;height:6px;background:rgba(255,255,255,0.08);border-radius:3px;overflow:hidden;">
          <div style="width:${spikeBar}%;height:100%;background:${color};border-radius:3px;"></div>
        </div>
        <span style="font:600 11px var(--gt-mono,monospace);color:${color};">${zone.spike_ratio}x</span>
      </div>
    </div>

    <div style="margin:8px 0;">
      <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:4px;">TONE SEVERITY</div>
      <div style="display:flex;align-items:center;gap:8px;">
        <div style="flex:1;height:6px;background:rgba(255,255,255,0.08);border-radius:3px;overflow:hidden;">
          <div style="width:${toneBar}%;height:100%;background:#ef5350;border-radius:3px;"></div>
        </div>
        <span style="font:600 11px var(--gt-mono,monospace);color:#ef5350;">${zone.avg_tone}</span>
      </div>
    </div>

    ${signalHtml ? `
      <div style="margin:10px 0;">
        <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">CROSS-LAYER SIGNALS</div>
        <div style="display:flex;flex-wrap:wrap;gap:4px;">${signalHtml}</div>
      </div>
    ` : ""}

    <div style="margin:10px 0;">
      <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">TOP HEADLINES</div>
      ${headlinesHtml}
    </div>

    <div style="font:400 9px var(--gt-mono,monospace);color:#666;margin-top:8px;">
      Sources: ${tierHtml} · Updated ${new Date(zone.detected_at).toLocaleTimeString()}
    </div>

    ${zone.theater ? `<button class="detail-track-btn" style="background:rgba(255,152,0,0.15);border-color:rgba(255,152,0,0.3);color:#ffa726;font-weight:700;" data-action="click->globe#highlightTheater" data-theater="${controller._escapeHtml(zone.theater)}">
      <i class="fa-solid fa-layer-group" style="margin-right:4px;"></i>Highlight ${controller._escapeHtml(zone.theater)}
    </button>` : ""}

    <button class="detail-track-btn" style="background:rgba(244,67,54,0.2);border-color:rgba(244,67,54,0.4);color:#f44336;font-weight:700;" data-action="click->globe#revealPulseConnections" data-lat="${zone.lat}" data-lng="${zone.lng}" data-signals="${controller._escapeHtml(JSON.stringify(crossLayerSignals))}">
      <i class="fa-solid fa-eye" style="margin-right:4px;"></i>Explore This Area
    </button>

    <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${zone.lat}" data-lng="${zone.lng}">
      <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
    </button>

    ${controller._connectionsPlaceholder()}
  `
}

export function renderStrategicSituationDetailHtml(controller, item) {
  const color = STRATEGIC_STATUS_COLORS[item.status] || "#26c6da"
  const signalHtml = Object.entries(item.cross_layer_signals || {}).map(([key, value]) => {
    const label = key.replace(/_/g, " ")
    return `<span class="detail-chip" style="background:rgba(38,198,218,0.12);color:${key === "gps_jamming" ? "#ffca28" : color};">${controller._escapeHtml(`${label}: ${value}`)}</span>`
  }).join("")

  const headlinesHtml = (item.top_articles || []).map(article => {
    const timeAgo = article.published_at ? controller._timeAgo(new Date(article.published_at)) : ""
    if (article.cluster_id) {
      return `<div style="display:flex;gap:8px;align-items:flex-start;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
        <button type="button" data-action="click->globe#selectContextNode" data-kind="news_story_cluster" data-id="${controller._escapeHtml(article.cluster_id)}" data-title="${controller._escapeHtml(article.title || "Story cluster")}" data-summary="${controller._escapeHtml((article.publisher || article.source || "") + (timeAgo ? ` · ${timeAgo}` : ""))}" style="flex:1;padding:0;border:0;background:none;text-align:left;cursor:pointer;">
          <div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.3;">${controller._escapeHtml(article.title)}</div>
          <div style="font:400 9px var(--gt-mono,monospace);color:#666;margin-top:2px;">${controller._escapeHtml(article.publisher || article.source || "")} · ${timeAgo}</div>
        </button>
        ${article.url ? `<a href="${controller._safeUrl(article.url)}" target="_blank" rel="noopener" style="color:#888;text-decoration:none;padding-top:2px;"><i class="fa-solid fa-arrow-up-right-from-square"></i></a>` : ""}
      </div>`
    }

    return `<div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.4;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">${controller._escapeHtml(article.title)}</div>`
  }).join("")

  const flowRows = Object.entries(item.flows || {})
    .filter(([, flow]) => flow?.pct)
    .map(([type, flow]) => `
      <div style="display:flex;justify-content:space-between;padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
        <span style="font:600 11px var(--gt-mono);color:#e0e0e0;text-transform:capitalize;">${controller._escapeHtml(type)}</span>
        <span style="font:700 11px var(--gt-mono);color:${color};">${flow.pct}% of world</span>
      </div>
    `).join("")

  return `
    <div class="detail-callsign" style="color:${color};">
      <i class="fa-solid fa-crosshairs" style="margin-right:6px;"></i>${controller._escapeHtml(item.name || "Strategic situation")}
    </div>
    <div style="display:inline-block;padding:2px 8px;border-radius:3px;background:${color};color:#000;font:700 10px var(--gt-mono,monospace);letter-spacing:1px;margin-bottom:8px;">
      ${(item.status || "monitoring").toUpperCase()} — STRATEGIC ${item.strategic_score || 0}
    </div>
    <div style="font:400 10px var(--gt-mono,monospace);color:#aaa;margin-bottom:10px;line-height:1.4;">
      ${controller._escapeHtml(item.pressure_summary || "")}
    </div>
    <div class="detail-grid">
      <div class="detail-field">
        <span class="detail-label">Story clusters</span>
        <span class="detail-value" style="color:${color};">${item.direct_cluster_count || 0}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Sources</span>
        <span class="detail-value">${item.source_count || 0}</span>
      </div>
      ${item.theater ? `<div class="detail-field"><span class="detail-label">Theater</span><span class="detail-value">${controller._escapeHtml(item.theater)}</span></div>` : ""}
    </div>
    ${signalHtml ? `<div style="margin:10px 0;"><div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">LIVE SIGNALS</div><div style="display:flex;flex-wrap:wrap;gap:4px;">${signalHtml}</div></div>` : ""}
    ${flowRows ? `<div style="margin:10px 0;"><div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">FLOW EXPOSURE</div>${flowRows}</div>` : ""}
    ${headlinesHtml ? `<div style="margin:10px 0;"><div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">DIRECT REPORTING</div>${headlinesHtml}</div>` : ""}
    ${item.theater ? `<button class="detail-track-btn" style="background:rgba(255,152,0,0.15);border-color:rgba(255,152,0,0.3);color:#ffa726;font-weight:700;" data-action="click->globe#highlightTheater" data-theater="${controller._escapeHtml(item.theater)}">
      <i class="fa-solid fa-layer-group" style="margin-right:4px;"></i>Highlight ${controller._escapeHtml(item.theater)}
    </button>` : ""}
    <button class="detail-track-btn" style="background:rgba(38,198,218,0.15);border-color:rgba(38,198,218,0.3);color:#26c6da;" data-action="click->globe#selectContextNode" data-kind="${controller._escapeHtml(item.kind || "entity")}" data-id="${controller._escapeHtml(item.node_id || item.name || "")}" data-title="${controller._escapeHtml(item.name || "Strategic node")}" data-summary="${controller._escapeHtml(item.pressure_summary || "")}">
      <i class="fa-solid fa-diagram-project" style="margin-right:4px;"></i>Open Graph Context
    </button>
    ${controller._connectionsPlaceholder()}
  `
}

export function renderStrikeArcDetailHtml(controller, arc) {
  const width = Math.min(1.5 + arc.count * 0.2, 5).toFixed(1)
  const intensity = arc.count >= 15 ? "Very high" : arc.count >= 8 ? "High" : arc.count >= 4 ? "Moderate" : "Low"
  const headlinesHtml = (arc.sample_headlines || []).map(headline =>
    `<div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.4;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">${controller._escapeHtml(headline)}</div>`
  ).join("")

  return `
    <div class="detail-callsign" style="color:#f44336;">
      <i class="fa-solid fa-arrows-left-right" style="margin-right:6px;"></i>STRIKE ARC
    </div>
    <div style="font:600 14px var(--gt-sans,sans-serif);color:rgba(220,230,245,0.85);margin:4px 0 8px;">
      ${controller._escapeHtml(arc.from_name)} → ${controller._escapeHtml(arc.to_name)}
    </div>

    <div class="detail-grid">
      <div class="detail-field">
        <span class="detail-label">Mentions</span>
        <span class="detail-value" style="color:#f44336;">${arc.count}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Intensity</span>
        <span class="detail-value">${intensity}</span>
      </div>
    </div>

    <div style="margin:10px 0;">
      <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:4px;">ARC THICKNESS</div>
      <div style="font:400 10px var(--gt-sans,sans-serif);color:rgba(200,210,225,0.4);line-height:1.5;">
        Width scales with mention count (${width}px). More headlines mentioning this actor pair → thicker arc. Extracted from ${arc.count} headlines that mention both "${controller._escapeHtml(arc.from_name)}" and "${controller._escapeHtml(arc.to_name)}" with directional attack language.
      </div>
    </div>

    ${headlinesHtml ? `
      <div style="margin:10px 0;">
        <div style="font:600 9px var(--gt-mono,monospace);color:#888;letter-spacing:1px;margin-bottom:6px;">SAMPLE HEADLINES</div>
        ${headlinesHtml}
      </div>
    ` : ""}
  `
}

export function renderHexDetailHtml(controller, cell, zone, localName, connectionHtml, headlinesHtml) {
  const trendHtml = zone
    ? `<div style="font:600 10px var(--gt-mono);color:${TREND_COLORS[zone.escalation_trend] || "#ff9800"};letter-spacing:0.5px;margin:4px 0;">${(zone.escalation_trend || "").toUpperCase()} — PULSE ${zone.pulse_score}</div>`
    : ""

  return `
    <div class="detail-callsign"><i class="fa-solid fa-hexagon-nodes" style="color:#ff9800;margin-right:6px;"></i>${controller._escapeHtml(localName)}</div>
    ${connectionHtml}
    ${trendHtml}
    <div class="detail-grid">
      <div class="detail-field">
        <span class="detail-label">Articles</span>
        <span class="detail-value">${cell.count}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Intensity</span>
        <span class="detail-value">${(cell.intensity * 100).toFixed(0)}%</span>
      </div>
      ${zone ? `<div class="detail-field">
        <span class="detail-label">Reports (24h)</span>
        <span class="detail-value">${zone.count_24h || "—"}</span>
      </div>` : ""}
      ${zone ? `<div class="detail-field">
        <span class="detail-label">Sources</span>
        <span class="detail-value">${zone.source_count || "—"}</span>
      </div>` : ""}
    </div>
    ${headlinesHtml}
    ${zone ? `<button class="detail-track-btn" style="background:rgba(244,67,54,0.2);border-color:rgba(244,67,54,0.4);color:#f44336;"
      data-action="click->globe#flyToConflictZone" data-zone-key="${controller._escapeHtml(zone.cell_key)}">
      <i class="fa-solid fa-crosshairs" style="margin-right:4px;"></i>Go to ${controller._escapeHtml(cell.situation || "situation")}
    </button>` : ""}
    ${cell.theater ? `<button class="detail-track-btn" style="background:rgba(255,152,0,0.15);border-color:rgba(255,152,0,0.3);color:#ffa726;"
      data-action="click->globe#highlightTheater" data-theater="${controller._escapeHtml(cell.theater)}">
      <i class="fa-solid fa-layer-group" style="margin-right:4px;"></i>Highlight ${controller._escapeHtml(cell.theater)}
    </button>` : ""}
  `
}

export function renderSituationPanelHtml(controller, zones, strategic, snapshotStatus, expandedState) {
  const countSummary = {
    zones: zones.length,
    strategic: strategic.length,
    snapshotStatus,
  }

  if (!zones.length && !strategic.length) {
    const emptyLabel = {
      pending: "Conflict pulse snapshot pending.",
      stale: "Showing no active zones from the latest stored snapshot.",
      error: "Conflict pulse snapshot unavailable.",
    }[snapshotStatus] || "No active zones."

    return {
      countSummary,
      html: `<div style="padding:16px 14px;color:var(--gt-text-dim);font:500 11px var(--gt-mono);">${controller._escapeHtml(emptyLabel)}</div>`,
    }
  }

  const theaters = {}
  zones.forEach(zone => {
    const theater = zone.theater || "Other"
    ;(theaters[theater] ||= []).push(zone)
  })

  const sortedTheaters = Object.entries(theaters).sort((a, b) => {
    const maxA = Math.max(...a[1].map(zone => zone.pulse_score))
    const maxB = Math.max(...b[1].map(zone => zone.pulse_score))
    return maxB - maxA
  })

  let html = ""
  if (snapshotStatus !== "ready") {
    html += `<div style="padding:0 0 10px;display:flex;align-items:center;gap:6px;flex-wrap:wrap;">${controller._statusChip(snapshotStatus, controller._statusLabel(snapshotStatus, "snapshot"))}</div>`
  }

  if (strategic.length) {
    html += renderStrategicSituationSection(controller, strategic)
  }

  sortedTheaters.forEach(([theater, theaterZones], idx) => {
    html += renderTheaterZoneSection(controller, theater, theaterZones, idx, expandedState || {})
  })

  return { countSummary, html }
}

function renderStrategicSituationSection(controller, strategic) {
  let html = `<div class="sit-theater">`
  html += `<div class="sit-theater-header"><span class="sit-theater-arrow">▾</span><span class="sit-theater-name">Strategic Situations</span><span class="sit-theater-count">${strategic.length}</span></div>`
  html += `<div class="sit-theater-body">`

  strategic.forEach((item, idx) => {
    const color = STRATEGIC_STATUS_COLORS[item.status] || "#26c6da"
    const topArticle = (item.top_articles || [])[0]
    const strategicId = item.id || item.node_id || item.name || `strategic-${idx}`
    html += `<div class="sit-zone sit-zone--summary" data-zone-key="${controller._escapeHtml(item.id || `strategic-${idx}`)}">
      <div class="sit-zone-header" data-action="click->globe#showStrategicSituationFromList" data-id="${controller._escapeHtml(strategicId)}">
        <span class="sit-zone-name">${controller._escapeHtml(item.name || "Strategic node")}</span>
        <span class="sit-zone-score" style="color:${color};">${item.strategic_score || 0} <span class="sit-zone-trend">${controller._escapeHtml((item.status || "monitoring").toUpperCase())}</span></span>
      </div>
      <div class="sit-zone-summary">
        <div class="sit-zone-headline">${controller._escapeHtml(item.pressure_summary || (item.theater || "Strategic pressure"))}</div>
        <div class="sit-zone-meta">${controller._escapeHtml([item.theater, `${item.source_count || 0} sources`, `${item.direct_cluster_count || 0} clusters`].filter(Boolean).join(" · "))}</div>
        ${topArticle ? `<button type="button" data-action="click->globe#selectContextNode" data-kind="news_story_cluster" data-id="${controller._escapeHtml(topArticle.cluster_id || "")}" data-title="${controller._escapeHtml(topArticle.title || "Story cluster")}" data-summary="${controller._escapeHtml(topArticle.publisher || topArticle.source || "")}" style="display:block;width:100%;padding:0;border:0;background:none;text-align:left;cursor:pointer;margin-top:8px;">
          <div class="sit-zone-headline">${controller._escapeHtml(topArticle.title || "")}</div>
          <div class="sit-zone-meta">${controller._escapeHtml(topArticle.publisher || topArticle.source || "")}</div>
        </button>` : ""}
      </div>
    </div>`
  })

  html += `</div></div>`
  return html
}

function renderTheaterZoneSection(controller, theater, theaterZones, theaterIndex, expandedState) {
  const maxScore = Math.max(...theaterZones.map(zone => zone.pulse_score))
  const collapsed = maxScore < 40

  let html = `<div class="sit-theater${collapsed ? " sit-theater--collapsed" : ""}">`
  html += `<div class="sit-theater-header" data-action="click->globe#toggleSitTheater" data-idx="${theaterIndex}">
    <span class="sit-theater-arrow">${collapsed ? "▸" : "▾"}</span>
    <span class="sit-theater-name">${controller._escapeHtml(theater)}</span>
    <span class="sit-theater-count">${theaterZones.length}</span>
  </div>`
  html += `<div class="sit-theater-body"${collapsed ? ' style="display:none;"' : ""}>`

  theaterZones
    .sort((a, b) => b.pulse_score - a.pulse_score)
    .forEach(zone => {
      html += renderSituationZoneCard(controller, zone, expandedState[zone.cell_key] || "collapsed")
    })

  html += `</div></div>`
  return html
}

function renderSituationZoneCard(controller, zone, state) {
  const color = TREND_COLORS[zone.escalation_trend] || "#ff9800"
  const arrow = TREND_ARROWS[zone.escalation_trend] || ""
  const key = zone.cell_key

  let html = `<div class="sit-zone sit-zone--${state}" data-zone-key="${controller._escapeHtml(key)}">`
  html += `<div class="sit-zone-header" data-action="click->globe#toggleSitZone" data-zone-key="${controller._escapeHtml(key)}">
    <span class="sit-zone-name">${controller._escapeHtml(zone.situation_name || "Developing")}</span>
    <span class="sit-zone-score" style="color:${color};">${zone.pulse_score} ${arrow} <span class="sit-zone-trend">${zone.escalation_trend.toUpperCase()}</span></span>
  </div>`

  if (state === "summary" || state === "expanded") {
    html += renderSituationZoneSummary(controller, zone)
  }

  if (state === "expanded") {
    html += renderSituationZoneExpanded(controller, zone)
  }

  html += `</div>`
  return html
}

function renderSituationZoneSummary(controller, zone) {
  const topArticle = (zone.top_articles || [])[0]
  const chips = []
  const signals = zone.cross_layer_signals || {}
  if (signals.military_flights) chips.push(`<span class="sit-chip sit-chip--mil">🛩 ${signals.military_flights}</span>`)
  if (signals.gps_jamming) chips.push(`<span class="sit-chip sit-chip--jam">📡 ${signals.gps_jamming}%</span>`)
  if (signals.fire_hotspots) chips.push(`<span class="sit-chip sit-chip--fire">🔥 ${signals.fire_hotspots}</span>`)
  if (signals.known_conflict_zone) chips.push(`<span class="sit-chip sit-chip--hist">📊 ${signals.known_conflict_zone}</span>`)
  if (signals.internet_outage) chips.push(`<span class="sit-chip sit-chip--out">⚡ outage</span>`)

  let html = `<div class="sit-zone-summary">`
  if (topArticle) {
    const timeAgo = topArticle.published_at ? controller._timeAgo(new Date(topArticle.published_at)) : ""
    if (topArticle.cluster_id) {
      html += `<button type="button" data-action="click->globe#selectContextNode" data-kind="news_story_cluster" data-id="${controller._escapeHtml(topArticle.cluster_id)}" data-title="${controller._escapeHtml(topArticle.title?.substring(0, 90) || "Story cluster")}" data-summary="${controller._escapeHtml((topArticle.publisher || topArticle.source || "") + (timeAgo ? ` · ${timeAgo}` : ""))}" style="display:block;width:100%;padding:0;border:0;background:none;text-align:left;cursor:pointer;">
        <div class="sit-zone-headline">${controller._escapeHtml(topArticle.title?.substring(0, 90))}</div>
        <div class="sit-zone-meta">${controller._escapeHtml(topArticle.publisher || topArticle.source || "")} · ${timeAgo}</div>
      </button>`
    } else {
      html += `<div class="sit-zone-headline">${controller._escapeHtml(topArticle.title?.substring(0, 90))}</div>
        <div class="sit-zone-meta">${controller._escapeHtml(topArticle.publisher || topArticle.source || "")} · ${timeAgo}</div>`
    }
  }
  if (chips.length) html += `<div class="sit-zone-chips">${chips.join("")}</div>`
  html += `</div>`
  return html
}

function renderSituationZoneExpanded(controller, zone) {
  let html = `<div class="sit-zone-detail">`
  html += `<div class="sit-zone-stats">
    <span>${zone.count_24h} reports today</span> · <span>${zone.source_count} sources</span> · <span>spike ${zone.spike_ratio}x</span>
  </div>`

  const articles = (zone.top_articles || []).slice(0, 5)
  if (articles.length) {
    html += `<div class="sit-section-label">TOP STORIES</div>`
    articles.forEach(article => {
      const timeAgo = article.published_at ? controller._timeAgo(new Date(article.published_at)) : ""
      if (article.cluster_id) {
        html += `<div class="sit-article" style="display:flex;gap:8px;align-items:flex-start;">
          <button type="button" data-action="click->globe#selectContextNode" data-kind="news_story_cluster" data-id="${controller._escapeHtml(article.cluster_id)}" data-title="${controller._escapeHtml(article.title || "Story cluster")}" data-summary="${controller._escapeHtml((article.publisher || article.source || "") + (timeAgo ? ` · ${timeAgo}` : ""))}" style="flex:1;padding:0;border:0;background:none;text-align:left;cursor:pointer;">
            <div class="sit-article-title">${controller._escapeHtml(article.title)}</div>
            <div class="sit-article-meta">${controller._escapeHtml(article.publisher || article.source || "")} · ${timeAgo}</div>
          </button>
          ${article.url ? `<a href="${controller._safeUrl(article.url)}" target="_blank" rel="noopener" style="color:rgba(200,210,225,0.45);text-decoration:none;"><i class="fa-solid fa-arrow-up-right-from-square"></i></a>` : ""}
        </div>`
      } else {
        html += `<a href="${controller._safeUrl(article.url)}" target="_blank" rel="noopener" class="sit-article">
          <div class="sit-article-title">${controller._escapeHtml(article.title)}</div>
          <div class="sit-article-meta">${controller._escapeHtml(article.publisher || article.source || "")} · ${timeAgo}</div>
        </a>`
      }
    })
    if (zone.count_24h > 5) html += `<div class="sit-more">+${zone.count_24h - 5} more</div>`
  }

  const signals = zone.cross_layer_signals || {}
  const context = zone.signal_context || {}
  const signalEntries = Object.entries(signals).filter(([, value]) => value)
  if (signalEntries.length) {
    html += `<div class="sit-section-label">WHY THESE LAYERS MATTER</div>`
    html += signalEntries.map(([key, value]) => renderSituationSignal(controller, key, value, context[key] || "")).join("")
  }

  html += `<button class="sit-explore-btn" data-action="click->globe#exploreSituation" data-zone-key="${controller._escapeHtml(zone.cell_key)}">
    Explore this area →
  </button>`
  html += `</div>`
  return html
}

function renderSituationSignal(controller, key, value, description) {
  const signalIcons = {
    military_flights: "🛩",
    gps_jamming: "📡",
    fire_hotspots: "🔥",
    known_conflict_zone: "📊",
    internet_outage: "⚡",
  }
  const signalLabels = {
    military_flights: "military flights",
    gps_jamming: "GPS jamming",
    fire_hotspots: "fire hotspots",
    known_conflict_zone: "historical incidents",
    internet_outage: "internet outage",
  }
  const valueString = typeof value === "number" ? (key === "gps_jamming" ? `${value}%` : value) : value
  return `<div class="sit-signal">
    <div class="sit-signal-header">${signalIcons[key] || "📎"} ${valueString} ${controller._escapeHtml(signalLabels[key] || key.replace(/_/g, " "))}</div>
    ${description ? `<div class="sit-signal-desc">${controller._escapeHtml(description)}</div>` : ""}
  </div>`
}

function renderConflictArticle(controller, article) {
  const timeAgo = article.published_at ? controller._timeAgo(new Date(article.published_at)) : ""
  const itemBody = `
    <div style="font:400 11px var(--gt-mono,monospace);color:#e0e0e0;line-height:1.3;">${controller._escapeHtml(article.title)}</div>
    <div style="font:400 9px var(--gt-mono,monospace);color:#666;margin-top:2px;">${controller._escapeHtml(article.publisher || article.source || "")} · tone ${article.tone || 0} · ${timeAgo}</div>
  `

  if (article.cluster_id) {
    return `<div style="display:flex;gap:8px;align-items:flex-start;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
      <button type="button" data-action="click->globe#selectContextNode" data-kind="news_story_cluster" data-id="${controller._escapeHtml(article.cluster_id)}" data-title="${controller._escapeHtml(article.title || "Story cluster")}" data-summary="${controller._escapeHtml((article.publisher || article.source || "") + (timeAgo ? ` · ${timeAgo}` : ""))}" style="flex:1;padding:0;border:0;background:none;text-align:left;cursor:pointer;">
        ${itemBody}
      </button>
      ${article.url ? `<a href="${controller._safeUrl(article.url)}" target="_blank" rel="noopener" style="color:#888;text-decoration:none;padding-top:2px;"><i class="fa-solid fa-arrow-up-right-from-square"></i></a>` : ""}
    </div>`
  }

  return `<a href="${controller._safeUrl(article.url)}" target="_blank" rel="noopener" style="display:block;text-decoration:none;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
    ${itemBody}
  </a>`
}

function buildConflictSignalHtml(controller, zone, signals) {
  let html = ""
  if (signals.military_flights) html += `<span class="detail-chip" style="cursor:pointer;background:rgba(239,83,80,0.15);color:#ef5350;" data-action="click->globe#pulseSignalClick" data-signal="flights" data-lat="${zone.lat}" data-lng="${zone.lng}"><i class="fa-solid fa-jet-fighter"></i> ${signals.military_flights} mil flights</span>`
  if (signals.gps_jamming) html += `<span class="detail-chip" style="cursor:pointer;background:rgba(255,193,7,0.15);color:#ffc107;" data-action="click->globe#pulseSignalClick" data-signal="gpsJamming" data-lat="${zone.lat}" data-lng="${zone.lng}"><i class="fa-solid fa-satellite-dish"></i> ${signals.gps_jamming}% jamming</span>`
  if (signals.internet_outage) html += `<span class="detail-chip" style="background:rgba(156,39,176,0.15);color:#ce93d8;"><i class="fa-solid fa-plug"></i> outage: ${signals.internet_outage}</span>`
  if (signals.fire_hotspots) html += `<span class="detail-chip" style="cursor:pointer;background:rgba(255,87,34,0.15);color:#ff5722;" data-action="click->globe#pulseSignalClick" data-signal="fires" data-lat="${zone.lat}" data-lng="${zone.lng}"><i class="fa-solid fa-fire"></i> ${signals.fire_hotspots} fires</span>`
  if (signals.known_conflict_zone) html += `<span class="detail-chip" style="cursor:pointer;background:rgba(244,67,54,0.15);color:#f44336;" data-action="click->globe#pulseSignalClick" data-signal="conflicts" data-lat="${zone.lat}" data-lng="${zone.lng}"><i class="fa-solid fa-crosshairs"></i> ${signals.known_conflict_zone} historical events</span>`
  return html
}
