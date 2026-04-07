import { LAYER_REGISTRY_BY_KEY, isLayerTemporarilyDisabled } from "globe/controller/ui/registry"

// ── Deep Links ──────────────────────────────────────────
// Encode/decode globe state in URL hash for shareable views.
//
// Format: #lat,lng,height,heading,pitch|layer1,layer2,...|sat:cat1,cat2|mil:0|countries:US,DE
// All sections after camera are optional.

const LAYER_KEYS = [
  "flights", "trails", "ships", "borders", "cities", "airports",
  "earthquakes", "naturalEvents", "cameras", "gpsJamming", "news",
  "cables", "ports", "shippingLanes", "outages", "powerPlants", "conflicts", "traffic", "notams", "terrain",
  "commoditySites",
  "fireHotspots", "weather", "financial", "insights", "situations",
  "pipelines", "railways", "trains", "chokepoints", "militaryBases", "militaryFlights", "airbases", "navalVessels",
]

// Short aliases to keep URLs compact
const LAYER_SHORT = {
  flights: "fl", trails: "tr", ships: "sh", borders: "bd", cities: "ct",
  airports: "ap", earthquakes: "eq", naturalEvents: "ev", cameras: "cm",
  gpsJamming: "gj", news: "nw", cables: "cb", ports: "po", shippingLanes: "sl", outages: "ou",
  powerPlants: "pp", conflicts: "cf", traffic: "tf", notams: "nt", terrain: "tn",
  commoditySites: "cs",
  fireHotspots: "fh", weather: "wx", financial: "fn", insights: "in", situations: "si",
  pipelines: "pl", railways: "rl", trains: "tns", chokepoints: "cp", militaryBases: "mb", militaryFlights: "mf", airbases: "ab", navalVessels: "nv",
}

const SHORT_TO_LAYER = Object.fromEntries(
  Object.entries(LAYER_SHORT).map(([k, v]) => [v, k])
)

function invokeDeepLinkStep(label, fn) {
  try {
    const result = fn()
    if (result && typeof result.then === "function") {
      result.catch(error => console.warn(`Deep link step failed: ${label}`, error))
    }
  } catch (error) {
    console.warn(`Deep link step failed: ${label}`, error)
  }
}

export function encodeState(controller) {
  const Cesium = window.Cesium
  if (!Cesium || !controller.viewer?.camera) return null

  let carto
  try { carto = controller.viewer.camera.positionCartographic } catch { return null }

  const parts = []

  // Camera: lat,lng,height,heading,pitch (rounded for compact URLs)
  const lat = Cesium.Math.toDegrees(carto.latitude).toFixed(4)
  const lng = Cesium.Math.toDegrees(carto.longitude).toFixed(4)
  const h = Math.round(carto.height)
  const hd = controller.viewer.camera.heading.toFixed(3)
  const pt = controller.viewer.camera.pitch.toFixed(3)
  parts.push(`${lat},${lng},${h},${hd},${pt}`)

  // Active layers
  const activeLayers = LAYER_KEYS.filter(k => {
    if (k === "terrain") return controller.terrainEnabled
    const visibleProp = LAYER_REGISTRY_BY_KEY[k]?.visibleProp || `${k}Visible`
    return controller[visibleProp]
  })
  if (activeLayers.length > 0) {
    parts.push("l:" + activeLayers.map(k => LAYER_SHORT[k]).join(","))
  }

  // Active satellite categories
  const activeSats = Object.entries(controller.satCategoryVisible || {})
    .filter(([, v]) => v)
    .map(([k]) => k)
  if (activeSats.length > 0) {
    parts.push("s:" + activeSats.join(","))
  }

  // Military/civilian filter (only encode if non-default)
  if (!controller.showCivilian || !controller.showMilitary) {
    const mil = (controller.showCivilian ? "c" : "") + (controller.showMilitary ? "m" : "")
    parts.push("f:" + mil)
  }

  if (controller._activeRegion) {
    parts.push("r:" + controller._activeRegion.key)
  } else if (controller._activeCircle?.center && controller._activeCircle?.radius) {
    const center = controller._activeCircle.center
    parts.push(`ci:${center.lat.toFixed(4)},${center.lng.toFixed(4)},${Math.round(controller._activeCircle.radius)}`)
  } else if (controller.selectedCountries?.size > 0) {
    parts.push("co:" + [...controller.selectedCountries].join("|"))
  }

  return "#" + parts.join(";")
}

export function decodeHash(hash) {
  if (!hash || hash.length < 2) return null

  const raw = hash.startsWith("#") ? hash.slice(1) : hash
  const sections = raw.split(";")
  if (sections.length === 0) return null

  const result = {}

  // First section is always camera
  const cam = sections[0].split(",")
  if (cam.length >= 3) {
    result.camera = {
      lat: parseFloat(cam[0]),
      lng: parseFloat(cam[1]),
      height: parseFloat(cam[2]),
      heading: cam.length > 3 ? parseFloat(cam[3]) : 0,
      pitch: cam.length > 4 ? parseFloat(cam[4]) : -Math.PI / 2,
    }
    // Validate
    if (isNaN(result.camera.lat) || isNaN(result.camera.lng) || isNaN(result.camera.height)) {
      return null
    }
  } else {
    return null
  }

  // Remaining sections are keyed
  for (let i = 1; i < sections.length; i++) {
    const s = sections[i]
    const colonIdx = s.indexOf(":")
    if (colonIdx < 0) continue
    const key = s.slice(0, colonIdx)
    const val = s.slice(colonIdx + 1)

    if (key === "l") {
      result.layers = val.split(",").map(short => SHORT_TO_LAYER[short]).filter(Boolean)
    } else if (key === "s") {
      result.satCategories = val.split(",")
    } else if (key === "f") {
      result.showCivilian = val.includes("c")
      result.showMilitary = val.includes("m")
    } else if (key === "co") {
      result.countries = val.split("|")
    } else if (key === "ci") {
      const circle = val.split(",")
      if (circle.length === 3) {
        result.circle = {
          lat: parseFloat(circle[0]),
          lng: parseFloat(circle[1]),
          radius: parseFloat(circle[2]),
        }
      }
    } else if (key === "r") {
      result.region = val
    }
  }

  return result
}

export function decodeFocusParams(search) {
  const raw = search || ""
  if (!raw) return null

  const params = new URLSearchParams(raw.startsWith("?") ? raw.slice(1) : raw)
  const kind = params.get("focus_kind")
  const id = params.get("focus_id")
  if (!kind || !id) return null

  return {
    kind,
    id,
    title: params.get("focus_title"),
  }
}

export function applyDeepLink(controller, state) {
  const Cesium = window.Cesium
  if (!Cesium || !controller.viewer) return

  // Apply camera
  if (state.camera) {
    controller.viewer.camera.setView({
      destination: Cesium.Cartesian3.fromDegrees(
        state.camera.lng, state.camera.lat, state.camera.height
      ),
      orientation: {
        heading: state.camera.heading || 0,
        pitch: state.camera.pitch || -Cesium.Math.PI_OVER_TWO,
        roll: 0,
      },
    })
  }

  if (controller._ensureAdvancedLayersEnabled) {
    const requestedLayers = [...(state.layers || [])]
    if (state.satCategories?.length) requestedLayers.push("satellites")
    controller._ensureAdvancedLayersEnabled(requestedLayers)
  }

  // Apply layers — toggle on only the ones specified
  if (state.layers) {
    const toggleMap = {
      flights: "toggleFlights", trails: "toggleTrails", ships: "toggleShips",
      borders: "toggleBorders", cities: "toggleCities", airports: "toggleAirports",
      earthquakes: "toggleEarthquakes", naturalEvents: "toggleNaturalEvents",
      cameras: "toggleCameras", gpsJamming: "toggleGpsJamming", news: "toggleNews",
      cables: "toggleCables", ports: "togglePorts", shippingLanes: "toggleShippingLanes", outages: "toggleOutages", powerPlants: "togglePowerPlants",
      commoditySites: "toggleCommoditySites",
      conflicts: "toggleConflicts", traffic: "toggleTraffic", notams: "toggleNotams",
      terrain: "toggleTerrain", fireHotspots: "toggleFireHotspots", weather: "toggleWeather",
      financial: "toggleFinancial", insights: "toggleInsights", situations: "toggleSituations",
      pipelines: "togglePipelines", railways: "toggleRailways", trains: "toggleTrains",
      chokepoints: "toggleChokepoints", militaryBases: "toggleMilitaryBases", militaryFlights: "toggleMilitaryFlightsFilter", airbases: "toggleAirbases", navalVessels: "toggleNavalVessels",
    }
    const targetMap = {
      flights: "flightsToggle", trails: "trailsToggle", ships: "shipsToggle",
      borders: "bordersToggle", cities: "citiesToggle", airports: "airportsToggle",
      earthquakes: "earthquakesToggle", naturalEvents: "naturalEventsToggle",
      cameras: "camerasToggle", gpsJamming: "gpsJammingToggle", news: "newsToggle",
      cables: "cablesToggle", ports: "portsToggle", shippingLanes: "shippingLanesToggle", outages: "outagesToggle", powerPlants: "powerPlantsToggle",
      commoditySites: "commoditySitesToggle",
      conflicts: "conflictsToggle", traffic: "trafficToggle", notams: "notamsToggle",
      fireHotspots: "fireHotspotsToggle", weather: "weatherToggle", financial: "financialToggle",
      terrain: "terrainToggle", insights: "insightsToggle", situations: "situationsToggle",
      pipelines: "pipelinesToggle", railways: "railwaysToggle", trains: "trainsToggle",
      chokepoints: "chokepointsToggle", militaryBases: "militaryBasesToggle", militaryFlights: "militaryFlightsToggle", airbases: "airbasesToggle", navalVessels: "navalVesselsToggle",
    }

    for (const layer of state.layers) {
      if (isLayerTemporarilyDisabled(layer)) continue
      const method = toggleMap[layer]
      const target = targetMap[layer]
      if (!method || !target || !controller[method]) continue

      const visibleProp = LAYER_REGISTRY_BY_KEY[layer]?.visibleProp || (layer === "terrain" ? "terrainEnabled" : `${layer}Visible`)
      if (controller[visibleProp]) continue

      const targetName = `${target}Target`
      const hasTarget = `has${target.charAt(0).toUpperCase()}${target.slice(1)}Target`
      if (controller[hasTarget]) {
        controller[targetName].checked = true
      }
      invokeDeepLinkStep(`layer:${layer}`, () => controller[method]())
    }
  }

  // Apply satellite categories
  if (state.satCategories) {
    for (const cat of state.satCategories) {
      if (controller.satCategoryVisible[cat]) continue // already on
      controller.satCategoryVisible[cat] = true
      const chip = controller.element.querySelector(`.sb-chip[data-category="${cat}"]`)
      if (chip) chip.classList.add("active")
      if (!controller._loadedSatCategories.has(cat)) {
        invokeDeepLinkStep(`satellite-category:${cat}`, () => controller.fetchSatCategory(cat))
      }
    }
  }

  // Apply flight filter
  if (state.showCivilian !== undefined) {
    controller.showCivilian = state.showCivilian
    if (controller.hasCivilianToggleTarget) controller.civilianToggleTarget.checked = state.showCivilian
  }
  if (state.showMilitary !== undefined) {
    controller.showMilitary = state.showMilitary
    if (controller.hasMilitaryToggleTarget) controller.militaryToggleTarget.checked = state.showMilitary
  }

  // Apply country selection (defer until borders are loaded)
  if (state.countries?.length > 0) {
    controller._pendingCountryRestore = state.countries
    // If borders aren't on yet, turn them on
    if (!controller.bordersVisible) {
      if (controller.hasBordersToggleTarget) controller.bordersToggleTarget.checked = true
      invokeDeepLinkStep("layer:borders", () => controller.toggleBorders())
    }
  }

  if (state.circle && controller.applyCircleFilter) {
    invokeDeepLinkStep("circle-filter", () => controller.applyCircleFilter(
      { lat: state.circle.lat, lng: state.circle.lng },
      state.circle.radius,
      { showDetail: false, keepCountries: false }
    ))
  }

  // Apply region (overrides camera + layers set above)
  if (state.region && controller.enterRegion) {
    invokeDeepLinkStep(`region:${state.region}`, () => controller.enterRegion(state.region))
  }

  controller._syncQuickBar()
  controller._updateSatBadge()
}

export function copyShareLink(controller) {
  const hash = encodeState(controller)
  if (!hash) return

  const url = window.location.origin + window.location.pathname + hash
  navigator.clipboard.writeText(url).then(() => {
    controller._toast("Link copied to clipboard")
  }).catch(() => {
    // Fallback for insecure contexts
    const input = document.createElement("input")
    input.value = url
    document.body.appendChild(input)
    input.select()
    document.execCommand("copy")
    document.body.removeChild(input)
    controller._toast("Link copied to clipboard")
  })
}
