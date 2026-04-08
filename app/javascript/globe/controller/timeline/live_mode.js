export function pauseTimelineLive(controller) {
  controller._timelinePausedIntervals = {
    flight: !!controller.flightInterval,
    militaryFlight: !!controller._milFlightInterval,
    ship: !!controller.shipInterval,
    navalShip: !!controller._navalShipInterval,
    strikes: !!controller._strikesInterval,
    gpsJamming: !!controller._gpsJammingInterval,
    news: !!controller._newsInterval,
    events: !!controller._eventsInterval,
    outages: !!controller._outageInterval,
    financial: !!controller._financialInterval,
  }

  clearLiveIntervals(controller)
  if (controller._notamCameraCb) {
    controller.viewer.camera.moveEnd.removeEventListener(controller._notamCameraCb)
  }
  controller._pauseWeatherForTimeline?.()
  controller._stopInsightPolling?.({ clearData: false })

  if (controller._conflictPulseInterval) {
    clearInterval(controller._conflictPulseInterval)
    controller._conflictPulseInterval = null
  }
  controller._clearConflictPulseEntities?.()
  controller._lastConflictPulseBucket = null

  const liveDataSources = new Set(["flights", "mil-flights", "ships", "naval-vessels", "trails", "events", "gpsJamming", "news", "outages", "traffic", "conflicts", "fires", "weather", "notams", "financial", "insights", "satellites", "sat-orbits"])
  controller._timelineHiddenSources = []
  for (const [name, ds] of Object.entries(controller._ds)) {
    if (!liveDataSources.has(name)) continue
    if (ds && ds.show) {
      ds.show = false
      controller._timelineHiddenSources.push(name)
    }
  }
}

export function resumeTimelineLive(controller) {
  restoreHiddenSources(controller)

  if (controller.flightsVisible) {
    controller.fetchFlights()
    controller.flightInterval = setInterval(() => controller.fetchFlights(), 10000)
  }
  if (controller._milFlightsActive) {
    controller._fetchMilitaryFlights()
    controller._milFlightInterval = setInterval(() => {
      if (controller._milFlightsActive) controller._fetchMilitaryFlights()
    }, 10000)
  }
  if (controller.shipsVisible) {
    controller.fetchShips()
    controller.shipInterval = setInterval(() => controller.fetchShips(), 60000)
  }
  if (controller.navalVesselsVisible) {
    controller.fetchNavalVessels()
    controller._navalShipInterval = setInterval(() => {
      if (controller.navalVesselsVisible) controller.fetchNavalVessels()
    }, 60000)
  }
  if (controller.gpsJammingVisible) {
    controller.fetchGpsJamming()
    controller._gpsJammingInterval = setInterval(() => controller.fetchGpsJamming(), 60000)
  }
  if (controller.newsVisible) {
    controller.fetchNews()
    controller._newsInterval = setInterval(() => controller.fetchNews(), 900000)
  }
  if (controller.earthquakesVisible || controller.naturalEventsVisible) {
    if (controller.earthquakesVisible) controller.fetchEarthquakes()
    if (controller.naturalEventsVisible) controller.fetchNaturalEvents()
    controller._eventsInterval = setInterval(() => {
      if (controller.earthquakesVisible) controller.fetchEarthquakes()
      if (controller.naturalEventsVisible) controller.fetchNaturalEvents()
    }, 300000)
  }
  if (controller.outagesVisible) {
    controller.fetchOutages()
    controller._outageInterval = setInterval(() => controller.fetchOutages(), 300000)
  }
  if (controller.financialVisible) {
    controller.fetchCommodities()
    controller._financialInterval = setInterval(() => controller.fetchCommodities(), 60000)
  }
  if (strikeSignalsVisible(controller)) {
    controller.fetchStrikes()
    controller._strikesInterval = setInterval(() => {
      if (strikeSignalsVisible(controller)) controller.fetchStrikes()
    }, 300000)
  }
  if (controller.fireHotspotsVisible) {
    controller.fetchFireHotspots()
    controller._startFiresRefresh?.()
  }
  controller._resumeWeatherFromTimeline?.()
  controller._resumeNotamsFromTimeline?.()
  if (controller.insightsVisible) controller._startInsightPolling?.()
  if (Object.values(controller.satCategoryVisible || {}).some(Boolean)) {
    controller._refreshLiveSatelliteCategories?.()
  }
  if (controller.situationsVisible && controller._fetchConflictPulse) {
    controller._fetchConflictPulse()
    controller._conflictPulseInterval = setInterval(() => controller._fetchConflictPulse(), 10 * 60 * 1000)
  }
}

export function clearTimelineLiveEntities(controller) {
  const liveDataSources = new Set(["flights", "mil-flights", "ships", "naval-vessels", "trails", "events", "gpsJamming", "news", "outages", "traffic", "conflicts", "fires", "weather", "notams", "financial", "insights", "satellites", "sat-orbits"])
  for (const [name, source] of Object.entries(controller._ds)) {
    if (liveDataSources.has(name) && source) source.entities.removeAll()
  }
}

function clearLiveIntervals(controller) {
  if (controller.flightInterval) { clearInterval(controller.flightInterval); controller.flightInterval = null }
  if (controller._milFlightInterval) { clearInterval(controller._milFlightInterval); controller._milFlightInterval = null }
  if (controller.shipInterval) { clearInterval(controller.shipInterval); controller.shipInterval = null }
  if (controller._navalShipInterval) { clearInterval(controller._navalShipInterval); controller._navalShipInterval = null }
  if (controller._strikesInterval) { clearInterval(controller._strikesInterval); controller._strikesInterval = null }
  if (controller._gpsJammingInterval) { clearInterval(controller._gpsJammingInterval); controller._gpsJammingInterval = null }
  if (controller._newsInterval) { clearInterval(controller._newsInterval); controller._newsInterval = null }
  if (controller._eventsInterval) { clearInterval(controller._eventsInterval); controller._eventsInterval = null }
  if (controller._outageInterval) { clearInterval(controller._outageInterval); controller._outageInterval = null }
  if (controller._financialInterval) { clearInterval(controller._financialInterval); controller._financialInterval = null }
}

function restoreHiddenSources(controller) {
  if (!controller._timelineHiddenSources) return

  const activeDs = new Set()
  if (controller.flightsVisible) activeDs.add("flights")
  if (controller._milFlightsActive) activeDs.add("mil-flights")
  if (controller.shipsVisible) activeDs.add("ships")
  if (controller.navalVesselsVisible) activeDs.add("naval-vessels")
  if (controller.airportsVisible) activeDs.add("airports")
  if (controller.earthquakesVisible || controller.naturalEventsVisible) activeDs.add("events")
  if (controller.gpsJammingVisible) activeDs.add("gpsJamming")
  if (controller.newsVisible) activeDs.add("news")
  if (controller.outagesVisible) activeDs.add("outages")
  if (controller.conflictsVisible) activeDs.add("conflicts")
  if (controller.weatherVisible) activeDs.add("weather")
  if (controller.notamsVisible) activeDs.add("notams")
  if (controller.financialVisible) activeDs.add("financial")
  if (controller.insightsVisible) activeDs.add("insights")
  if (controller.fireHotspotsVisible) activeDs.add("fires")
  if (Object.values(controller.satCategoryVisible || {}).some(Boolean)) activeDs.add("satellites")
  if (controller.satOrbitsVisible) activeDs.add("sat-orbits")
  if (strikeSignalsVisible(controller)) activeDs.add("strikes")
  if (controller.trailsVisible) activeDs.add("trails")

  for (const name of controller._timelineHiddenSources) {
    if (controller._ds[name]) controller._ds[name].show = activeDs.has(name)
  }
  controller._timelineHiddenSources = null
}

function strikeSignalsVisible(controller) {
  return typeof controller._strikeSignalsVisible === "function"
    ? controller._strikeSignalsVisible()
    : !!(controller?.verifiedStrikesVisible || controller?.heatSignaturesVisible || controller?.strikesVisible)
}
