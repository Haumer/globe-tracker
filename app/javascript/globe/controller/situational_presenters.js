export function renderAirportDetailHtml(controller, icao, airport) {
  const color = airport.military ? "#ef5350" : "#ffd54f"
  const typeLabel = airport.military
    ? "Military"
    : (airport.type || "").replace(/_/g, " ").replace(/\b\w/g, char => char.toUpperCase())

  return `
    <div class="detail-callsign"><i class="fa-solid fa-plane-departure" style="color: ${color};"></i> ${controller._escapeHtml(airport.name || "")}</div>
    <div class="detail-country">${controller._escapeHtml(airport.municipality ? `${airport.municipality}, ` : "")}${controller._escapeHtml(airport.country || "")}</div>
    <div class="detail-grid">
      <div class="detail-field">
        <span class="detail-label">ICAO</span>
        <span class="detail-value">${controller._escapeHtml(icao)}</span>
      </div>
      ${airport.iata ? `<div class="detail-field"><span class="detail-label">IATA</span><span class="detail-value">${controller._escapeHtml(airport.iata)}</span></div>` : ""}
      <div class="detail-field">
        <span class="detail-label">Type</span>
        <span class="detail-value">${controller._escapeHtml(typeLabel)}</span>
      </div>
      ${airport.elevation ? `<div class="detail-field"><span class="detail-label">Elevation</span><span class="detail-value">${airport.elevation.toLocaleString()} ft</span></div>` : ""}
      <div class="detail-field">
        <span class="detail-label">Coordinates</span>
        <span class="detail-value">${airport.lat.toFixed(4)}°, ${airport.lng.toFixed(4)}°</span>
      </div>
    </div>
    <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: OurAirports / FAA</div>
  `
}

export function renderEarthquakeDetailHtml(controller, earthquake) {
  const date = new Date(earthquake.time)
  const ago = controller._timeAgo(date)
  const alertBadge = earthquake.alert ? `<span class="event-alert event-alert-${earthquake.alert}">${earthquake.alert.toUpperCase()}</span>` : ""
  const tsunamiBadge = earthquake.tsunami ? `<span class="event-alert event-alert-tsunami">TSUNAMI</span>` : ""
  const shakeMapButton = earthquake.mag >= 4.0
    ? `<button class="detail-track-btn" style="background:rgba(255,112,67,0.15);border-color:rgba(255,112,67,0.3);color:#ff7043;" data-action="click->globe#toggleShakeMap" data-eq-lat="${earthquake.lat}" data-eq-lng="${earthquake.lng}" data-eq-mag="${earthquake.mag}" data-eq-depth="${earthquake.depth}" data-eq-id="${earthquake.id}">
        <i class="fa-solid fa-bullseye" style="margin-right:4px;"></i>ShakeMap Intensity
      </button>`
    : ""
  const usgsButton = typeof earthquake.url === "string" && /^https?:\/\//i.test(earthquake.url)
    ? `<a href="${controller._safeUrl(earthquake.url)}" target="_blank" rel="noopener" class="detail-track-btn">View on USGS</a>`
    : ""

  return `
    <div class="detail-callsign">M${earthquake.mag.toFixed(1)} Earthquake</div>
    <div class="detail-country">${controller._escapeHtml(earthquake.title)}</div>
    <div class="event-badges">${alertBadge}${tsunamiBadge}</div>
    <div class="detail-grid">
      <div class="detail-field">
        <span class="detail-label">Magnitude</span>
        <span class="detail-value">${earthquake.mag.toFixed(1)} ${controller._escapeHtml(earthquake.magType || "")}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Depth</span>
        <span class="detail-value">${earthquake.depth.toFixed(1)} km</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Time</span>
        <span class="detail-value">${ago}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Coordinates</span>
        <span class="detail-value">${earthquake.lat.toFixed(2)}°, ${earthquake.lng.toFixed(2)}°</span>
      </div>
    </div>
    ${shakeMapButton}
    ${usgsButton}
    <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${earthquake.lat}" data-lng="${earthquake.lng}">
      <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
    </button>
    ${controller._connectionsPlaceholder()}
    <div class="shakemap-infra" data-globe-shakemap-infra style="display:none;"></div>
    <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: USGS Earthquake Hazards Program</div>
  `
}

export function renderNaturalEventDetailHtml(controller, eventItem, categoryInfo) {
  const date = eventItem.date ? new Date(eventItem.date) : null
  const ago = date ? controller._timeAgo(date) : "—"
  const magnitudeLabel = eventItem.magnitudeValue ? `${eventItem.magnitudeValue} ${eventItem.magnitudeUnit || ""}` : "—"
  const sourceLinks = (eventItem.sources || [])
    .filter(source => typeof source.url === "string" && /^https?:\/\//i.test(source.url))
    .map(source => `<a href="${controller._safeUrl(source.url)}" target="_blank" rel="noopener" class="event-source-link">${controller._escapeHtml(source.id)}</a>`)
    .join(" ")

  return `
    <div class="detail-callsign"><i class="fa-solid fa-${categoryInfo.icon}" style="color: ${categoryInfo.color};"></i> ${controller._escapeHtml(eventItem.categoryTitle)}</div>
    <div class="detail-country">${controller._escapeHtml(eventItem.title)}</div>
    <div class="detail-grid">
      <div class="detail-field">
        <span class="detail-label">Category</span>
        <span class="detail-value">${controller._escapeHtml(eventItem.categoryTitle)}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Magnitude</span>
        <span class="detail-value">${controller._escapeHtml(magnitudeLabel)}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Time</span>
        <span class="detail-value">${ago}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Coordinates</span>
        <span class="detail-value">${eventItem.lat.toFixed(2)}°, ${eventItem.lng.toFixed(2)}°</span>
      </div>
      ${eventItem.geometryPoints.length > 1 ? `
      <div class="detail-field">
        <span class="detail-label">Track Points</span>
        <span class="detail-value">${eventItem.geometryPoints.length}</span>
      </div>` : ""}
    </div>
    ${sourceLinks ? `<div class="event-sources">Sources: ${sourceLinks}</div>` : ""}
    ${typeof eventItem.link === "string" && /^https?:\/\//i.test(eventItem.link) ? `<a href="${controller._safeUrl(eventItem.link)}" target="_blank" rel="noopener" class="detail-track-btn">View on NASA EONET</a>` : ""}
    <button class="detail-track-btn" style="background:rgba(171,71,188,0.15);border-color:rgba(171,71,188,0.3);color:#ce93d8;" data-action="click->globe#showSatVisibility" data-lat="${eventItem.lat}" data-lng="${eventItem.lng}">
      <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>Show Overhead Satellites
    </button>
  `
}

export function renderFeaturedCameraCard(controller, camera, originalIndex) {
  const badge = controller._cameraModeBadge(camera)
  const sourceLabel = controller._cameraSourceLabel(camera)
  const location = [camera.city, camera.country].filter(Boolean).join(", ")
  const thumbUrl = controller._cameraThumbUrl(camera)
  const watchUrl = controller._cameraWatchUrl(camera)
  const freshness = controller._cameraFreshnessLabel(camera)
  const title = controller._escapeHtml(camera.title || "Untitled camera")
  const locationHtml = location ? `<span>${controller._escapeHtml(location)}</span>` : ""
  const viewCount = camera.viewCount ? `<span>${camera.viewCount.toLocaleString()} watching</span>` : ""

  return `<div class="cam-hero-card" data-action="click->globe#focusCamFeedItem" data-cam-idx="${originalIndex}">
    <div class="cam-hero-media">
      ${thumbUrl
        ? `<img src="${thumbUrl}" alt="${title}" loading="lazy">`
        : `<div class="cam-hero-placeholder">Live observation unavailable</div>`}
      <div class="cam-hero-badges">
        <span class="ins-chip ins-chip--${controller._cameraModeChipClass(camera)}">${badge.label}</span>
        <span class="ins-chip ins-chip--news">${controller._escapeHtml(sourceLabel)}</span>
      </div>
    </div>
    <div class="cam-hero-body">
      <div class="cam-hero-title">${title}</div>
      <div class="cam-hero-meta">
        ${locationHtml}
        <span>${controller._escapeHtml(freshness)}</span>
        ${viewCount}
      </div>
      <div class="cam-hero-actions">
        <button class="insight-action-btn" data-action="click->globe#focusCamFeedItem" data-cam-idx="${originalIndex}">Focus</button>
        ${watchUrl ? `<button class="insight-action-btn" data-action="click->globe#openCamStream" data-cam-idx="${originalIndex}">Watch</button>` : ""}
      </div>
    </div>
  </div>`
}

export function renderCameraListCard(controller, camera, originalIndex) {
  const badge = controller._cameraModeBadge(camera)
  const sourceLabel = controller._cameraSourceLabel(camera)
  const sourceColor = controller._cameraSourceColor(camera)
  const location = [camera.city, camera.country].filter(Boolean).join(", ")
  const thumbUrl = controller._cameraThumbUrl(camera)
  const title = controller._escapeHtml(camera.title || "Untitled camera")
  const freshness = controller._cameraFreshnessLabel(camera)

  return `<div class="cf-card" data-action="click->globe#focusCamFeedItem" data-cam-idx="${originalIndex}">
    <div class="cf-card-bar" style="background:${sourceColor};"></div>
    ${thumbUrl
      ? `<img class="cf-card-thumb" src="${thumbUrl}" alt="${title}" loading="lazy">`
      : `<div class="cf-card-thumb cf-card-thumb--placeholder">${controller._escapeHtml(sourceLabel)}</div>`}
    <div class="cf-card-body">
      <div class="cf-card-topline">
        <span class="cf-card-source">${controller._escapeHtml(sourceLabel)}</span>
        <span class="ins-chip ins-chip--${controller._cameraModeChipClass(camera)}">${badge.label}</span>
      </div>
      <div class="cf-card-title">${title}</div>
      <div class="cf-card-meta">
        ${location ? `<span class="cf-card-location">${controller._escapeHtml(location)}</span>` : ""}
        <span class="cf-card-updated">${controller._escapeHtml(freshness)}</span>
      </div>
    </div>
  </div>`
}

export function renderWebcamDetailHtml(controller, camera, thumbHtml, watchUrl, detail) {
  return `
    <div class="detail-callsign"><i class="fa-solid fa-video" style="color: ${camera.live ? "#4caf50" : "#29b6f6"};"></i> ${detail.sourceLabel}${detail.liveBadge}</div>
    <div class="detail-country">${controller._escapeHtml(camera.title)}</div>
    <div style="display:flex;flex-wrap:wrap;gap:4px;margin:8px 0 10px;">
      ${controller._statusChip(camera.stale ? "stale" : "ready", camera.stale ? "stale camera cache" : "cached camera")}
    </div>
    ${thumbHtml}
    <div class="detail-grid">
      <div class="detail-field">
        <span class="detail-label">Observation</span>
        <span class="detail-value">${detail.modeBadge.label}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Location</span>
        <span class="detail-value">${controller._escapeHtml(detail.location) || "—"}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Updated</span>
        <span class="detail-value">${detail.updated}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Freshness</span>
        <span class="detail-value">${controller._escapeHtml(detail.freshnessLabel)}</span>
      </div>
      <div class="detail-field">
        <span class="detail-label">Cache</span>
        <span class="detail-value">${camera.stale ? "Stale" : "Fresh"}</span>
      </div>
      ${camera.channelTitle ? `<div class="detail-field">
        <span class="detail-label">Channel</span>
        <span class="detail-value">${controller._escapeHtml(camera.channelTitle)}</span>
      </div>` : ""}
      ${camera.viewCount ? `<div class="detail-field">
        <span class="detail-label">Views</span>
        <span class="detail-value">${camera.viewCount.toLocaleString()}</span>
      </div>` : ""}
      <div class="detail-field">
        <span class="detail-label">Coordinates</span>
        <span class="detail-value">${camera.lat.toFixed(3)}°, ${camera.lng.toFixed(3)}°</span>
      </div>
    </div>
    <a href="${watchUrl}" target="_blank" rel="noopener" class="detail-track-btn"><i class="fa-solid fa-${camera.playerLink ? "play" : "arrow-up-right-from-square"}"></i> ${camera.playerLink ? "Watch Live" : "View Source"}</a>
    <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: ${controller._escapeHtml(detail.sourceLabel)}${detail.cacheMeta ? ` · ${controller._escapeHtml(detail.cacheMeta)}` : ""}</div>
  `
}
