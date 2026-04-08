export const PLAYBACK_LAYER_GROUPS = {
  static: [
    "cities",
    "airports",
    "airbases",
    "militaryBases",
    "ports",
    "pipelines",
    "cables",
    "powerPlants",
    "commoditySites",
    "borders",
    "terrain",
    "chokepoints",
  ],
  movement: [
    "flights",
    "militaryFlights",
    "ships",
    "navalVessels",
  ],
  ephemeral: [
    "earthquakes",
    "naturalEvents",
    "news",
    "gpsJamming",
    "outages",
    "weather",
    "notams",
    "fireHotspots",
    "heatSignatures",
    "verifiedStrikes",
    "conflicts",
  ],
  snapshot: [
    "situations",
    "financial",
    "traffic",
    "satellites",
  ],
  liveOnly: [
    "insights",
  ],
}

export function movementPlaybackLayersVisible(controller) {
  return !!(
    controller.flightsVisible ||
    controller._milFlightsActive ||
    controller.shipsVisible ||
    controller.navalVesselsVisible
  )
}

export function snapshotPlaybackLayersVisible(controller) {
  return !!(
    controller.situationsVisible ||
    controller.financialVisible ||
    controller.trafficVisible ||
    Object.values(controller.satCategoryVisible || {}).some(Boolean)
  )
}

export function ephemeralPlaybackLayersVisible(controller) {
  return playbackEphemeralRequest(controller).hasAny
}

export function eventPlaybackLayersVisible(controller) {
  return ephemeralPlaybackLayersVisible(controller) || snapshotPlaybackLayersVisible(controller)
}

export function playbackEphemeralRequest(controller) {
  const wantsFireEvents = !!(controller.fireHotspotsVisible || controller.heatSignaturesVisible || controller.strikesVisible)
  const wantsVerifiedStrikes = !!(controller.verifiedStrikesVisible || controller.strikesVisible)
  const generalTypes = []

  if (controller.earthquakesVisible) generalTypes.push("earthquake")
  if (controller.naturalEventsVisible) generalTypes.push("natural_event")
  if (controller.newsVisible) generalTypes.push("news")
  if (controller.gpsJammingVisible) generalTypes.push("gps_jamming")
  if (controller.outagesVisible) generalTypes.push("internet_outage")
  if (controller.weatherVisible) generalTypes.push("weather_alert")
  if (controller.notamsVisible) generalTypes.push("notam")

  const strikeTypes = []
  if (wantsFireEvents) strikeTypes.push("fire")
  if (wantsVerifiedStrikes) strikeTypes.push("geoconfirmed")

  return {
    generalTypes,
    strikeTypes,
    wantsConflictEvents: !!controller.conflictsVisible,
    wantsFireHotspots: !!controller.fireHotspotsVisible,
    wantsHeatSignatures: !!(controller.heatSignaturesVisible || controller.strikesVisible),
    wantsVerifiedStrikes,
    hasAny: generalTypes.length > 0 || strikeTypes.length > 0 || !!controller.conflictsVisible,
  }
}
