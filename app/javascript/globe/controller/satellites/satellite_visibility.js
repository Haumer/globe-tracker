import { haversineDistance } from "globe/utils"

const SAT_EVENT_MAP = {
  weather: ["fire", "natural", "weather", "earthquake"],
  "gps-ops": ["jamming", "fire", "earthquake"],
  glonass: ["jamming", "fire", "earthquake"],
  galileo: ["jamming", "fire", "earthquake"],
  beidou: ["jamming", "fire", "earthquake"],
  gnss: ["jamming", "fire", "earthquake"],
  sbas: ["jamming"],
  resource: ["fire", "natural", "earthquake"],
  planet: ["fire", "natural", "earthquake", "conflict"],
  radar: ["fire", "natural", "earthquake", "conflict"],
  science: ["fire", "natural", "earthquake"],
  military: ["conflict", "jamming", "fire", "earthquake", "news"],
  analyst: ["conflict", "jamming", "fire", "news"],
  starlink: ["conflict", "natural", "earthquake", "news"],
  iridium: ["conflict", "natural", "news"],
  oneweb: ["conflict", "natural", "news"],
  intelsat: ["conflict", "natural", "news"],
  ses: ["conflict", "natural", "news"],
  globalstar: ["conflict", "natural", "news"],
  sarsat: ["earthquake", "natural", "fire"],
  stations: ["natural", "fire", "earthquake"],
}

const DEFAULT_EVENTS = ["earthquake", "natural", "conflict", "fire", "news", "jamming", "weather"]

const EVENT_ICONS = {
  earthquake: "house-crack",
  natural: "bolt",
  conflict: "crosshairs",
  fire: "fire",
  news: "newspaper",
  jamming: "satellite-dish",
  weather: "cloud-bolt",
}

const EVENT_COLORS = {
  earthquake: "#ff7043",
  natural: "#66bb6a",
  conflict: "#f44336",
  fire: "#ff5722",
  news: "#ff9800",
  jamming: "#ffc107",
  weather: "#42a5f5",
}

const PURPOSE_LABELS = {
  weather: "Weather Detection",
  "gps-ops": "Navigation Monitoring",
  glonass: "Navigation Monitoring",
  galileo: "Navigation Monitoring",
  beidou: "Navigation Monitoring",
  gnss: "Navigation Monitoring",
  military: "ISR Coverage",
  analyst: "Intelligence Collection",
  resource: "Earth Observation",
  planet: "Earth Observation",
  radar: "SAR Imaging",
  sarsat: "Search & Rescue",
  starlink: "Comms Coverage",
  iridium: "Comms Coverage",
  stations: "Observation",
}

export function applySatelliteVisibilityMethods(GlobeController) {
  GlobeController.prototype.showSatVisibility = function(event) {
    if (this._satVisEntities?.length) {
      this._clearSatVisEntities()
      event.currentTarget.classList.remove("tracking")
      return
    }

    const lat = parseFloat(event.currentTarget.dataset.lat)
    const lng = parseFloat(event.currentTarget.dataset.lng)
    if (isNaN(lat) || isNaN(lng)) return

    event.currentTarget.classList.add("tracking")
    this._clearSatVisEntities()
    this._satVisEventPos = { lat, lng }

    const sat = window.satellite
    if (!sat || !this.satelliteData.length) {
      appendStatusMessage(event.currentTarget.parentNode, "Enable satellite categories first to see overhead passes.")
      return
    }

    const Cesium = window.Cesium
    const now = new Date()
    const gmst = sat.gstime(now)
    const observerGd = {
      latitude: lat * Math.PI / 180,
      longitude: lng * Math.PI / 180,
      height: 0,
    }

    const visible = []
    this.satelliteData.forEach(satellite => {
      try {
        const satrec = sat.twoline2satrec(satellite.tle_line1, satellite.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (!posVel.position) return

        const posGd = sat.eciToGeodetic(posVel.position, gmst)
        const satLng = sat.degreesLong(posGd.longitude)
        const satLat = sat.degreesLat(posGd.latitude)
        const satAlt = posGd.height
        if (isNaN(satLng) || isNaN(satLat) || isNaN(satAlt)) return

        const posEcf = sat.eciToEcf(posVel.position, gmst)
        const lookAngles = sat.ecfToLookAngles(observerGd, posEcf)
        const elevation = lookAngles.elevation * 180 / Math.PI
        if (elevation <= 5) return

        visible.push({
          name: satellite.name,
          norad_id: satellite.norad_id,
          category: satellite.category,
          lat: satLat,
          lng: satLng,
          alt: satAlt,
          elevation,
          azimuth: lookAngles.azimuth * 180 / Math.PI,
        })
      } catch {
        // Skip satellites with invalid TLE rows.
      }
    })

    visible.sort((a, b) => b.elevation - a.elevation)
    const top = visible.slice(0, 15)
    renderVisibilityEntities.call(this, Cesium, lat, lng, top)
    renderVisibilityResults.call(this, top)
  }

  GlobeController.prototype._clearSatVisEntities = function() {
    if (!this._satVisEntities?.length) return
    const ds = this._ds["satellites"]
    if (ds) this._satVisEntities.forEach(entity => ds.entities.remove(entity))
    this._satVisEntities = []
    this._satVisEventPos = null
    document.getElementById("satvis-results")?.remove()
    document.getElementById("ground-events-results")?.remove()
  }

  GlobeController.prototype.showGroundEvents = function(event) {
    if (this._satVisEntities?.length) {
      this._clearSatVisEntities()
      event.currentTarget.classList.remove("tracking")
      return
    }

    const noradId = parseInt(event.currentTarget.dataset.norad)
    const satData = this.satelliteData.find(satellite => satellite.norad_id === noradId)
    if (!satData) return

    event.currentTarget.classList.add("tracking")

    const sat = window.satellite
    if (!sat) return

    const Cesium = window.Cesium
    const now = new Date()
    const gmst = sat.gstime(now)
    const satrec = sat.twoline2satrec(satData.tle_line1, satData.tle_line2)
    const posVel = sat.propagate(satrec, now)
    if (!posVel.position) return

    const posGd = sat.eciToGeodetic(posVel.position, gmst)
    const satLat = sat.degreesLat(posGd.latitude)
    const satLng = sat.degreesLong(posGd.longitude)
    const satAltKm = posGd.height
    const footprintKm = Math.sqrt(2 * 6371 * satAltKm)
    const footprintM = footprintKm * 1000
    const relevantTypes = SAT_EVENT_MAP[satData.category] || DEFAULT_EVENTS

    const events = collectGroundEvents.call(this, relevantTypes, satLat, satLng, footprintM)
    events.sort((a, b) => a.dist - b.dist)
    const top = events.slice(0, 20)

    this._clearSatVisEntities()
    renderGroundEventEntities.call(this, Cesium, satData, satLat, satLng, satAltKm, footprintM, top)
    renderGroundEventResults.call(this, satData, footprintKm, top)
  }
}

function appendStatusMessage(parent, message) {
  const msg = document.createElement("div")
  msg.style.cssText = "margin-top:8px;font:400 10px var(--gt-mono);color:#ce93d8;"
  msg.textContent = message
  parent.appendChild(msg)
}

function renderVisibilityEntities(Cesium, eventLat, eventLng, satellites) {
  const dataSource = this.getSatellitesDataSource()

  satellites.forEach((satellite, index) => {
    const color = Cesium.Color.fromCssColorString(this.satCategoryColors[satellite.category] || "#ce93d8").withAlpha(0.5)

    this._satVisEntities.push(dataSource.entities.add({
      id: `satvis-line-${index}`,
      polyline: {
        positions: [
          Cesium.Cartesian3.fromDegrees(satellite.lng, satellite.lat, satellite.alt * 1000),
          Cesium.Cartesian3.fromDegrees(eventLng, eventLat, 0),
        ],
        width: 1.5,
        material: new Cesium.PolylineDashMaterialProperty({
          color,
          dashLength: 16,
        }),
      },
    }))

    this._satVisEntities.push(dataSource.entities.add({
      id: `satvis-lbl-${index}`,
      position: Cesium.Cartesian3.fromDegrees(satellite.lng, satellite.lat, satellite.alt * 1000),
      label: {
        text: `${satellite.name} (${satellite.elevation.toFixed(0)}°)`,
        font: "10px JetBrains Mono, monospace",
        fillColor: color.withAlpha(0.9),
        outlineColor: Cesium.Color.BLACK,
        outlineWidth: 3,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        pixelOffset: new Cesium.Cartesian2(8, 0),
        scaleByDistance: new Cesium.NearFarScalar(1e5, 1, 5e7, 0.3),
        translucencyByDistance: new Cesium.NearFarScalar(1e5, 1, 5e7, 0.1),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    }))
  })

  this._satVisEntities.push(dataSource.entities.add({
    id: "satvis-ground",
    position: Cesium.Cartesian3.fromDegrees(eventLng, eventLat, 0),
    ellipse: {
      semiMinorAxis: 50000,
      semiMajorAxis: 50000,
      material: Cesium.Color.fromCssColorString("#ce93d8").withAlpha(0.1),
      outline: true,
      outlineColor: Cesium.Color.fromCssColorString("#ce93d8").withAlpha(0.4),
      outlineWidth: 1,
      height: 0,
      heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
      classificationType: Cesium.ClassificationType.BOTH,
    },
  }))
}

function renderVisibilityResults(satellites) {
  const listHtml = satellites.length > 0
    ? satellites.map(satellite => {
        const color = this.satCategoryColors[satellite.category] || "#ce93d8"
        return `<div style="display:flex;justify-content:space-between;font:400 10px var(--gt-mono);color:var(--gt-text-dim);padding:1px 0;">
          <span style="color:${color};">${this._escapeHtml(satellite.name)}</span>
          <span>${satellite.elevation.toFixed(0)}° el · ${Math.round(satellite.alt)} km</span>
        </div>`
      }).join("")
    : `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">No satellites currently overhead. Enable more satellite categories.</div>`

  const container = document.createElement("div")
  container.id = "satvis-results"
  container.innerHTML = `
    <div style="margin-top:10px;padding:6px 8px;background:rgba(171,71,188,0.08);border:1px solid rgba(171,71,188,0.25);border-radius:4px;">
      <div style="font:600 9px var(--gt-mono);color:#ce93d8;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">
        <i class="fa-solid fa-satellite" style="margin-right:4px;"></i>${satellites.length} SATELLITES OVERHEAD
      </div>
      ${listHtml}
    </div>
  `

  document.getElementById("satvis-results")?.remove()
  this.detailContentTarget.appendChild(container)
}

function collectGroundEvents(relevantTypes, satLat, satLng, footprintM) {
  const events = []
  const pushIfWithin = (type, items, buildEvent) => {
    if (!relevantTypes.includes(type) || !items?.length) return
    items.forEach(item => {
      const lat = item.lat
      const lng = item.lng
      if (lat == null || lng == null) return
      const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat, lng })
      if (dist <= footprintM) events.push(buildEvent(item, dist))
    })
  }

  pushIfWithin("earthquake", this._earthquakeData, (eq, dist) => ({
    type: "earthquake",
    label: `M${eq.mag.toFixed(1)} ${eq.title}`,
    lat: eq.lat,
    lng: eq.lng,
    dist,
  }))

  pushIfWithin("natural", this._naturalEventData, (event, dist) => ({
    type: "natural",
    label: event.title,
    lat: event.lat,
    lng: event.lng,
    dist,
  }))

  pushIfWithin("conflict", this._conflictData, (conflict, dist) => ({
    type: "conflict",
    label: `${conflict.conflict || "Conflict"} — ${conflict.country || ""}`,
    lat: conflict.lat,
    lng: conflict.lng,
    dist,
  }))

  pushIfWithin("fire", this._fireHotspotData, (fire, dist) => ({
    type: "fire",
    label: `Fire ${fire.lat.toFixed(2)}°, ${fire.lng.toFixed(2)}° (${fire.satellite || "?"})`,
    lat: fire.lat,
    lng: fire.lng,
    dist,
  }))

  if (relevantTypes.includes("jamming") && this._gpsJammingData?.length) {
    this._gpsJammingData.forEach(jamming => {
      if (jamming.level === "low") return
      const dist = haversineDistance({ lat: satLat, lng: satLng }, { lat: jamming.lat, lng: jamming.lng })
      if (dist > footprintM) return
      events.push({
        type: "jamming",
        label: `GPS jamming ${jamming.pct}% (${jamming.level})`,
        lat: jamming.lat,
        lng: jamming.lng,
        dist,
      })
    })
  }

  pushIfWithin("weather", this._weatherAlerts, (weather, dist) => ({
    type: "weather",
    label: `${weather.severity}: ${weather.event}`,
    lat: weather.lat,
    lng: weather.lng,
    dist,
  }))

  pushIfWithin("news", this._newsData, (news, dist) => ({
    type: "news",
    label: news.title || "News",
    lat: news.lat,
    lng: news.lng,
    dist,
  }))

  return events
}

function renderGroundEventEntities(Cesium, satData, satLat, satLng, satAltKm, footprintM, events) {
  const dataSource = this.getSatellitesDataSource()
  const satColor = Cesium.Color.fromCssColorString(this.satCategoryColors[satData.category] || "#ce93d8")

  this._satVisEntities.push(dataSource.entities.add({
    id: "satvis-footprint",
    position: Cesium.Cartesian3.fromDegrees(satLng, satLat, 0),
    ellipse: {
      semiMinorAxis: footprintM,
      semiMajorAxis: footprintM,
      material: satColor.withAlpha(0.04),
      outline: true,
      outlineColor: satColor.withAlpha(0.2),
      outlineWidth: 1,
      height: 0,
      heightReference: Cesium.HeightReference.CLAMP_TO_GROUND,
      classificationType: Cesium.ClassificationType.BOTH,
    },
  }))

  events.forEach((event, index) => {
    const color = Cesium.Color.fromCssColorString(EVENT_COLORS[event.type] || "#ce93d8").withAlpha(0.5)
    this._satVisEntities.push(dataSource.entities.add({
      id: `satvis-gnd-${index}`,
      polyline: {
        positions: [
          Cesium.Cartesian3.fromDegrees(satLng, satLat, satAltKm * 1000),
          Cesium.Cartesian3.fromDegrees(event.lng, event.lat, 0),
        ],
        width: 1.5,
        material: new Cesium.PolylineDashMaterialProperty({ color, dashLength: 16 }),
      },
    }))
  })
}

function renderGroundEventResults(satData, footprintKm, events) {
  const listHtml = events.length > 0
    ? events.map(event => {
        const color = EVENT_COLORS[event.type] || "#ce93d8"
        const icon = EVENT_ICONS[event.type] || "circle"
        const distKm = Math.round(event.dist / 1000)
        return `<div style="display:flex;gap:6px;align-items:start;font:400 10px var(--gt-mono);color:var(--gt-text-dim);padding:2px 0;">
          <i class="fa-solid fa-${icon}" style="color:${color};margin-top:2px;font-size:9px;flex-shrink:0;"></i>
          <span style="flex:1;line-height:1.3;">${this._escapeHtml(event.label)}</span>
          <span style="flex-shrink:0;color:${color};">${distKm} km</span>
        </div>`
      }).join("")
    : `<div style="font:400 10px var(--gt-mono);color:var(--gt-text-dim);">No relevant events in footprint for this ${satData.category} satellite. Enable matching event layers.</div>`

  const purposeLabel = PURPOSE_LABELS[satData.category] || "Ground Events"
  const container = document.createElement("div")
  container.id = "ground-events-results"
  container.innerHTML = `
    <div style="margin-top:10px;padding:6px 8px;background:rgba(171,71,188,0.08);border:1px solid rgba(171,71,188,0.25);border-radius:4px;">
      <div style="font:600 9px var(--gt-mono);color:#ce93d8;letter-spacing:1px;text-transform:uppercase;margin-bottom:4px;">
        <i class="fa-solid fa-crosshairs" style="margin-right:4px;"></i>${events.length} ${purposeLabel.toUpperCase()}
        <span style="font-weight:400;text-transform:none;margin-left:4px;">(${Math.round(footprintKm)} km radius)</span>
      </div>
      ${listHtml}
    </div>
  `

  document.getElementById("ground-events-results")?.remove()
  this.detailContentTarget.appendChild(container)
}
