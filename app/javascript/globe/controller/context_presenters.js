export const CONTEXT_LAYER_CONFIG = {
  cameras: { visibleProp: "camerasVisible", targetProp: "camerasToggleTarget", hasTargetProp: "hasCamerasToggleTarget", method: "toggleCameras" },
  news: { visibleProp: "newsVisible", targetProp: "newsToggleTarget", hasTargetProp: "hasNewsToggleTarget", method: "toggleNews" },
  weather: { visibleProp: "weatherVisible", targetProp: "weatherToggleTarget", hasTargetProp: "hasWeatherToggleTarget", method: "toggleWeather" },
  earthquakes: { visibleProp: "earthquakesVisible", targetProp: "earthquakesToggleTarget", hasTargetProp: "hasEarthquakesToggleTarget", method: "toggleEarthquakes" },
  outages: { visibleProp: "outagesVisible", targetProp: "outagesToggleTarget", hasTargetProp: "hasOutagesToggleTarget", method: "toggleOutages" },
  flights: { visibleProp: "flightsVisible", targetProp: "flightsToggleTarget", hasTargetProp: "hasFlightsToggleTarget", method: "toggleFlights" },
  ships: { visibleProp: "shipsVisible", targetProp: "shipsToggleTarget", hasTargetProp: "hasShipsToggleTarget", method: "toggleShips" },
}

function contextStatusLabel(context) {
  const value = context?.statusLabel || context?.severity
  if (!value) return null
  return `${value}`.replace(/_/g, " ").toUpperCase()
}

function safeContextSeverity(context) {
  return context?.severity || "medium"
}

function nodeRequestKey(nodeRequest) {
  if (!nodeRequest?.kind || !nodeRequest?.id) return null
  return `${nodeRequest.kind}:${nodeRequest.id}`
}

function renderPinnedMapSection(controller, context) {
  const activeKey = nodeRequestKey(context?.nodeRequest)
  const pinnedStates = (controller._pinnedAnchoredDetails || [])
    .filter(state => state?.anchorId)
    .filter(state => nodeRequestKey(state.nodeRequest) !== activeKey)

  if (!pinnedStates.length) return ""

  const cards = pinnedStates.map(state => {
    const anchorId = controller._escapeHtml(state.anchorId)
    const eyebrow = controller._escapeHtml(state.chips?.[0]?.label || "Pinned")
    const title = controller._escapeHtml(state.title || "Pinned item")
    const subtitle = state.subtitle
      ? `<div class="context-pinned-meta">${controller._escapeHtml(state.subtitle)}</div>`
      : ""
    const brief = state.brief
      ? `<div class="context-pinned-brief">${controller._escapeHtml(state.brief)}</div>`
      : ""
    const caseAction = state.casePath
      ? `<a class="context-action-btn" href="${controller._safeUrl(state.casePath)}">Case</a>`
      : ""

    return `
      <article class="context-pinned-card">
        <div class="context-pinned-eyebrow">${eyebrow}</div>
        <div class="context-pinned-title">${title}</div>
        ${subtitle}
        ${brief}
        <div class="context-pinned-actions">
          <button type="button" class="context-action-btn" data-action="click->globe#focusPinnedAnchoredDetail" data-anchor-id="${anchorId}">Focus</button>
          ${caseAction}
          <button type="button" class="context-action-btn" data-action="click->globe#unpinAnchoredDetail" data-anchor-id="${anchorId}">Unpin</button>
        </div>
      </article>
    `
  }).join("")

  return `
    <section class="context-section context-section--pinned">
      <div class="context-section-head">
        <div class="context-section-title">Pinned on map</div>
        <button type="button" class="context-section-clear" data-action="click->globe#unpinAllAnchoredDetails">Unpin all</button>
      </div>
      <div class="context-pinned-list">${cards}</div>
    </section>
  `
}

function renderMetricGrid(metrics = []) {
  const cards = metrics
    .filter(metric => metric?.label && metric?.value)
    .map(metric => `
      <div class="context-metric-card">
        <div class="context-metric-label">${metric.label}</div>
        <div class="context-metric-value">${metric.value}</div>
      </div>
    `)
    .join("")

  return cards ? `<div class="context-metric-grid">${cards}</div>` : ""
}

function renderTheaterRailSection(controller, context) {
  const zone = context?.zoneData || {}
  const brief = context?.theaterBrief || {}
  const derivedConfidence = controller._theaterDerivedConfidence
    ? controller._theaterDerivedConfidence(zone)
    : { level: "medium", rationale: "" }
  const confidenceLevel = brief.confidence_level || derivedConfidence.level || "medium"
  const confidenceLevelKey = `${confidenceLevel}`.trim().toLowerCase().replace(/\s+/g, "-")
  const confidenceRationale = brief.confidence_rationale || derivedConfidence.rationale || ""
  const assessment = brief.assessment
    || (controller._theaterFallbackAssessment ? controller._theaterFallbackAssessment(zone) : null)
    || context.summary
    || "Live theater assessment unavailable."
  const generatedAgo = context.theaterBriefGeneratedAt ? controller._timeAgo(new Date(context.theaterBriefGeneratedAt)) : null

  let stateHtml = ""
  if (context.theaterBriefStatus === "ready" && generatedAgo) {
    stateHtml = `<div class="context-brief-state">Stored AI brief · ${controller._escapeHtml(generatedAgo)}</div>`
  } else if (["loading", "pending"].includes(context.theaterBriefStatus)) {
    stateHtml = '<div class="context-brief-state">Refreshing stored AI brief from current theater evidence…</div>'
  } else if (context.theaterBriefStatus === "error") {
    stateHtml = '<div class="context-brief-state context-brief-state--error">Stored AI brief unavailable. Showing live factual read.</div>'
  }

  const metrics = [
    zone.pulse_score ? { label: "Pulse", value: `${zone.pulse_score}` } : null,
    zone.count_24h ? { label: "Reports / 24h", value: `${zone.count_24h}` } : null,
    zone.source_count ? { label: "Sources", value: `${zone.source_count}` } : null,
    zone.detected_at ? { label: "Updated", value: controller._timeAgo(new Date(zone.detected_at)) } : null,
  ].filter(Boolean)

  const developments = controller._theaterReportingItems
    ? controller._theaterReportingItems(zone).slice(0, 3)
    : []

  return [
    renderContextSection(controller, {
      title: "Live read",
      variant: "summary",
      html: `
        ${renderMetricGrid(metrics)}
        <div class="context-brief context-brief--summary">
          <div class="context-brief-body">${controller._escapeHtml(assessment)}</div>
          <div class="context-brief-confidence">
            <span class="context-brief-confidence-level context-brief-confidence-level--${controller._escapeHtml(confidenceLevelKey)}">${controller._escapeHtml(confidenceLevel)} confidence</span>
            ${confidenceRationale ? `<span class="context-brief-confidence-text">${controller._escapeHtml(confidenceRationale)}</span>` : ""}
          </div>
          ${stateHtml}
        </div>
      `,
    }),
    developments.length ? renderContextSection(controller, {
      title: "Latest developments",
      variant: "summary",
      items: developments,
    }) : "",
  ].filter(Boolean)
}

function renderRecordedRailSection(controller, context) {
  const node = context?.nodeContext?.node
  const summary = node?.summary && node.summary !== context.summary ? `${node.summary}` : null
  const rows = [
    (context?.nodeContext?.memberships || []).length ? { label: "Actors", value: `${context.nodeContext.memberships.length}` } : null,
    (context?.nodeContext?.evidence || []).length ? { label: "Evidence", value: `${context.nodeContext.evidence.length}` } : null,
    (context?.nodeContext?.relationships || []).length ? { label: "Linked nodes", value: `${context.nodeContext.relationships.length}` } : null,
  ].filter(Boolean)

  if (!summary && !rows.length) return ""

  return renderContextSection(controller, {
    title: "Recorded context",
    variant: "summary",
    html: summary
      ? `
        <div class="context-brief context-brief--summary">
          <div class="context-brief-group">
            <div class="context-brief-label">Node record</div>
            <div class="context-brief-body">${controller._escapeHtml(summary)}</div>
          </div>
        </div>
      `
      : "",
    rows,
  })
}

function primaryContextRailSections(controller, context) {
  if (!context) return []
  if (context.kind === "theater") return renderTheaterRailSection(controller, context)
  return [renderRecordedRailSection(controller, context)].filter(Boolean)
}

function primaryContextActions(controller, context) {
  const actions = []

  if (context.casePayload && controller._caseIntakePathForPayload) {
    const casePath = controller._caseIntakePathForPayload(context.casePayload)
    if (casePath) {
      actions.push({
        path: casePath,
        icon: "fa-folder-open",
        label: "Open case workspace",
      })
    }
  }

  const focusAction = (context.actions || []).find(action => action.lat != null && action.lng != null)
  if (focusAction) {
    actions.push({
      ...focusAction,
      label: focusAction.label === "Focus" ? "Focus map" : focusAction.label,
    })
  }

  const externalAction = context.kind === "theater"
    ? null
    : (context.actions || []).find(action => action.url || action.path)
  if (externalAction) actions.push(externalAction)

  return actions.slice(0, 2)
}

export function renderSelectedContext(controller, context) {
  const pinnedSection = renderPinnedMapSection(controller, context)

  if (!context) {
    if (pinnedSection) {
      return `
        <div class="context-shell context-shell--pinned-only" style="--context-accent:#93c5fd;">
          <div class="context-overview">
            <div class="context-kicker">
              <span class="context-kicker-label">
                <i class="fa-solid fa-thumbtack" aria-hidden="true"></i>
                MAP CONTEXT
              </span>
            </div>
            <div class="context-title">Pinned map context</div>
            <div class="context-summary">No active selection. These pinned map cards stay linked to the globe until you unpin them or open one into focus.</div>
          </div>
          <div class="context-section-list">${pinnedSection}</div>
        </div>
      `
    }

    return '<div class="context-empty">Click a map item to inspect its live context here. Deep analysis belongs in the case workspace.</div>'
  }

  const showTopSummary = context.kind !== "theater"
  const metaPills = (showTopSummary ? (context.meta || []) : [])
    .filter(item => item?.value)
    .map(item => `
      <span class="context-meta-pill">
        <span class="context-meta-label">${controller._escapeHtml(item.label)}</span>
        <span class="context-meta-value">${controller._escapeHtml(item.value)}</span>
      </span>
    `)
    .join("")

  const sections = [...primaryContextRailSections(controller, context)]
  if (pinnedSection) sections.push(pinnedSection)

  const actions = primaryContextActions(controller, context)
    .map(action => renderContextAction(controller, action))
    .join("")

  const severity = safeContextSeverity(context)
  const statusChip = contextStatusLabel(context)
    ? `<span class="context-status-chip context-status-chip--${controller._escapeHtml(severity)}">${controller._escapeHtml(contextStatusLabel(context))}</span>`
    : ""

  return `
    <div class="context-shell context-shell--${controller._escapeHtml(severity)}" style="--context-accent:${controller._escapeHtml(context.accentColor || "#4fc3f7")};">
      <div class="context-overview">
        <div class="context-kicker">
          <span class="context-kicker-label">
            <i class="fa-solid ${controller._escapeHtml(context.icon || "fa-circle-info")}" aria-hidden="true"></i>
            ${controller._escapeHtml(context.eyebrow || "CONTEXT")}
          </span>
          ${statusChip}
        </div>
        <div class="context-title">${controller._escapeHtml(context.title || "Selected context")}</div>
        ${context.subtitle ? `<div class="context-subtitle">${controller._escapeHtml(context.subtitle)}</div>` : ""}
        ${showTopSummary && context.summary ? `<div class="context-summary">${controller._escapeHtml(context.summary)}</div>` : ""}
        ${metaPills ? `<div class="context-meta">${metaPills}</div>` : ""}
        ${actions ? `<div class="context-actions">${actions}</div>` : ""}
      </div>
      ${sections.length ? `<div class="context-section-list">${sections.join("")}</div>` : ""}
    </div>
  `
}

export function renderContextSection(controller, section) {
  if (!section) return ""

  const rows = (section.rows || [])
    .filter(row => row?.value)
    .map(row => `
      <div class="context-row">
        <span class="context-row-label">${controller._escapeHtml(row.label)}</span>
        <span class="context-row-value">${controller._escapeHtml(row.value)}</span>
      </div>
    `)
    .join("")

  const items = (section.items || [])
    .filter(item => item?.label)
    .map(item => renderContextItem(controller, item))
    .join("")

  const groups = (section.groups || [])
    .map(group => {
      const groupItems = (group.items || [])
        .filter(item => item?.label)
        .map(item => renderContextItem(controller, item))
        .join("")
      if (!groupItems) return ""

      return `
        <div class="context-section-group">
          ${group.title ? `<div class="context-section-group-title">${controller._escapeHtml(group.title)}</div>` : ""}
          <div class="context-items">${groupItems}</div>
        </div>
      `
    })
    .join("")

  const chips = (section.chips || [])
    .filter(Boolean)
    .map(chip => `<span class="ins-chip ins-chip--${controller._escapeHtml(chip.variant || "eq")}">${controller._escapeHtml(chip.label)}</span>`)
    .join("")

  const html = section.html || ""
  if (!rows && !items && !chips && !html && !groups) return ""

  return `
    <section class="context-section${section.variant ? ` context-section--${controller._escapeHtml(section.variant)}` : ""}">
      <div class="context-section-title">${controller._escapeHtml(section.title || "Section")}</div>
      ${chips ? `<div class="context-chip-row">${chips}</div>` : ""}
      ${rows ? `<div class="context-rows">${rows}</div>` : ""}
      ${html ? `<div class="context-html">${html}</div>` : ""}
      ${groups}
      ${items ? `<div class="context-items">${items}</div>` : ""}
    </section>
  `
}

export function renderContextItemBody(controller, item) {
  const label = `
    <div class="context-item-copy">
      <div class="context-item-label">${controller._escapeHtml(item.label)}</div>
      ${item.meta ? `<div class="context-item-meta">${controller._escapeHtml(item.meta)}</div>` : ""}
    </div>
  `

  if (!item.badge) return label

  return `
    <div class="context-item-main">
      ${label}
      <span class="ins-chip context-item-badge ins-chip--${controller._escapeHtml(item.badge.variant || "eq")}">${controller._escapeHtml(item.badge.label)}</span>
    </div>
  `
}

export function renderContextAction(controller, action) {
  if (action.path) {
    return `<a class="context-action-btn" href="${controller._safeUrl(action.path)}"><i class="fa-solid ${controller._escapeHtml(action.icon || "fa-arrow-up-right-from-square")}"></i> ${controller._escapeHtml(action.label)}</a>`
  }

  if (action.url) {
    return `<a class="context-action-btn" href="${controller._safeUrl(action.url)}" target="_blank" rel="noopener"><i class="fa-solid ${controller._escapeHtml(action.icon || "fa-arrow-up-right-from-square")}"></i> ${controller._escapeHtml(action.label)}</a>`
  }

  if (action.handler === "showAffectedInsightEntities" && Number.isInteger(action.insightIdx)) {
    return `<button class="context-action-btn" data-action="click->globe#showAffectedInsightEntities" data-insight-idx="${action.insightIdx}"><i class="fa-solid ${controller._escapeHtml(action.icon || "fa-crosshairs")}"></i> ${controller._escapeHtml(action.label)}</button>`
  }

  if (action.lat != null && action.lng != null) {
    return `<button class="context-action-btn" data-action="click->globe#focusContextLocation" data-lat="${action.lat}" data-lng="${action.lng}" data-height="${action.height || 500000}"><i class="fa-solid ${controller._escapeHtml(action.icon || "fa-location-crosshairs")}"></i> ${controller._escapeHtml(action.label)}</button>`
  }

  return ""
}


function renderContextItem(controller, item) {
  const itemBody = renderContextItemBody(controller, item)

  if (item.nodeRequest?.kind && item.nodeRequest?.id) {
    return `
      <div class="context-item">
        <button
          type="button"
          class="context-item-button"
          data-action="click->globe#selectContextNode"
          data-kind="${controller._escapeHtml(item.nodeRequest.kind)}"
          data-id="${controller._escapeHtml(item.nodeRequest.id)}"
          data-title="${controller._escapeHtml(item.label)}"
          data-summary="${controller._escapeHtml(item.meta || "")}"
        >
          ${itemBody}
        </button>
      </div>
    `
  }

  if (item.cameraId) {
    return `
      <div class="context-item">
        <button
          type="button"
          class="context-item-button"
          data-action="click->globe#openContextCamera"
          data-camera-id="${controller._escapeHtml(item.cameraId)}"
        >
          ${itemBody}
        </button>
      </div>
    `
  }

  if (item.layerKey || item.rpTab) {
    const latAttr = item.lat != null ? ` data-lat="${item.lat}"` : ""
    const lngAttr = item.lng != null ? ` data-lng="${item.lng}"` : ""
    const heightAttr = item.height != null ? ` data-height="${item.height}"` : ""
    const tabAttr = item.rpTab ? ` data-rp-tab="${controller._escapeHtml(item.rpTab)}"` : ""
    const layerAttr = item.layerKey ? ` data-layer-key="${controller._escapeHtml(item.layerKey)}"` : ""

    return `
      <div class="context-item">
        <button
          type="button"
          class="context-item-button"
          data-action="click->globe#openContextLayer"
          ${layerAttr}
          ${tabAttr}
          ${latAttr}
          ${lngAttr}
          ${heightAttr}
        >
          ${itemBody}
        </button>
      </div>
    `
  }

  if (item.url) {
    return `
      <div class="context-item">
        <a class="context-item-link" href="${controller._safeUrl(item.url)}" target="_blank" rel="noopener">
          ${itemBody}
        </a>
      </div>
    `
  }

  return `
    <div class="context-item">
      <div class="context-item-static">
        ${itemBody}
      </div>
    </div>
  `
}
