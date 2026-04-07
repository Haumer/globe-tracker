export const LAYER_REGISTRY = [
  { key: "flights", toggleTarget: "flightsToggle", method: "toggleFlights", visibleProp: "flightsVisible", qlTarget: "qlFlights", section: "tracking", pill: { label: "FLT", color: "#4fc3f7" } },
  { key: "ships", toggleTarget: "shipsToggle", method: "toggleShips", visibleProp: "shipsVisible", qlTarget: "qlShips", section: "tracking", pill: { label: "AIS", color: "#26c6da" } },
  { key: "trains", toggleTarget: "trainsToggle", method: "toggleTrains", visibleProp: "trainsVisible", qlTarget: "qlTrains", section: "tracking", pill: { label: "TRAIN", color: "#e53935" }, disabled: true },
  { key: "notams", toggleTarget: "notamsToggle", method: "toggleNotams", visibleProp: "notamsVisible", qlTarget: "qlNotams", section: "tracking", pill: { label: "NOTAM", color: "#ffab40" } },
  { key: "earthquakes", toggleTarget: "earthquakesToggle", method: "toggleEarthquakes", visibleProp: "earthquakesVisible", qlTarget: "qlEarthquakes", section: "events", pill: { label: "EQ", color: "#ff5252" } },
  { key: "naturalEvents", toggleTarget: "naturalEventsToggle", method: "toggleNaturalEvents", visibleProp: "naturalEventsVisible", qlTarget: "qlEvents", section: "events", pill: { label: "EVT", color: "#ff9800" } },
  { key: "fireHotspots", toggleTarget: "fireHotspotsToggle", method: "toggleFireHotspots", visibleProp: "fireHotspotsVisible", qlTarget: "qlFireHotspots", section: "events", pill: { label: "FIRE", color: "#ff6d00" } },
  { key: "weather", toggleTarget: "weatherToggle", method: "toggleWeather", visibleProp: "weatherVisible", qlTarget: "qlWeather", section: "events", pill: { label: "WX", color: "#64b5f6" } },
  { key: "conflicts", toggleTarget: "conflictsToggle", method: "toggleConflicts", visibleProp: "conflictsVisible", qlTarget: "qlConflicts", section: "events", pill: { label: "WAR", color: "#ef5350" } },
  { key: "situations", toggleTarget: "situationsToggle", method: "toggleSituations", visibleProp: "situationsVisible", qlTarget: "qlSituations", section: "events", pill: { label: "THE", color: "#ff7043" } },
  { key: "news", toggleTarget: "newsToggle", method: "toggleNews", visibleProp: "newsVisible", qlTarget: "qlNews", section: "events", pill: { label: "NEWS", color: "#7c4dff" } },
  { key: "insights", toggleTarget: "insightsToggle", method: "toggleInsights", visibleProp: "insightsVisible", qlTarget: "qlInsights", section: "events", pill: { label: "INS", color: "#26c6da" } },
  { key: "militaryFlights", toggleTarget: "militaryFlightsToggle", method: "toggleMilitaryFlightsFilter", visibleProp: "_milFlightsActive", qlTarget: "qlMilitaryFlights", section: "military", pill: { label: "MIL", color: "#ef5350" } },
  { key: "airbases", toggleTarget: "airbasesToggle", method: "toggleAirbases", visibleProp: "airbasesVisible", qlTarget: "qlAirbases", section: "military", pill: { label: "ABASE", color: "#ff7043" } },
  { key: "militaryBases", toggleTarget: "militaryBasesToggle", method: "toggleMilitaryBases", visibleProp: "militaryBasesVisible", qlTarget: "qlMilitaryBases", section: "military", pill: { label: "BASE", color: "#ff5252" } },
  { key: "navalVessels", toggleTarget: "navalVesselsToggle", method: "toggleNavalVessels", visibleProp: "navalVesselsVisible", qlTarget: "qlNavalVessels", section: "military", pill: { label: "NAVY", color: "#42a5f5" } },
  { key: "verifiedStrikes", toggleTarget: "verifiedStrikesToggle", method: "toggleVerifiedStrikes", visibleProp: "verifiedStrikesVisible", qlTarget: "qlVerifiedStrikes", section: "military", pill: { label: "VSTRK", color: "#4caf50" } },
  { key: "heatSignatures", toggleTarget: "heatSignaturesToggle", method: "toggleHeatSignatures", visibleProp: "heatSignaturesVisible", qlTarget: "qlHeatSignatures", section: "military", pill: { label: "HEAT", color: "#e040fb" } },
  { key: "cables", toggleTarget: "cablesToggle", method: "toggleCables", visibleProp: "cablesVisible", qlTarget: "qlCables", section: "infrastructure", pill: { label: "CBL", color: "#00bcd4" } },
  { key: "ports", toggleTarget: "portsToggle", method: "togglePorts", visibleProp: "portsVisible", qlTarget: "qlPorts", section: "infrastructure", pill: { label: "PORT", color: "#8bc34a" } },
  { key: "shippingLanes", toggleTarget: "shippingLanesToggle", method: "toggleShippingLanes", visibleProp: "shippingLanesVisible", qlTarget: "qlShippingLanes", section: "infrastructure", pill: { label: "LANE", color: "#ff8a00" }, disabled: true },
  { key: "pipelines", toggleTarget: "pipelinesToggle", method: "togglePipelines", visibleProp: "pipelinesVisible", qlTarget: "qlPipelines", section: "infrastructure", pill: { label: "PIPE", color: "#ff6d00" } },
  { key: "railways", toggleTarget: "railwaysToggle", method: "toggleRailways", visibleProp: "railwaysVisible", qlTarget: "qlRailways", section: "infrastructure", pill: { label: "RAIL", color: "#90a4ae" }, disabled: true },
  { key: "powerPlants", toggleTarget: "powerPlantsToggle", method: "togglePowerPlants", visibleProp: "powerPlantsVisible", qlTarget: "qlPowerPlants", section: "infrastructure", pill: { label: "PWR", color: "#ffc107" } },
  { key: "cameras", toggleTarget: "camerasToggle", method: "toggleCameras", visibleProp: "camerasVisible", qlTarget: "qlCameras", section: "infrastructure", pill: { label: "CAM", color: "#29b6f6" } },
  { key: "financial", toggleTarget: "financialToggle", method: "toggleFinancial", visibleProp: "financialVisible", qlTarget: "qlFinancial", section: "infrastructure", pill: { label: "MKT", color: "#66bb6a" } },
  { key: "chokepoints", toggleTarget: "chokepointsToggle", method: "toggleChokepoints", visibleProp: "chokepointsVisible", qlTarget: "qlChokepoints", section: "infrastructure", pill: { label: "CHOKE", color: "#4fc3f7" } },
  { key: "traffic", toggleTarget: "trafficToggle", method: "toggleTraffic", visibleProp: "trafficVisible", qlTarget: "qlTraffic", section: "cyber", pill: { label: "NET", color: "#69f0ae" } },
  { key: "outages", toggleTarget: "outagesToggle", method: "toggleOutages", visibleProp: "outagesVisible", qlTarget: "qlOutages", section: "cyber", pill: { label: "OUT", color: "#e040fb" } },
  { key: "gpsJamming", toggleTarget: "gpsJammingToggle", method: "toggleGpsJamming", visibleProp: "gpsJammingVisible", qlTarget: "qlGpsJamming", section: "cyber", pill: { label: "GPS", color: "#ff1744" } },
  { key: "cities", toggleTarget: "citiesToggle", method: "toggleCities", visibleProp: "citiesVisible", qlTarget: "qlCities", section: "map", pill: { label: "CITY", color: "#ffd54f" } },
  { key: "airports", toggleTarget: "airportsToggle", method: "toggleAirports", visibleProp: "airportsVisible", qlTarget: "qlAirports", section: "map", pill: { label: "APT", color: "#81d4fa" } },
  { key: "borders", toggleTarget: "bordersToggle", method: "toggleBorders", visibleProp: "bordersVisible", qlTarget: "qlBorders", section: "map", pill: { label: "BDR", color: "#ffd54f" } },
  { key: "terrain", toggleTarget: "terrainToggle", method: "toggleTerrain", visibleProp: "terrainEnabled", qlTarget: "qlTerrain", section: "map", pill: null },
]

export const ADVANCED_LIBRARY_KEYS = [
  "flights",
  "ships",
  "satellites",
  "earthquakes",
  "naturalEvents",
  "fireHotspots",
  "weather",
  "conflicts",
  "traffic",
  "outages",
  "gpsJamming",
  "chokepoints",
  "ports",
  "shippingLanes",
  "trains",
  "notams",
  "militaryFlights",
  "airbases",
  "militaryBases",
  "navalVessels",
  "verifiedStrikes",
  "heatSignatures",
  "cables",
  "pipelines",
  "railways",
  "powerPlants",
  "cameras",
  "financial",
  "cities",
  "airports",
  "borders",
  "terrain",
]

export const QUICK_TOGGLE_MAP = Object.fromEntries(
  LAYER_REGISTRY.map(layer => [layer.key, { target: layer.toggleTarget, method: layer.method }])
)

export const LAYER_REGISTRY_BY_KEY = Object.fromEntries(
  LAYER_REGISTRY.map(layer => [layer.key, layer])
)

export function layerRegistryEntry(layerKey) {
  return LAYER_REGISTRY.find(layer => layer.key === layerKey) || null
}

export function isLayerTemporarilyDisabled(layerKey) {
  return Boolean(layerRegistryEntry(layerKey)?.disabled)
}
