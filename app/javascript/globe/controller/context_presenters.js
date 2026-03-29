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
      <div class="detail-field">
        <span class="detail-label">${controller._escapeHtml(item.label)}</span>
        <span class="detail-value">${controller._escapeHtml(item.value)}</span>
      </div>
    `)
    .join("")

  const sections = [
    ...(context.sections || []),
    ...controller._dynamicContextSections(context),
    ...controller._durableContextSections(context),
  ].map(section => renderContextSection(controller, section)).join("")

  const actions = (context.actions || [])
    .map(action => renderContextAction(controller, action))
    .join("")

  return `
    <div class="insight-card insight-card--${controller._escapeHtml(context.severity || "medium")}">
      <div class="insight-card-severity">
        <i class="fa-solid ${controller._escapeHtml(context.icon || "fa-circle-info")}" style="color:${controller._escapeHtml(context.accentColor || "#4fc3f7")};"></i>
      </div>
      <div class="insight-card-body">
        <div class="insight-card-type">${controller._escapeHtml(context.eyebrow || "CONTEXT")}</div>
        <div class="insight-card-title">${controller._escapeHtml(context.title || "Selected context")}</div>
        ${context.subtitle ? `<div class="insight-card-desc" style="margin-top:4px;color:rgba(226,232,240,0.78);">${controller._escapeHtml(context.subtitle)}</div>` : ""}
        ${context.summary ? `<div class="insight-card-desc">${controller._escapeHtml(context.summary)}</div>` : ""}
        ${meta ? `<div class="detail-grid" style="margin-top:10px;">${meta}</div>` : ""}
        ${actions ? `<div class="insight-card-actions" style="margin-top:10px;">${actions}</div>` : ""}
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
      <div style="display:flex;justify-content:space-between;gap:10px;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
        <span style="font:600 10px var(--gt-mono);color:rgba(200,210,225,0.6);text-transform:uppercase;letter-spacing:0.6px;">${controller._escapeHtml(row.label)}</span>
        <span style="font:500 11px var(--gt-sans);color:#f8fafc;text-align:right;overflow-wrap:anywhere;word-break:break-word;">${controller._escapeHtml(row.value)}</span>
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
    <div style="margin-top:12px;">
      <div style="font:600 9px var(--gt-mono);color:rgba(200,210,225,0.45);letter-spacing:1px;text-transform:uppercase;margin-bottom:6px;">
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
    <div style="font:500 11px var(--gt-sans);color:#f8fafc;line-height:1.35;overflow-wrap:anywhere;word-break:break-word;">${controller._escapeHtml(item.label)}</div>
    ${item.meta ? `<div style="font:500 9px var(--gt-mono);color:rgba(200,210,225,0.45);margin-top:2px;">${controller._escapeHtml(item.meta)}</div>` : ""}
  `

  if (!item.badge) return label

  return `
    <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:10px;">
      <div style="min-width:0;">${label}</div>
      <span class="ins-chip ins-chip--${controller._escapeHtml(item.badge.variant || "eq")}" style="flex-shrink:0;">${controller._escapeHtml(item.badge.label)}</span>
    </div>
  `
}

export function renderContextAction(controller, action) {
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

function renderContextItem(controller, item) {
  const itemBody = renderContextItemBody(controller, item)

  if (item.nodeRequest?.kind && item.nodeRequest?.id) {
    return `
      <div style="padding:6px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
        <button
          type="button"
          data-action="click->globe#selectContextNode"
          data-kind="${controller._escapeHtml(item.nodeRequest.kind)}"
          data-id="${controller._escapeHtml(item.nodeRequest.id)}"
          data-title="${controller._escapeHtml(item.label)}"
          data-summary="${controller._escapeHtml(item.meta || "")}"
          style="display:block;width:100%;padding:0;border:0;background:none;text-align:left;cursor:pointer;"
        >
          ${itemBody}
        </button>
      </div>
    `
  }

  if (item.cameraId) {
    return `
      <div style="padding:6px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
        <button
          type="button"
          data-action="click->globe#openContextCamera"
          data-camera-id="${controller._escapeHtml(item.cameraId)}"
          style="display:block;width:100%;padding:0;border:0;background:none;text-align:left;cursor:pointer;"
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
      <div style="padding:6px 0;border-bottom:1px solid rgba(255,255,255,0.05);">
        <button
          type="button"
          data-action="click->globe#openContextLayer"
          ${layerAttr}
          ${tabAttr}
          ${latAttr}
          ${lngAttr}
          ${heightAttr}
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
        <a href="${controller._safeUrl(item.url)}" target="_blank" rel="noopener" style="display:block;text-decoration:none;">
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
}
