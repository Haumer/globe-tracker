// Detail panel HTML renderers for each entity type.
// Usage:
//   import { renderDetailHTML, detailField } from "../globe/details"
//   this.detailContentTarget.innerHTML = renderDetailHTML("flight", { ... })

/**
 * Generates a single detail-field block.
 * @param {string} label
 * @param {string} value
 * @param {string} [style] - optional inline style for the value span
 * @returns {string} HTML string
 */
export function detailField(label, value, style) {
  const styleAttr = style ? ` style="${style}"` : ""
  return `<div class="detail-field">
  <span class="detail-label">${label}</span>
  <span class="detail-value"${styleAttr}>${value}</span>
</div>`
}

/**
 * Wraps an array of detail-field strings in the standard grid container.
 */
function detailGrid(fields) {
  return `<div class="detail-grid">${fields.join("")}</div>`
}

/**
 * Standard header: title line + subtitle line.
 */
function detailHeader(title, subtitle) {
  return `<div class="detail-callsign">${title}</div>
<div class="detail-country">${subtitle}</div>`
}

/**
 * Renders a row of external links.
 */
function detailLinks(links) {
  const items = links
    .filter(l => l.url)
    .map(l => `<a href="${l.url}" target="_blank" rel="noopener">${l.label}</a>`)
    .join("")
  return items ? `<div class="detail-links">${items}</div>` : ""
}

// ── Per-type renderers ──────────────────────────────────────

function renderFlight(data) {
  const callsign = data.callsign || data.id
  const alt = data.currentAlt
  const speed = data.speed
  const heading = data.heading
  const vrate = data.verticalRate || 0

  let vrateDisplay = "\u2014"
  if (vrate > 0.5) vrateDisplay = `+${Math.round(vrate)} m/s \u2191`
  else if (vrate < -0.5) vrateDisplay = `${Math.round(vrate)} m/s \u2193`
  else if (!data.onGround) vrateDisplay = "Level"

  const isTracking = !!data._isTracking

  const fields = [
    detailField("Altitude", alt ? Math.round(alt).toLocaleString() + " m" : "\u2014"),
    detailField("Speed", speed ? Math.round(speed * 3.6) + " km/h" : "\u2014"),
    detailField("Heading", heading ? Math.round(heading) + "\u00b0" : "\u2014"),
    detailField("V/S", vrateDisplay),
    detailField("ICAO24", data.id, "font-size:12px; opacity:0.7;"),
    detailField("Status", data.onGround ? "On Ground" : "Airborne"),
  ]
  if (data.registration) fields.push(detailField("Reg", data.registration))
  if (data.aircraftType) fields.push(detailField("Type", data.aircraftType))
  fields.push(detailField("Source", data.source === "adsb" ? "ADS-B Exchange" : "OpenSky", "font-size:11px;"))

  return [
    detailHeader(callsign || data.id, data.originCountry || "Unknown"),
    `<div class="detail-route" id="detail-route">Loading route...</div>`,
    detailGrid(fields),
    detailLinks([
      { url: `https://www.flightradar24.com/${callsign}`, label: "FR24" },
      { url: `https://www.flightaware.com/live/flight/${callsign}`, label: "FlightAware" },
      { url: `https://globe.adsbexchange.com/?icao=${data.id}`, label: "ADS-B" },
    ]),
    `<button class="detail-track-btn ${isTracking ? "tracking" : ""}" data-flight-id="${data.id}">
  ${isTracking ? "Stop Tracking" : "Track Flight"}
</button>`,
  ].join("\n")
}

function renderShip(data) {
  const speedKnots = data.speed ? Math.round(data.speed * 10) / 10 + " kn" : "\u2014"
  const courseDisplay = data.course ? Math.round(data.course) + "\u00b0" : "\u2014"
  const headingDisplay = data.heading ? Math.round(data.heading) + "\u00b0" : "\u2014"
  const mmsi = data.mmsi

  return [
    detailHeader(data.name, data.flag || "Unknown flag"),
    detailGrid([
      detailField("Type", data.shipTypeName || "\u2014"),
      detailField("Speed", speedKnots),
      detailField("Course", courseDisplay),
      detailField("Heading", headingDisplay),
      detailField("MMSI", mmsi, "font-size:12px; opacity:0.7;"),
      detailField("Destination", data.destination || "\u2014"),
    ]),
    detailLinks([
      { url: `https://www.marinetraffic.com/en/ais/details/ships/mmsi:${mmsi}`, label: "MarineTraffic" },
      { url: `https://www.vesselfinder.com/vessels?mmsi=${mmsi}`, label: "VesselFinder" },
    ]),
  ].join("\n")
}

function renderSatellite(data) {
  const fields = [
    detailField("NORAD ID", data.norad_id),
    detailField("Altitude", data.altKm || "\u2014"),
    detailField("Speed", data.speedKms || "\u2014"),
    detailField("Category", data.category),
  ]

  let footprintBtn = ""
  if (data.showFootprintToggle) {
    footprintBtn = `<button class="detail-track-btn ${data.satFootprintCountryMode ? 'tracking' : ''}"
        data-action="click->globe#toggleSatFootprintCountryMode">
  ${data.satFootprintCountryMode ? 'Show Radial Footprint' : 'Map to Selected Countries'}
</button>`
  }

  return [
    detailHeader(data.name, data.category.toUpperCase()),
    detailGrid(fields),
    footprintBtn,
  ].join("\n")
}

function renderAirport(data) {
  return [
    detailHeader(
      `<i class="fa-solid fa-plane-departure" style="color: #ffd54f;"></i> ${data.name}`,
      data.icao
    ),
    detailGrid([
      detailField("ICAO", data.icao),
      detailField("Coordinates", `${data.lat.toFixed(2)}\u00b0, ${data.lng.toFixed(2)}\u00b0`),
    ]),
  ].join("\n")
}

function renderEarthquake(data) {
  const alertBadge = data.alert
    ? `<span class="event-alert event-alert-${data.alert}">${data.alert.toUpperCase()}</span>`
    : ""
  const tsunamiBadge = data.tsunami
    ? `<span class="event-alert event-alert-tsunami">TSUNAMI</span>`
    : ""

  const usgsLink = (typeof data.url === "string" && data.url.startsWith("http"))
    ? `<a href="${data.url}" target="_blank" rel="noopener" class="detail-track-btn">View on USGS</a>`
    : ""

  return [
    detailHeader(`M${data.mag.toFixed(1)} Earthquake`, data.title),
    `<div class="event-badges">${alertBadge}${tsunamiBadge}</div>`,
    detailGrid([
      detailField("Magnitude", `${data.mag.toFixed(1)} ${data.magType}`),
      detailField("Depth", `${data.depth.toFixed(1)} km`),
      detailField("Time", data.ago),
      detailField("Coordinates", `${data.lat.toFixed(2)}\u00b0, ${data.lng.toFixed(2)}\u00b0`),
    ]),
    usgsLink,
  ].join("\n")
}

function renderEvent(data) {
  const fields = [
    detailField("Category", data.categoryTitle),
    detailField("Magnitude", data.magStr),
    detailField("Time", data.ago),
    detailField("Coordinates", `${data.lat.toFixed(2)}\u00b0, ${data.lng.toFixed(2)}\u00b0`),
  ]
  if (data.trackPoints > 1) {
    fields.push(detailField("Track Points", data.trackPoints))
  }

  const sourceLinks = (data.sourceLinks || "")
  const sourcesHtml = sourceLinks ? `<div class="event-sources">Sources: ${sourceLinks}</div>` : ""

  const eonetLink = (typeof data.link === "string" && data.link.startsWith("http"))
    ? `<a href="${data.link}" target="_blank" rel="noopener" class="detail-track-btn">View on NASA EONET</a>`
    : ""

  return [
    detailHeader(
      `<i class="fa-solid fa-${data.catIcon}" style="color: ${data.catColor};"></i> ${data.categoryTitle}`,
      data.title
    ),
    detailGrid(fields),
    sourcesHtml,
    eonetLink,
  ].join("\n")
}

function renderWebcam(data) {
  const thumbHtml = data.thumbnail
    ? `<div class="webcam-thumb"><img src="${data.thumbnail}" alt="${data.title}" loading="lazy"></div>`
    : ""

  const watchUrl = (typeof data.playerLink === "string" && data.playerLink.startsWith("http"))
    ? data.playerLink
    : `https://www.windy.com/webcams/${data.id}`

  return [
    detailHeader(
      `<i class="fa-solid fa-video" style="color: #29b6f6;"></i> Webcam`,
      data.title
    ),
    thumbHtml,
    detailGrid([
      detailField("Location", data.location || "\u2014"),
      detailField("Updated", data.updated || "\u2014"),
      detailField("Views", (data.viewCount || 0).toLocaleString()),
      detailField("Coordinates", `${data.lat.toFixed(3)}\u00b0, ${data.lng.toFixed(3)}\u00b0`),
    ]),
    `<a href="${watchUrl}" target="_blank" rel="noopener" class="detail-track-btn"><i class="fa-solid fa-play"></i> Watch Live</a>`,
  ].join("\n")
}

function renderBorder(data) {
  const countryList = data.countryList
  const count = data.countryCount

  return [
    detailHeader("Selected Countries", `${count} countries`),
    `<div class="detail-country-list">${countryList}</div>`,
    `<div class="detail-border-actions">
  <button class="detail-track-btn" id="draw-circle-btn">
    <i class="fa-solid fa-circle-dot"></i> Draw Circle
  </button>
  <button class="detail-track-btn" id="clear-selection-btn">Clear Selection</button>
</div>`,
  ].join("\n")
}

// ── Main dispatcher ─────────────────────────────────────────

const renderers = {
  flight: renderFlight,
  ship: renderShip,
  satellite: renderSatellite,
  airport: renderAirport,
  earthquake: renderEarthquake,
  event: renderEvent,
  webcam: renderWebcam,
  border: renderBorder,
}

/**
 * Returns the detail panel HTML for the given entity type.
 * @param {"flight"|"ship"|"satellite"|"airport"|"earthquake"|"event"|"webcam"|"border"} type
 * @param {Object} data - entity data (shape depends on type)
 * @returns {string} HTML string
 */
export function renderDetailHTML(type, data) {
  const fn = renderers[type]
  if (!fn) throw new Error(`Unknown detail type: ${type}`)
  return fn(data)
}
