// The live-data layers for one selected situation.
//
// The main globe already ingests flights, ships, fire hotspots, webcams,
// satellites, conflict events, earthquakes, weather alerts, NOTAMs, bases and
// infrastructure. This module puts them on the situations globe one situation
// at a time: the server's layer plan (/api/situations/:id/layers) says which
// layers matter here and exactly what to fetch; this class fetches, draws,
// re-polls the live ones, and owns the chip bar + panel sections.
//
// The user's toggle always wins. Overrides live for the session, keyed by
// layer, so turning fires off once keeps them off on the next selection.

import { createPlaneIcon } from "globe/utils"

const CHIP_CONTAINER_ID = "sit-layer-chips"
const SECTIONS_CONTAINER_ID = "sit-layer-sections"

const SATELLITE_JS_URL = "https://cdn.jsdelivr.net/npm/satellite.js@5.0.0/dist/satellite.min.js"

// Render caps. Every cap that can drop data is reported in the layer's count
// line, so a clipped view never reads as a complete one.
const MAX_AIRCRAFT = 400
const MAX_SHIPS = 600
const MAX_FIRES = 800
const MAX_CONFLICT_EVENTS = 500
const MAX_BASES = 300
const MAX_NOTAMS = 100
const LABEL_BUDGET = 40

// Satellite pass search: a day ahead, minute steps, and a pass counts once the
// satellite is well above the horizon rather than skimming it.
const PASS_LOOKAHEAD_HOURS = 24
const PASS_STEP_SECONDS = 60
const PASS_MIN_ELEVATION_DEG = 25
const PASS_MAX_SATELLITES = 150
const PASS_LIST_LIMIT = 10
// A LEO imaging pass lasts minutes. Anything above the horizon longer than
// this is geostationary or highly elliptical -- a continuous watcher, not a
// pass -- and one SBIRS bird "overhead now" forever would crowd every real
// pass off the list.
const PASS_MAX_MINUTES = 45

const LAYER_COLORS = {
  aircraft: "#9fd8ff",
  aircraftMilitary: "#ff7043",
  ships: "#7ee0c3",
  shipsNaval: "#ff7043",
  fires: "#ff6a3d",
  firesStrike: "#ff2d00",
  webcams: "#c792ea",
  conflict: "#e05f5f",
  quakes: "#ffd24d",
  weather: "#ffe082",
  notams: "#ef5350",
  bases: "#90a4ae",
  pipelines: "#b0847a",
  cables: "#4dd0e1",
  boundary: "#ffc44d",
}

export class SituationLayerManager {
  constructor(viewer) {
    this.viewer = viewer
    this._ds = null
    this._plan = null
    this._situation = null
    this._entities = new Map()   // key -> [entity]
    this._timers = new Map()     // key -> interval id
    this._sections = new Map()   // key -> html string for the dossier
    this._notes = new Map()      // key -> one-line count note for the chip row
    this._overrides = new Map()  // key -> bool, survives across selections
    this._on = new Set()         // keys currently enabled
    this._epoch = 0              // bumped on every (de)activate to drop stale fetches
    this._trackedFlightId = null // icao24 the camera is following, if any
    this._trackedShipId = null   // mmsi the camera is following, if any
    this._planeIcons = new Map() // color -> canvas, drawn once
    // The page sets this to hear whether the boundary layer drew a polygon
    // over the anchor -- the nominal footprint circle is redundant then.
    this.onBoundaryState = null
  }

  async activate(situation) {
    this.deactivate()
    this._chipsExpanded = false
    const epoch = ++this._epoch
    this._situation = situation

    let plan
    try {
      const resp = await fetch(`/api/situations/${situation.id}/layers`)
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
      plan = await resp.json()
    } catch (error) {
      console.error("Layer plan fetch failed", error)
      this._renderChipsError()
      return null
    }
    if (epoch !== this._epoch) return null

    this._plan = plan
    await this._ensureDataSource()
    this._renderChips()

    for (const layer of plan.layers) {
      const wanted = this._overrides.has(layer.key)
        ? this._overrides.get(layer.key)
        : (layer.baseline || layer.on_by_default)
      if (wanted && layer.status === "ready") this._enable(layer, epoch)
    }
    return plan
  }

  deactivate() {
    this._epoch++
    this._trackedFlightId = null
    this._trackedShipId = null
    this._timers.forEach((timer) => clearInterval(timer))
    this._timers.clear()
    this._entities.forEach((list) => list.forEach((entity) => this._ds?.entities.remove(entity)))
    this._entities.clear()
    this._on.clear()
    this._sections.clear()
    this._notes.clear()
    this._plan = null
    this._situation = null
    const chips = document.getElementById(CHIP_CONTAINER_ID)
    if (chips) chips.innerHTML = ""
    const sections = document.getElementById(SECTIONS_CONTAINER_ID)
    if (sections) sections.innerHTML = ""
    this._requestRender()
  }

  toggle(key) {
    const layer = this._plan?.layers.find((l) => l.key === key)
    if (!layer || layer.status !== "ready") return

    const on = this._on.has(key)
    this._overrides.set(key, !on)
    if (on) this._disable(key)
    else this._enable(layer, this._epoch)
    this._renderChips()
  }

  // ── plumbing ──────────────────────────────────────────────────────────

  async _ensureDataSource() {
    if (this._ds) return
    const Cesium = window.Cesium
    this._ds = new Cesium.CustomDataSource("situation-layers")
    await this.viewer.dataSources.add(this._ds)
  }

  async _enable(layer, epoch) {
    this._on.add(layer.key)
    await this._refresh(layer, epoch)
    if (layer.refresh_seconds > 0 && epoch === this._epoch) {
      const timer = setInterval(() => this._refresh(layer, epoch), layer.refresh_seconds * 1000)
      this._timers.set(layer.key, timer)
    }
    this._renderChips()
  }

  _disable(key) {
    this._on.delete(key)
    const timer = this._timers.get(key)
    if (timer) clearInterval(timer)
    this._timers.delete(key)
    this._clearEntities(key)
    this._sections.delete(key)
    this._notes.delete(key)
    if (key === "boundaries") this.onBoundaryState?.({ anchorPolygon: false })
    if (key === "aircraft") this._trackedFlightId = null
    if (key === "ships") this._trackedShipId = null
    this._renderSections()
    this._requestRender()
  }

  _clearEntities(key) {
    const list = this._entities.get(key) || []
    list.forEach((entity) => this._ds.entities.remove(entity))
    this._entities.delete(key)
  }

  async _refresh(layer, epoch) {
    let payloads
    try {
      payloads = await Promise.all(layer.sources.map((source) => this._json(source.url, source.params)))
    } catch (error) {
      console.error(`Layer ${layer.key} fetch failed`, error)
      this._notes.set(layer.key, "fetch failed")
      this._renderChips()
      return
    }
    if (epoch !== this._epoch) return

    this._clearEntities(layer.key)
    this._sections.delete(layer.key)
    this._notes.delete(layer.key)

    const renderer = this._renderers()[layer.kind]
    if (renderer) await renderer.call(this, layer, payloads)

    this._renderSections()
    this._renderChips()
    this._requestRender()
  }

  async _json(url, params) {
    const qs = new URLSearchParams(params || {}).toString()
    const resp = await fetch(qs ? `${url}?${qs}` : url)
    if (!resp.ok) throw new Error(`${url} → HTTP ${resp.status}`)
    return resp.json()
  }

  _add(key, options) {
    // Every entity carries the situation id: the page's picking treats an
    // untagged pick as "clicked empty space" and closes the dossier, which
    // must not happen when the click landed on the layer data the dossier
    // just introduced.
    const entity = this._ds.entities.add(options)
    entity.situationId = this._situation?.id
    if (!this._entities.has(key)) this._entities.set(key, [])
    this._entities.get(key).push(entity)
    return entity
  }

  _requestRender() {
    this.viewer?.scene.requestRender()
  }

  _inBbox(lat, lng, pad = 0) {
    const box = this._plan?.bbox
    if (!box || lat == null || lng == null) return false
    return lat <= box.north + pad && lat >= box.south - pad &&
      lng <= box.east + pad && lng >= box.west - pad
  }

  _distanceKm(lat, lng) {
    const anchor = this._plan?.anchor
    if (!anchor || lat == null) return null
    return haversineKm(anchor.lat, anchor.lng, lat, lng)
  }

  // Proximity as brightness: a datum on top of the anchor draws at full
  // strength, one at the corner of the box at less than half. The box admits
  // it; the distance says how much it matters.
  _proximityAlpha(base, lat, lng) {
    const distance = this._distanceKm(lat, lng)
    if (distance == null) return base
    const reach = (this._plan?.radius_km || 150) * 1.45 // box corner
    return base * (0.4 + 0.6 * Math.max(0, 1 - distance / reach))
  }

  // ── renderers ─────────────────────────────────────────────────────────

  _renderers() {
    return {
      boundaries: this._renderBoundaries,
      aircraft: this._renderAircraft,
      ships: this._renderShips,
      fires: this._renderFires,
      webcams: this._renderWebcams,
      conflict_events: this._renderConflictEvents,
      earthquakes: this._renderEarthquakes,
      weather_alerts: this._renderWeatherAlerts,
      notams: this._renderNotams,
      military_bases: this._renderMilitaryBases,
      infrastructure: this._renderInfrastructure,
      satellites: this._renderSatellites,
    }
  }

  // The boundary that contains the anchor, drawn instead of guessed at --
  // plus the regions the curator judged affected, shaded by grade. District
  // boundaries are tried first (finer), admin1 as the fallback; if neither
  // polygon set contains the anchor and no named region matches, the layer
  // says so and draws nothing, because highlighting the wrong district is
  // worse than a circle.
  async _renderBoundaries(layer, payloads) {
    const anchor = this._plan.anchor
    const [districts, admin1] = payloads
    const drawnNames = new Set()

    // The curator names affected regions ("Hormozgan", "Balochistan") with a
    // grade; matching is by normalized name against both polygon sets, and a
    // region that matches nothing is skipped rather than guessed at -- but
    // counted, so the note admits what could not be drawn.
    let shaded = 0
    let unmatched = 0
    ;(this._plan.regions || []).forEach((region) => {
      const feature = this._featureByName(districts, region.name) || this._featureByName(admin1, region.name)
      if (!feature) { unmatched++; return }

      // Two visibly different shades: heavy fill for high impact, light for
      // moderate. Anything fainter disappears against the dark basemap.
      const high = region.impact === "high"
      this._drawBoundaryFeature(layer.key, feature, {
        fillAlpha: high ? 0.3 : 0.14,
        outlineAlpha: high ? 1.0 : 0.7,
        width: high ? 2.5 : 2,
      })
      drawnNames.add(normalizeName(featureName(feature)))
      shaded++
    })

    const feature = this._containingFeature(districts, anchor) || this._containingFeature(admin1, anchor)
    let anchorName = null
    if (feature && !drawnNames.has(normalizeName(featureName(feature)))) {
      this._drawBoundaryFeature(layer.key, feature, { fillAlpha: 0.05, outlineAlpha: 0.85, width: 2 })
      anchorName = featureName(feature)
    } else if (feature) {
      anchorName = featureName(feature)
    }

    // The page hides the nominal footprint circle once a real polygon covers
    // the anchor -- an accurate boundary beats a radius guess.
    this.onBoundaryState?.({ anchorPolygon: !!feature })

    if (!anchorName && !shaded) {
      this._notes.set(layer.key, "no polygon contains the anchor")
      return
    }
    this._notes.set(layer.key, [
      anchorName,
      shaded ? `${shaded} affected shaded` : null,
      unmatched ? `${unmatched} unmatched` : null,
    ].filter(Boolean).join(" · "))
  }

  _drawBoundaryFeature(key, feature, { fillAlpha, outlineAlpha, width }) {
    const Cesium = window.Cesium
    this._outerRings(feature.geometry).forEach((ring) => {
      const positions = ring.map(([lng, lat]) => Cesium.Cartesian3.fromDegrees(lng, lat))
      this._add(key, {
        polygon: {
          hierarchy: new Cesium.PolygonHierarchy(positions),
          material: Cesium.Color.fromCssColorString(LAYER_COLORS.boundary).withAlpha(fillAlpha),
          height: 0,
        },
      })
      this._add(key, {
        polyline: {
          positions: positions,
          width: width,
          material: Cesium.Color.fromCssColorString(LAYER_COLORS.boundary).withAlpha(outlineAlpha),
          clampToGround: false,
        },
      })
    })
  }

  _featureByName(collection, name) {
    const wanted = normalizeName(name)
    if (!wanted) return null
    // An exact match anywhere in the collection beats a substring match: with
    // both "Gaza Strip" and "Gaza Governorate" present, "Gaza" must not settle
    // for whichever happens to come first.
    const features = collection?.features || []
    const candidatesOf = (feature) => featureNames(feature).map(normalizeName).filter(Boolean)
    return features.find((feature) => candidatesOf(feature).some((c) => c === wanted)) ||
      features.find((feature) => candidatesOf(feature).some((c) => c.includes(wanted) || wanted.includes(c)))
  }

  async _renderAircraft(layer, payloads) {
    const Cesium = window.Cesium
    const flights = (payloads[0] || []).slice(0, MAX_AIRCRAFT)
    const labelled = flights.length <= LABEL_BUDGET
    let tracked = null

    flights.forEach((flight) => {
      if (flight.latitude == null || flight.longitude == null) return
      const military = !!flight.military
      const color = military ? LAYER_COLORS.aircraftMilitary : LAYER_COLORS.aircraft
      const isTracked = this._trackedFlightId && flight.icao24 === this._trackedFlightId
      if (isTracked) tracked = flight

      const entity = this._add(layer.key, {
        position: Cesium.Cartesian3.fromDegrees(flight.longitude, flight.latitude),
        billboard: {
          image: this._planeIcon(color),
          scale: isTracked ? 1.1 : 0.7,
          rotation: Cesium.Math.toRadians(-(flight.heading || 0)),
          alignedAxis: Cesium.Cartesian3.UNIT_Z,
          color: Cesium.Color.WHITE.withAlpha(flight.on_ground ? 0.35 : 1),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: (isTracked || (labelled && flight.callsign))
          ? layerLabel((flight.callsign || flight.icao24 || "").trim(), color)
          : undefined,
      })
      // Clicking a plane tracks it; the page's pick handler reads this tag.
      entity.flightRef = {
        icao24: flight.icao24, callsign: flight.callsign,
        latitude: flight.latitude, longitude: flight.longitude,
      }
    })

    // Keep the camera on the tracked plane as positions refresh; a plane that
    // left the box (or landed) releases the camera rather than pinning it to
    // its last known position.
    if (this._trackedFlightId) {
      if (tracked) this._followTarget(tracked)
      else this._trackedFlightId = null
    }

    const military = flights.filter((f) => f.military).length
    this._notes.set(layer.key, `${flights.length}${flights.length === MAX_AIRCRAFT ? "+" : ""} aloft` +
      (military ? ` · ${military} military` : "") +
      (tracked ? ` · tracking ${(tracked.callsign || tracked.icao24 || "").trim()}` : ""))
  }

  // Toggle: clicking the tracked plane again lets go; clicking another plane
  // switches to it.
  trackFlight(ref) {
    if (!ref?.icao24 || this._trackedFlightId === ref.icao24) {
      this._trackedFlightId = null
      this._renderChips()
      return
    }
    this._trackedFlightId = ref.icao24
    this._followTarget(ref, { approach: true })
    this._renderChips()
  }

  _followTarget(target, { approach = false } = {}) {
    const Cesium = window.Cesium
    if (target.latitude == null || target.longitude == null) return
    const current = this.viewer.camera.positionCartographic.height
    // First click swoops in; refreshes keep whatever height the user chose.
    const height = approach ? Math.min(current, 150_000) : current
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(target.longitude, target.latitude, Math.max(height, 20_000)),
      duration: approach ? 1.4 : 1.0,
    })
  }

  _planeIcon(color) {
    if (!this._planeIcons.has(color)) this._planeIcons.set(color, createPlaneIcon(color))
    return this._planeIcons.get(color)
  }

  async _renderShips(layer, payloads) {
    const Cesium = window.Cesium
    const ships = (payloads[0] || []).slice(0, MAX_SHIPS)
    const labelled = ships.length <= LABEL_BUDGET / 2
    let tracked = null

    ships.forEach((ship) => {
      const naval = /military|naval|warship|law/i.test(ship.ship_type || "")
      const color = naval ? LAYER_COLORS.shipsNaval : LAYER_COLORS.ships
      const isTracked = this._trackedShipId && ship.mmsi === this._trackedShipId
      if (isTracked) tracked = ship

      const entity = this._add(layer.key, {
        position: Cesium.Cartesian3.fromDegrees(ship.longitude, ship.latitude),
        point: {
          pixelSize: isTracked ? 7 : naval ? 5 : 3.5,
          color: Cesium.Color.fromCssColorString(color).withAlpha(0.9),
          outlineColor: isTracked ? Cesium.Color.WHITE.withAlpha(0.9) : Cesium.Color.TRANSPARENT,
          outlineWidth: isTracked ? 1.5 : 0,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: (isTracked || (labelled && ship.name)) ? layerLabel(ship.name || String(ship.mmsi), color) : undefined,
      })
      entity.shipRef = {
        mmsi: ship.mmsi, name: ship.name,
        latitude: ship.latitude, longitude: ship.longitude,
      }
    })

    if (this._trackedShipId) {
      if (tracked) this._followTarget(tracked)
      else this._trackedShipId = null
    }

    const naval = ships.filter((s) => /military|naval|warship|law/i.test(s.ship_type || "")).length
    this._notes.set(layer.key, ships.length
      ? `${ships.length}${ships.length === MAX_SHIPS ? "+" : ""} underway` + (naval ? ` · ${naval} naval` : "") +
        (tracked ? ` · tracking ${tracked.name || tracked.mmsi}` : "")
      : "none in the box")
  }

  trackShip(ref) {
    if (!ref?.mmsi || this._trackedShipId === ref.mmsi) {
      this._trackedShipId = null
      this._renderChips()
      return
    }
    this._trackedShipId = ref.mmsi
    this._followTarget(ref, { approach: true })
    this._renderChips()
  }

  // FireHotspot rows arrive as arrays:
  // [id, lat, lng, brightness, confidence, satellite, instrument, frp,
  //  daynight, acq_ms, possible_strike]
  async _renderFires(layer, payloads) {
    const Cesium = window.Cesium
    // The server already scoped to the box and the situation's window; what is
    // left to assess is quality and nearness. Low-confidence pixels are noise
    // at this zoom — unless they are flagged possible strikes, which are the
    // one thing this layer exists to not miss.
    const rows = (payloads[0] || []).filter((r) => r[10] === 1 || fireConfidence(r[4]) >= 30)
    const dropped = (payloads[0] || []).length - rows.length
    const shown = rows.slice(0, MAX_FIRES)

    shown.forEach((row) => {
      const strike = row[10] === 1
      const frp = Number(row[7]) || 0
      const alpha = strike ? 1 : this._proximityAlpha(0.75, row[1], row[2])
      this._add(layer.key, {
        position: Cesium.Cartesian3.fromDegrees(row[2], row[1]),
        point: {
          pixelSize: Math.min(3 + frp / 40, 8),
          color: Cesium.Color.fromCssColorString(strike ? LAYER_COLORS.firesStrike : LAYER_COLORS.fires)
            .withAlpha(alpha),
          outlineColor: strike ? Cesium.Color.WHITE.withAlpha(0.9) : Cesium.Color.TRANSPARENT,
          outlineWidth: strike ? 1.5 : 0,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
    })

    const strikes = shown.filter((r) => r[10] === 1).length
    this._notes.set(layer.key, shown.length
      ? `${shown.length}${rows.length > shown.length ? "+" : ""} hotspots` +
        (strikes ? ` · ${strikes} possible strikes` : "") +
        (dropped ? ` · ${dropped} low-conf hidden` : "")
      : "no thermal anomalies in the box")
  }

  async _renderWebcams(layer, payloads) {
    const Cesium = window.Cesium
    const cams = payloads[0]?.webcams || []

    cams.forEach((cam) => {
      const loc = cam.location || {}
      if (loc.latitude == null) return
      const entity = this._add(layer.key, {
        position: Cesium.Cartesian3.fromDegrees(loc.longitude, loc.latitude),
        point: {
          pixelSize: 5,
          color: Cesium.Color.fromCssColorString(LAYER_COLORS.webcams).withAlpha(cam.live ? 1 : 0.6),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.6),
          outlineWidth: 1,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
      // Clicking the dot opens the same watchable target the dossier row does.
      entity.openUrl = webcamLink(cam)
    })

    const live = cams.filter((c) => c.live).length
    const ranked = cams
      .map((cam) => ({ cam, km: this._distanceKm(cam.location?.latitude, cam.location?.longitude) }))
      .sort((a, b) => (b.cam.live - a.cam.live) || ((a.km ?? Infinity) - (b.km ?? Infinity)))
    this._notes.set(layer.key, cams.length ? `${cams.length} cams · ${live} live` : "none nearby")
    if (cams.length) this._sections.set(layer.key, webcamSection(ranked))
  }

  async _renderConflictEvents(layer, payloads) {
    const Cesium = window.Cesium
    const events = (payloads[0] || []).slice(0, MAX_CONFLICT_EVENTS)

    // UCDP is a historical record. Age is rendered — a year-old clash draws at
    // a fraction of last week's — and the note names the span and the latest
    // date, so history can inform without impersonating the present.
    const now = Date.now()
    const yearMs = 365 * 24 * 3600 * 1000

    events.forEach((event) => {
      if (event.lat == null) return
      const age = event.date_start ? Math.min((now - Date.parse(event.date_start)) / yearMs, 1) : 1
      const alpha = this._proximityAlpha(0.85 - 0.6 * age, event.lat, event.lng)
      this._add(layer.key, {
        position: Cesium.Cartesian3.fromDegrees(event.lng, event.lat),
        point: {
          pixelSize: 3.5,
          color: Cesium.Color.fromCssColorString(LAYER_COLORS.conflict).withAlpha(Math.max(alpha, 0.12)),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
    })

    const deaths = events.reduce((sum, e) => sum + (Number(e.deaths) || 0), 0)
    const latest = events.map((e) => e.date_start).filter(Boolean).sort().pop()
    this._notes.set(layer.key, events.length
      ? `${events.length} events in 2y` + (deaths ? ` · ${deaths.toLocaleString()} deaths` : "") +
        (latest ? ` · latest ${latest.slice(0, 10)}` : "")
      : "none recorded in 2y")
  }

  async _renderEarthquakes(layer, payloads) {
    const Cesium = window.Cesium
    // Below M2.5 is instrument chatter at situation scale.
    const quakes = (payloads[0] || []).filter((q) => this._inBbox(q.lat, q.lng) && (Number(q.mag) || 0) >= 2.5)
    const labelled = quakes.length <= 20

    quakes.forEach((quake) => {
      const mag = Number(quake.mag) || 0
      const entity = this._add(layer.key, {
        position: Cesium.Cartesian3.fromDegrees(quake.lng, quake.lat),
        point: {
          pixelSize: 4 + mag * 1.5,
          color: Cesium.Color.fromCssColorString(LAYER_COLORS.quakes).withAlpha(0.15),
          outlineColor: Cesium.Color.fromCssColorString(LAYER_COLORS.quakes).withAlpha(0.9),
          outlineWidth: 1.5,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: labelled ? layerLabel(`M${mag.toFixed(1)}`, LAYER_COLORS.quakes) : undefined,
      })
      if (quake.url) entity.openUrl = quake.url
    })

    this._notes.set(layer.key, quakes.length ? `${quakes.length} of M2.5+ in 7 days` : "none of M2.5+ in 7 days")
    if (quakes.length) this._sections.set(layer.key, quakeSection(quakes))
  }

  async _renderWeatherAlerts(layer, payloads) {
    const Cesium = window.Cesium
    const alerts = (payloads[0]?.alerts || []).filter((a) => a.lat != null)
    const labelled = alerts.length <= 15

    alerts.forEach((alert) => {
      this._add(layer.key, {
        position: Cesium.Cartesian3.fromDegrees(alert.lng, alert.lat),
        billboard: {
          image: triangleGlyph(LAYER_COLORS.weather, 0.9),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: labelled && alert.event ? layerLabel(alert.event, LAYER_COLORS.weather) : undefined,
      })
    })

    this._notes.set(layer.key, alerts.length ? `${alerts.length} active alerts` : "no active alerts")
  }

  async _renderNotams(layer, payloads) {
    const Cesium = window.Cesium
    const zones = (payloads[0] || []).slice(0, MAX_NOTAMS)

    zones.forEach((zone) => {
      if (zone.lat == null || !zone.radius_m) return
      this._add(layer.key, {
        position: Cesium.Cartesian3.fromDegrees(zone.lng, zone.lat),
        ellipse: {
          semiMajorAxis: zone.radius_m,
          semiMinorAxis: zone.radius_m,
          // Outline only — a filled disc per restriction turns three NOTAMs
          // into a red wash over the whole box.
          material: Cesium.Color.TRANSPARENT,
          outline: true,
          outlineColor: Cesium.Color.fromCssColorString(LAYER_COLORS.notams).withAlpha(0.45),
          height: 0,
        },
      })
    })

    this._notes.set(layer.key, zones.length ? `${zones.length} restrictions` : "none in the box")
  }

  async _renderMilitaryBases(layer, payloads) {
    const Cesium = window.Cesium
    // Rows arrive as arrays: [id, lat, lng, name, base_type, country, operator].
    // The box is re-checked here: a server that ignores or mishandles the bbox
    // params must not paint the whole world's bases onto one situation.
    const bases = (payloads[0] || [])
      .filter((base) => this._inBbox(base[1], base[2]))
      .slice(0, MAX_BASES)

    bases.forEach((base) => {
      this._add(layer.key, {
        position: Cesium.Cartesian3.fromDegrees(base[2], base[1]),
        billboard: {
          image: diamondGlyph(LAYER_COLORS.bases),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
      })
    })

    this._notes.set(layer.key, bases.length ? `${bases.length} installations` : "none in the box")
  }

  async _renderInfrastructure(layer, payloads) {
    const Cesium = window.Cesium
    const [pipes, cables] = payloads
    let drawn = 0

    // Pipelines store [lat, lng]; cables store [lng, lat]. Same repo, opposite
    // orders — mirror the main globe's renderers exactly.
    ;(pipes?.pipelines || []).forEach((pipe) => {
      const coords = pipe.coordinates || []
      if (!coords.some((pt) => this._inBbox(pt[0], pt[1], 3))) return
      drawn++
      this._add(layer.key, {
        polyline: {
          positions: coords.map((pt) => Cesium.Cartesian3.fromDegrees(pt[1], pt[0])),
          width: 1.5,
          material: Cesium.Color.fromCssColorString(pipe.color || LAYER_COLORS.pipelines).withAlpha(0.4),
          arcType: Cesium.ArcType.GEODESIC,
        },
      })
    })

    ;(cables?.cables || []).forEach((cable) => {
      const segments = cable.coordinates || []
      // Cable coordinates are segment lists of [lng, lat] pairs.
      segments.forEach((segment) => {
        const points = Array.isArray(segment[0]) ? segment : [segment]
        if (!points.some((pt) => this._inBbox(pt[1], pt[0], 3))) return
        drawn++
        this._add(layer.key, {
          polyline: {
            positions: points.map((pt) => Cesium.Cartesian3.fromDegrees(pt[0], pt[1])),
            width: 1,
            material: Cesium.Color.fromCssColorString(cable.color || LAYER_COLORS.cables).withAlpha(0.35),
            arcType: Cesium.ArcType.GEODESIC,
          },
        })
      })
    })

    this._notes.set(layer.key, drawn ? `${drawn} lines through the area` : "nothing runs through the box")
  }

  // Passes are computed, not drawn: the useful fact is "a capable imager sees
  // this anchor at 14:32", which is a list, not a shape on the ground.
  async _renderSatellites(layer, payloads) {
    const sats = (payloads[0] || []).filter((s) => s.tle_line1 && s.tle_line2).slice(0, PASS_MAX_SATELLITES)
    if (!sats.length) {
      this._notes.set(layer.key, "no TLEs available")
      return
    }

    await loadSatelliteJs()
    if (!window.satellite) {
      this._notes.set(layer.key, "propagator failed to load")
      return
    }

    const anchor = this._plan.anchor
    const result = await computePasses(sats, anchor, () => this._epoch)
    if (result == null) return // superseded mid-computation

    const { passes, watchers } = result
    const note = passes.length
      ? `${passes.length} passes in 24h`
      : `no passes above ${PASS_MIN_ELEVATION_DEG}° in 24h`
    this._notes.set(layer.key, watchers ? `${note} · ${watchers} in continuous view` : note)
    if (passes.length) this._sections.set(layer.key, passSection(passes))
  }

  // ── chips + sections ──────────────────────────────────────────────────

  _renderChips() {
    const container = document.getElementById(CHIP_CONTAINER_ID)
    if (!container || !this._plan) return

    // On first, suggested next, plain available after, unavailable last -- the
    // chips the user can act on lead, dead ones trail as a dim tail. The note
    // rides inline on active chips only; everything else lives in the tooltip.
    const rank = (layer) => {
      if (this._on.has(layer.key)) return 0
      if (layer.status !== "ready") return 3
      return layer.reason ? 1 : 2
    }
    const ordered = [...this._plan.layers].sort((a, b) => rank(a) - rank(b))

    // A dead chip nobody toggles is pure noise: only chips that are on,
    // suggested by the curator, or baseline show by default; the tail folds
    // behind a count. If nothing qualifies, everything shows.
    const lead = ordered.filter((layer) => this._on.has(layer.key) ||
      layer.baseline || (layer.status === "ready" && layer.reason))
    const visible = (this._chipsExpanded || !lead.length) ? ordered : lead
    const hidden = ordered.length - visible.length

    const chips = visible.map((layer) => {
      const on = this._on.has(layer.key)
      const unavailable = layer.status !== "ready"
      const note = on ? this._notes.get(layer.key) : null
      const title = [
        layer.meaning,
        layer.reason ? `Why: ${layer.reason}` : null,
        unavailable ? `Unavailable: ${layer.status}` : null,
      ].filter(Boolean).join("\n")

      const suggested = !on && !unavailable && layer.reason
      return `<button type="button"
        class="sit-chip ${on ? "is-on" : ""} ${unavailable ? "is-unavailable" : ""} ${layer.baseline ? "is-baseline" : ""} ${suggested ? "is-suggested" : ""}"
        data-layer-key="${layer.key}" title="${escapeAttr(title)}" ${unavailable ? "disabled" : ""}>
        ${escapeHtml(layer.title)}${note ? `<span class="sit-chip-note">${escapeHtml(note)}</span>` : ""}
      </button>`
    }).join("")

    const moreChip = hidden > 0
      ? `<button type="button" class="sit-chip is-more" data-chip-more>+${hidden} more</button>`
      : this._chipsExpanded && ordered.length > lead.length
        ? `<button type="button" class="sit-chip is-more" data-chip-more>fewer</button>`
        : ""

    const basis = this._plan.curated_by === "ai" ? "AI-curated" : "rule-curated"
    container.innerHTML = `
      <div class="sit-section-title">Live layers <span class="sit-chip-basis">${basis}</span></div>
      <div class="sit-chip-row">${chips}${moreChip}</div>`

    container.querySelectorAll(".sit-chip[data-layer-key]").forEach((button) => {
      button.addEventListener("click", (event) => {
        event.stopPropagation()
        this.toggle(button.dataset.layerKey)
      })
    })
    container.querySelector("[data-chip-more]")?.addEventListener("click", (event) => {
      event.stopPropagation()
      this._chipsExpanded = !this._chipsExpanded
      this._renderChips()
    })
  }

  _renderChipsError() {
    const container = document.getElementById(CHIP_CONTAINER_ID)
    if (container) container.innerHTML = `<div class="sit-note">Layer plan unavailable.</div>`
  }

  _renderSections() {
    const container = document.getElementById(SECTIONS_CONTAINER_ID)
    if (!container) return
    container.innerHTML = [...this._sections.values()].join("")
  }

  _containingFeature(collection, anchor) {
    const features = collection?.features || []
    return features.find((feature) => geometryContains(feature.geometry, anchor.lng, anchor.lat))
  }

  _outerRings(geometry) {
    if (!geometry) return []
    if (geometry.type === "Polygon") return [geometry.coordinates[0]]
    if (geometry.type === "MultiPolygon") return geometry.coordinates.map((poly) => poly[0])
    return []
  }
}

// ── geometry helpers ────────────────────────────────────────────────────

function featureName(feature) {
  return feature?.properties?.name || feature?.properties?.NAME || feature?.properties?.shapeName || ""
}

// Every name the polygon answers to: local name, English name, GeoNames name,
// alternates. Natural Earth's `name` is often the local form ("Bayern"), and
// the curator speaks English ("Bavaria") — matching on one property misses the
// other.
function featureNames(feature) {
  const props = feature?.properties || {}
  return [props.name, props.NAME, props.shapeName, props.name_en, props.gn_name, props.name_alt, props.woe_name]
    .filter(Boolean)
    .flatMap((value) => String(value).split("|"))
}

// The curator says "Hormozgan"; the polygon says "Hormozgān Province". Strip
// diacritics and the administrative furniture words before comparing.
function normalizeName(value) {
  return String(value || "")
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\b(province|state|governorate|region|district|prefecture|oblast|county)\b/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
}

function geometryContains(geometry, lng, lat) {
  if (!geometry) return false
  if (geometry.type === "Polygon") return polygonContains(geometry.coordinates, lng, lat)
  if (geometry.type === "MultiPolygon") {
    return geometry.coordinates.some((poly) => polygonContains(poly, lng, lat))
  }
  return false
}

// Ray cast against the outer ring, then punch out holes.
function polygonContains(rings, lng, lat) {
  if (!rings?.length) return false
  if (!ringContains(rings[0], lng, lat)) return false
  return !rings.slice(1).some((hole) => ringContains(hole, lng, lat))
}

function ringContains(ring, lng, lat) {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i]
    const [xj, yj] = ring[j]
    if ((yi > lat) !== (yj > lat) && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) {
      inside = !inside
    }
  }
  return inside
}

// ── satellite passes ────────────────────────────────────────────────────

let satelliteJsPromise = null
function loadSatelliteJs() {
  if (window.satellite) return Promise.resolve()
  if (satelliteJsPromise) return satelliteJsPromise

  satelliteJsPromise = new Promise((resolve) => {
    const script = document.createElement("script")
    script.src = SATELLITE_JS_URL
    script.onload = resolve
    script.onerror = () => resolve() // caller checks window.satellite
    document.head.appendChild(script)
  })
  return satelliteJsPromise
}

// Stepped SGP4 over the lookahead window, chunked so a hundred propagations a
// frame never block the UI. epochCheck aborts the walk if the selection moved
// on mid-computation.
async function computePasses(sats, anchor, epochCheck) {
  const sat = window.satellite
  const startEpoch = epochCheck()
  const observer = {
    longitude: sat.degreesToRadians(anchor.lng),
    latitude: sat.degreesToRadians(anchor.lat),
    height: 0,
  }

  const now = Date.now()
  const steps = (PASS_LOOKAHEAD_HOURS * 3600) / PASS_STEP_SECONDS
  const passes = []
  const watchers = new Set()

  const flush = (record, pass) => {
    const minutes = (pass.lastSeen - pass.start) / 60000
    if (minutes > PASS_MAX_MINUTES) watchers.add(record.name)
    else passes.push({ name: record.name, category: record.category, purpose: record.purpose,
                       start: pass.start, maxElevation: pass.maxElevation })
  }

  for (let index = 0; index < sats.length; index++) {
    if (index % 10 === 9) {
      await new Promise((resolve) => setTimeout(resolve, 0))
      if (epochCheck() !== startEpoch) return null
    }

    const record = sats[index]
    let satrec
    try {
      satrec = sat.twoline2satrec(record.tle_line1, record.tle_line2)
    } catch { continue }

    let current = null
    for (let step = 0; step <= steps; step++) {
      const time = new Date(now + step * PASS_STEP_SECONDS * 1000)
      let elevation = -90
      try {
        const positionEci = sat.propagate(satrec, time)?.position
        if (positionEci) {
          const gmst = sat.gstime(time)
          const positionEcf = sat.eciToEcf(positionEci, gmst)
          const look = sat.ecfToLookAngles(observer, positionEcf)
          elevation = sat.radiansToDegrees(look.elevation)
        }
      } catch { break }

      if (elevation >= PASS_MIN_ELEVATION_DEG) {
        if (!current) current = { start: time, maxElevation: elevation, lastSeen: time }
        else { current.maxElevation = Math.max(current.maxElevation, elevation); current.lastSeen = time }
      } else if (current) {
        flush(record, current)
        current = null
        if (passes.length > PASS_LIST_LIMIT * 4) break
      }
    }
    if (current) flush(record, current)
  }

  return {
    passes: passes.sort((a, b) => a.start - b.start).slice(0, PASS_LIST_LIMIT),
    watchers: watchers.size,
  }
}

// ── section templates ───────────────────────────────────────────────────

// Live streams first, then nearest first — a live phone stream 4 km out beats
// a periodic resort cam at the box edge.
// A watchable page beats a frozen JPEG: the player when there is one, the
// Windy webcam page for Windy cams, and only then the raw still.
function webcamLink(cam) {
  const windyPage = cam.source === "windy" && cam.webcamId
    ? `https://www.windy.com/webcams/${encodeURIComponent(cam.webcamId)}` : null
  return cam.player?.live?.embed || windyPage || cam.images?.current?.preview
}

function webcamSection(ranked) {
  const rows = ranked.slice(0, 8).map(({ cam, km }) => {
    const preview = cam.images?.current?.preview
    const link = webcamLink(cam)
    const badge = cam.live ? `<span class="sit-cam-live">LIVE</span>` : ""
    const place = [cam.location?.city, cam.location?.country].filter(Boolean).join(", ")
    const distance = km != null ? ` · ${Math.round(km)} km` : ""

    return `<a class="sit-cam" href="${escapeAttr(link || "#")}" target="_blank" rel="noopener">
      ${preview ? `<img class="sit-cam-img" src="${escapeAttr(preview)}" alt="" loading="lazy">` : ""}
      <span class="sit-cam-meta">${badge}${escapeHtml(cam.title || "untitled")}<em>${escapeHtml(place)}${distance}</em></span>
    </a>`
  }).join("")

  return `<div class="sit-section-title">Cameras near the anchor</div>
    <div class="sit-cams">${rows}</div>`
}

function quakeSection(quakes) {
  const strongest = [...quakes].sort((a, b) => (Number(b.mag) || 0) - (Number(a.mag) || 0)).slice(0, 6)
  const rows = strongest.map((quake) => {
    const mag = Number(quake.mag) || 0
    const hours = quake.time ? Math.round((Date.now() - quake.time) / 3600000) : null
    const when = hours == null ? "" : hours < 1 ? "just now" : hours < 24 ? `${hours}h ago` : `${Math.round(hours / 24)}d ago`
    const depth = quake.depth != null ? `${Math.round(quake.depth)} km deep` : null
    const detail = [depth, when].filter(Boolean).join(" · ")
    const name = escapeHtml(quake.title || `M${mag.toFixed(1)}`)
    const label = quake.url
      ? `<a href="${escapeAttr(quake.url)}" target="_blank" rel="noopener">${name}</a>`
      : name

    return `<div class="sit-ring-row">
      <span class="sit-ring-name">${label}</span>
      <span class="sit-ring-detail">${escapeHtml(detail)}</span>
    </div>`
  }).join("")

  return `<div class="sit-section-title">Strongest recent quakes</div>
    <div class="sit-ring">${rows}</div>`
}

function passSection(passes) {
  const rows = passes.map((pass) => {
    const minutes = Math.round((pass.start - Date.now()) / 60000)
    const when = minutes <= 0 ? "overhead now" : minutes < 60 ? `in ${minutes} min` : `in ${Math.round(minutes / 60)}h ${minutes % 60}m`
    return `<div class="sit-ring-row">
      <span class="sit-ring-name">${escapeHtml(pass.name)}</span>
      <span class="sit-ring-detail">${when} · max ${Math.round(pass.maxElevation)}°</span>
    </div>`
  }).join("")

  return `<div class="sit-section-title">Imaging passes over the anchor</div>
    <div class="sit-ring">${rows}</div>`
}

// ── glyphs ──────────────────────────────────────────────────────────────

const glyphCache = new Map()

function triangleGlyph(color, alpha) {
  const key = `tri:${color}:${alpha}`
  if (glyphCache.has(key)) return glyphCache.get(key)

  const size = 14
  const canvas = document.createElement("canvas")
  canvas.width = canvas.height = size
  const ctx = canvas.getContext("2d")
  ctx.globalAlpha = alpha
  ctx.beginPath()
  ctx.moveTo(size / 2, 1.5)
  ctx.lineTo(size - 2.5, size - 2)
  ctx.lineTo(2.5, size - 2)
  ctx.closePath()
  ctx.fillStyle = color
  ctx.fill()
  ctx.lineWidth = 1
  ctx.strokeStyle = "rgba(0,0,0,0.7)"
  ctx.stroke()

  glyphCache.set(key, canvas)
  return canvas
}

function diamondGlyph(color) {
  const key = `dia:${color}`
  if (glyphCache.has(key)) return glyphCache.get(key)

  const size = 12
  const canvas = document.createElement("canvas")
  canvas.width = canvas.height = size
  const ctx = canvas.getContext("2d")
  ctx.beginPath()
  ctx.moveTo(size / 2, 1)
  ctx.lineTo(size - 1, size / 2)
  ctx.lineTo(size / 2, size - 1)
  ctx.lineTo(1, size / 2)
  ctx.closePath()
  ctx.fillStyle = color
  ctx.globalAlpha = 0.9
  ctx.fill()
  ctx.globalAlpha = 1
  ctx.lineWidth = 1
  ctx.strokeStyle = "rgba(0,0,0,0.7)"
  ctx.stroke()

  glyphCache.set(key, canvas)
  return canvas
}

function layerLabel(text, color) {
  const Cesium = window.Cesium
  return {
    text: text,
    font: `400 9px "JetBrains Mono", monospace`,
    fillColor: Cesium.Color.fromCssColorString(color),
    outlineColor: Cesium.Color.BLACK,
    outlineWidth: 2,
    style: Cesium.LabelStyle.FILL_AND_OUTLINE,
    pixelOffset: new Cesium.Cartesian2(0, -10),
    disableDepthTestDistance: Number.POSITIVE_INFINITY,
  }
}

// FIRMS confidence arrives as "high"/"nominal"/"low", "h"/"n"/"l", or 0-100.
function fireConfidence(value) {
  const text = String(value ?? "").toLowerCase()
  if (text.startsWith("h")) return 90
  if (text.startsWith("n")) return 50
  if (text.startsWith("l")) return 10
  const numeric = Number(value)
  return Number.isFinite(numeric) ? numeric : 50
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const rad = Math.PI / 180
  const dLat = (lat2 - lat1) * rad
  const dLng = (lng2 - lng1) * rad
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLng / 2) ** 2
  return 6371 * 2 * Math.asin(Math.sqrt(Math.min(h, 1)))
}

// ── html helpers ────────────────────────────────────────────────────────

function escapeHtml(value) {
  const div = document.createElement("div")
  div.textContent = value == null ? "" : String(value)
  return div.innerHTML
}

function escapeAttr(value) {
  return escapeHtml(value).replaceAll('"', "&quot;")
}
