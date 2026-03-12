// ── Deep Links ──────────────────────────────────────────
// Encode/decode globe state in URL hash for shareable views.
//
// Format: #lat,lng,height,heading,pitch|layer1,layer2,...|sat:cat1,cat2|mil:0|countries:US,DE
// All sections after camera are optional.

const LAYER_KEYS = [
  "flights", "trails", "ships", "borders", "cities", "airports",
  "earthquakes", "naturalEvents", "cameras", "gpsJamming", "news",
  "cables", "outages", "powerPlants", "conflicts", "traffic", "notams", "terrain",
]

// Short aliases to keep URLs compact
const LAYER_SHORT = {
  flights: "fl", trails: "tr", ships: "sh", borders: "bd", cities: "ct",
  airports: "ap", earthquakes: "eq", naturalEvents: "ev", cameras: "cm",
  gpsJamming: "gj", news: "nw", cables: "cb", outages: "ou",
  powerPlants: "pp", conflicts: "cf", traffic: "tf", notams: "nt", terrain: "tn",
}

const SHORT_TO_LAYER = Object.fromEntries(
  Object.entries(LAYER_SHORT).map(([k, v]) => [v, k])
)

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
    if (k === "naturalEvents") return controller.naturalEventsVisible
    if (k === "terrain") return controller.terrainEnabled
    return controller[k + "Visible"]
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

  // Selected countries
  if (controller.selectedCountries?.size > 0) {
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
    }
  }

  return result
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

  // Apply layers — toggle on only the ones specified
  if (state.layers) {
    const toggleMap = {
      flights: "toggleFlights", trails: "toggleTrails", ships: "toggleShips",
      borders: "toggleBorders", cities: "toggleCities", airports: "toggleAirports",
      earthquakes: "toggleEarthquakes", naturalEvents: "toggleNaturalEvents",
      cameras: "toggleCameras", gpsJamming: "toggleGpsJamming", news: "toggleNews",
      cables: "toggleCables", outages: "toggleOutages", powerPlants: "togglePowerPlants",
      conflicts: "toggleConflicts", traffic: "toggleTraffic", notams: "toggleNotams",
      terrain: "toggleTerrain",
    }
    const targetMap = {
      flights: "flightsToggle", trails: "trailsToggle", ships: "shipsToggle",
      borders: "bordersToggle", cities: "citiesToggle", airports: "airportsToggle",
      earthquakes: "earthquakesToggle", naturalEvents: "naturalEventsToggle",
      cameras: "camerasToggle", gpsJamming: "gpsJammingToggle", news: "newsToggle",
      cables: "cablesToggle", outages: "outagesToggle", powerPlants: "powerPlantsToggle",
      conflicts: "conflictsToggle", traffic: "trafficToggle", notams: "notamsToggle",
      terrain: "terrainToggle",
    }

    for (const layer of state.layers) {
      const method = toggleMap[layer]
      const target = targetMap[layer]
      if (!method || !controller[method]) continue

      // Check if already visible
      const visKey = layer === "naturalEvents" ? "naturalEventsVisible"
        : layer === "terrain" ? "terrainEnabled"
        : layer + "Visible"
      if (controller[visKey]) continue // already on

      // Set checkbox
      const targetName = target + "Target"
      const hasTarget = "has" + target.charAt(0).toUpperCase() + target.slice(1) + "Target"
      if (controller[hasTarget]) {
        controller[targetName].checked = true
      }
      controller[method]()
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
        controller.fetchSatCategory(cat)
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
      controller.toggleBorders()
    }
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
