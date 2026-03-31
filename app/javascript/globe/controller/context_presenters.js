export const CONTEXT_LAYER_CONFIG = {
  cameras: { visibleProp: "camerasVisible", targetProp: "camerasToggleTarget", hasTargetProp: "hasCamerasToggleTarget", method: "toggleCameras" },
  news: { visibleProp: "newsVisible", targetProp: "newsToggleTarget", hasTargetProp: "hasNewsToggleTarget", method: "toggleNews" },
  weather: { visibleProp: "weatherVisible", targetProp: "weatherToggleTarget", hasTargetProp: "hasWeatherToggleTarget", method: "toggleWeather" },
  earthquakes: { visibleProp: "earthquakesVisible", targetProp: "earthquakesToggleTarget", hasTargetProp: "hasEarthquakesToggleTarget", method: "toggleEarthquakes" },
  outages: { visibleProp: "outagesVisible", targetProp: "outagesToggleTarget", hasTargetProp: "hasOutagesToggleTarget", method: "toggleOutages" },
  flights: { visibleProp: "flightsVisible", targetProp: "flightsToggleTarget", hasTargetProp: "hasFlightsToggleTarget", method: "toggleFlights" },
  ships: { visibleProp: "shipsVisible", targetProp: "shipsToggleTarget", hasTargetProp: "hasShipsToggleTarget", method: "toggleShips" },
}

export function renderSelectedContext(controller, context) {
  if (!context) {
    return '<div class="insight-empty">Select a story, theater, insight, or strategic node to inspect related evidence here.</div>'
  }

  const meta = (context.meta || [])
    .filter(item => item?.value)
    .map(item => `
      <div class="context-stat">
        <span class="context-stat-label">${controller._escapeHtml(item.label)}</span>
        <span class="context-stat-value">${controller._escapeHtml(item.value)}</span>
      </div>
    `)
    .join("")

  const sections = [
    ...(context.sections || []),
    ...controller._dynamicContextSections(context),
    ...controller._durableContextSections(context),
  ].map(section => renderContextSection(controller, section)).join("")

  const actionsList = [...(context.actions || [])]
  if (context.casePayload && controller._caseIntakePathForPayload) {
    const casePath = controller._caseIntakePathForPayload(context.casePayload)
    if (casePath) {
      actionsList.unshift({
        path: casePath,
        icon: "fa-folder-plus",
        label: "Create case",
      })
    }
  }
  if (context.nodeRequest?.kind && context.nodeRequest?.id) {
    actionsList.unshift({
      path: objectViewUrlForNodeRequest(context.nodeRequest),
      icon: "fa-table-cells-large",
      label: "Open object view",
    })
  }

  const actions = actionsList
    .map(action => renderContextAction(controller, action))
    .join("")

  return `
    <div class="insight-card insight-card--${controller._escapeHtml(context.severity || "medium")} insight-card--context">
      <div class="insight-card-severity">
        <i class="fa-solid ${controller._escapeHtml(context.icon || "fa-circle-info")}" style="color:${controller._escapeHtml(context.accentColor || "#4fc3f7")};"></i>
      </div>
      <div class="insight-card-body">
        <div class="insight-card-type">${controller._escapeHtml(context.eyebrow || "CONTEXT")}</div>
        <div class="insight-card-title">${controller._escapeHtml(context.title || "Selected context")}</div>
        ${context.subtitle ? `<div class="insight-card-desc insight-card-desc--context-subtitle">${controller._escapeHtml(context.subtitle)}</div>` : ""}
        ${context.summary ? `<div class="insight-card-desc insight-card-desc--context-summary">${controller._escapeHtml(context.summary)}</div>` : ""}
        ${meta ? `<div class="context-meta-strip">${meta}</div>` : ""}
        ${actions ? `<div class="insight-card-actions context-actions">${actions}</div>` : ""}
        ${sections}
      </div>
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

  const chips = (section.chips || [])
    .filter(Boolean)
    .map(chip => `<span class="ins-chip ins-chip--${controller._escapeHtml(chip.variant || "eq")}">${controller._escapeHtml(chip.label)}</span>`)
    .join("")

  const body = rows || items || chips || section.html || ""
  if (!body) return ""

  return `
    <div class="context-section">
      <div class="context-section-title">
        ${controller._escapeHtml(section.title || "Section")}
      </div>
      ${chips ? `<div class="insight-card-chips">${chips}</div>` : ""}
      ${rows || items ? `<div>${rows || items}</div>` : ""}
      ${section.html || ""}
    </div>
  `
}

export function renderContextItemBody(controller, item) {
  const label = `
    <div class="context-item-label">${controller._escapeHtml(item.label)}</div>
    ${item.meta ? `<div class="context-item-meta">${controller._escapeHtml(item.meta)}</div>` : ""}
  `

  if (!item.badge) return label

  return `
    <div class="context-item-body context-item-body--badged">
      <div class="context-item-copy">${label}</div>
      <span class="ins-chip ins-chip--${controller._escapeHtml(item.badge.variant || "eq")}" style="flex-shrink:0;">${controller._escapeHtml(item.badge.label)}</span>
    </div>
  `
}

export function renderContextAction(controller, action) {
  if (action.path) {
    return `<a class="insight-action-btn" href="${controller._safeUrl(action.path)}"><i class="fa-solid ${controller._escapeHtml(action.icon || "fa-arrow-up-right-from-square")}"></i> ${controller._escapeHtml(action.label)}</a>`
  }

  if (action.url) {
    return `<a class="insight-action-btn" href="${controller._safeUrl(action.url)}" target="_blank" rel="noopener"><i class="fa-solid ${controller._escapeHtml(action.icon || "fa-arrow-up-right-from-square")}"></i> ${controller._escapeHtml(action.label)}</a>`
  }

  if (action.handler === "showAffectedInsightEntities" && Number.isInteger(action.insightIdx)) {
    return `<button class="insight-action-btn" data-action="click->globe#showAffectedInsightEntities" data-insight-idx="${action.insightIdx}"><i class="fa-solid ${controller._escapeHtml(action.icon || "fa-crosshairs")}"></i> ${controller._escapeHtml(action.label)}</button>`
  }

  if (action.lat != null && action.lng != null) {
    return `<button class="insight-action-btn" data-action="click->globe#focusContextLocation" data-lat="${action.lat}" data-lng="${action.lng}" data-height="${action.height || 500000}"><i class="fa-solid ${controller._escapeHtml(action.icon || "fa-location-crosshairs")}"></i> ${controller._escapeHtml(action.label)}</button>`
  }

  return ""
}

function objectViewUrlForNodeRequest(nodeRequest) {
  return `/objects/${encodeURIComponent(nodeRequest.kind)}/${encodeURIComponent(nodeRequest.id)}`
}

function renderContextItem(controller, item) {
  const itemBody = renderContextItemBody(controller, item)

  if (item.nodeRequest?.kind && item.nodeRequest?.id) {
    return `
      <div class="context-item">
        <button
          class="context-item-hit"
          type="button"
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
          class="context-item-hit"
          type="button"
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
          class="context-item-hit"
          type="button"
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
        <a class="context-item-hit" href="${controller._safeUrl(item.url)}" target="_blank" rel="noopener">
          ${itemBody}
        </a>
      </div>
    `
  }

  return `
    <div class="context-item">
      ${itemBody}
    </div>
  `
}
