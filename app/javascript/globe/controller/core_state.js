const DEFAULT_SAT_CATEGORY_VISIBILITY = {
  stations: false,
  starlink: false,
  "gps-ops": false,
  glonass: false,
  galileo: false,
  weather: false,
  resource: false,
  science: false,
  military: false,
  analyst: false,
  geo: false,
  iridium: false,
  oneweb: false,
  planet: false,
  spire: false,
  gnss: false,
  tdrss: false,
  radar: false,
  sbas: false,
  cubesat: false,
  amateur: false,
  sarsat: false,
  "last-30-days": false,
  beidou: false,
  molniya: false,
  geodetic: false,
  dmc: false,
  argos: false,
  intelsat: false,
  ses: false,
  "x-comm": false,
  globalstar: false,
}

const INTERVAL_PROPS = [
  "_clockInterval",
  "_alertPollInterval",
  "flightInterval",
  "shipInterval",
  "_gpsJammingInterval",
  "_newsInterval",
  "_eventsInterval",
  "_outageInterval",
  "_trainPollTimer",
  "_strikesInterval",
  "_milFlightInterval",
  "_financialInterval",
  "_conflictPulseInterval",
  "_firesInterval",
  "_miniTimelineInterval",
  "_anomalyInterval",
  "_recordingTimerInterval",
  "_webcamRefreshInterval",
]

const TIMEOUT_PROPS = [
  "_savePrefsDebounce",
  "_searchDebounce",
  "_rwDebounce",
  "_timelineEventTimer",
  "_timelineLayerReloadTimer",
  "_polyHighlightTimer",
  "_toastTimer",
  "_portDebounce",
  "_theaterBriefPollTimer",
]

const RAF_PROPS = [
  "animationFrame",
  "_timelineRaf",
  "_pulseAnimFrame",
  "_rippleFrame",
  "_syncQBTimer",
]

const CAMERA_MOVE_END_CALLBACK_PROPS = [
  "_onCameraMoveEnd",
  "_webcamMoveHandler",
  "_flightCameraCb",
  "_shipCameraCb",
  "_rwCameraCb",
  "_portCameraCb",
  "_airbaseCameraCb",
  "_milBaseCameraCb",
  "_notamCameraCb",
  "_navalCameraCb",
  "_ppCameraCb",
]

function satCategoryVisibility() {
  return { ...DEFAULT_SAT_CATEGORY_VISIBILITY }
}

function detachCameraMoveEndCallbacks(controller, viewer) {
  const moveEnd = viewer?.camera?.moveEnd
  if (!moveEnd?.removeEventListener) return

  CAMERA_MOVE_END_CALLBACK_PROPS.forEach(prop => {
    if (!controller[prop]) return
    try {
      moveEnd.removeEventListener(controller[prop])
    } catch {}
    controller[prop] = null
  })
}

function installDeadViewerShim(viewer) {
  if (!viewer) return null

  const noop = () => {}
  const defineValue = (key, value) => {
    try {
      Object.defineProperty(viewer, key, {
        value,
        configurable: true,
        writable: true,
      })
    } catch {
      try {
        viewer[key] = value
      } catch {}
    }
  }
  const deadMoveEnd = {
    addEventListener: noop,
    removeEventListener: noop,
  }
  const deadCamera = {
    moveEnd: deadMoveEnd,
    flyTo: noop,
    setView: noop,
    getPickRay: () => null,
    position: { x: 0, y: 0, z: 0 },
    positionWC: { x: 0, y: 0, z: 0 },
    positionCartographic: { longitude: 0, latitude: 0, height: 0 },
    heading: 0,
    pitch: 0,
    roll: 0,
  }
  const deadScene = {
    camera: deadCamera,
    canvas: { clientWidth: 0, clientHeight: 0, width: 0, height: 0 },
    globe: {
      pick: () => null,
      show: false,
      enableLighting: false,
      showGroundAtmosphere: false,
      maximumScreenSpaceError: 0,
    },
    fog: { enabled: false },
    skyAtmosphere: { show: false },
    skyBox: { show: false },
    primitives: {
      add: noop,
      remove: noop,
      removeAll: noop,
    },
    screenSpaceCameraController: { enableRotate: true },
    requestRender: noop,
    render: noop,
    setTerrain: noop,
    sampleHeightMostDetailed: () => Promise.resolve([]),
    drillPick: () => [],
    pick: () => null,
    verticalExaggeration: 1,
    backgroundColor: null,
    fxaa: false,
  }

  defineValue("_cesiumWidget", { scene: deadScene })
  defineValue("dataSources", {
    add: noop,
    remove: noop,
    removeAll: noop,
  })
  defineValue("clock", { currentTime: null })

  return viewer
}

export function initializeCoreState(controller) {
  controller._destroyed = false
  controller._airportDb = {}
  controller.flightsVisible = false
  controller.flightInterval = null
  controller.flightData = new Map()
  controller.selectedFlights = new Set()
  controller.selectedShips = new Set()
  controller.selectedSats = new Set()
  controller._selectionBoxEntities = new Map()
  controller._focusedSelection = null
  controller._selBoxImgGreen = null
  controller._selBoxImgYellow = null
  controller.animationFrame = null
  controller.lastAnimTime = null
  controller.trailsVisible = false
  controller.trailHistory = new Map()
  controller.trackedFlightId = null
  controller.trackedTrainId = null
  controller._trackingHeights = [5000, 50000, 200000, 800000]
  controller._trackingHeightLabels = ["Street", "Close", "Medium", "Far"]
  controller._trackingHeightIdx = 2
  controller.showCivilian = true
  controller.showMilitary = true
  controller._milFlightsActive = false
  controller._milFlightData = []
  controller._milFlightEntities = []
  controller._milFlightInterval = null
  controller.satelliteData = []
  controller._loadedSatCategories = new Set()
  controller.satelliteEntities = new Map()
  controller.satCategoryVisible = satCategoryVisibility()
  controller.satOrbitsVisible = false
  controller.satOrbitEntities = new Map()
  controller.selectedSatNoradId = null
  controller._satFootprintEntities = []
  controller.satHeatmapVisible = false
  controller._heatmapEntities = []
  controller._heatmapGrid = new Map()
  controller._heatmapHitLifeSec = 60
  controller._heatmapLastUpdate = 0
  controller._sweepEntities = []
  controller._lastSatPositions = []
  controller._buildHeatmapActive = false
  controller._buildHeatmapBaseEntities = []
  controller._buildHeatmapGrid = new Map()
  controller.shipsVisible = false
  controller.shipData = new Map()
  controller.shipInterval = null
  controller.bordersVisible = false
  controller.bordersLoaded = false
  controller.selectedCountries = new Set()
  controller._selectedCountriesBbox = null
  controller._borderCountryMap = new Map()
  controller._countryEntities = new Map()
  controller._countryFeatures = []
  controller.citiesVisible = false
  controller._citiesData = []
  controller._urbanAreas = []
  controller._citiesLoaded = false
  controller._cityEntities = []
  controller.earthquakesVisible = false
  controller._earthquakeData = []
  controller._earthquakeEntities = []
  controller.naturalEventsVisible = false
  controller._naturalEventData = []
  controller._naturalEventEntities = []
  controller._eventsInterval = null
  controller.fireHotspotsVisible = false
  controller.fireClustersVisible = true
  controller._fireHotspotFetchToken = 0
  controller._fireHotspotData = []
  controller._fireHotspotClusterData = []
  controller._fireHotspotEntities = []
  controller.strikesVisible = false
  controller._strikeDetections = []
  controller._strikeEntities = []
  controller._gcDetections = []
  controller.weatherVisible = false
  controller._weatherActiveLayers = {}
  controller._weatherImageryLayers = {}
  controller._weatherAlerts = []
  controller._weatherAlertEntities = []
  controller._weatherOpacity = 0.6
  controller.financialVisible = false
  controller._financialInterval = null
  controller._commodityData = []
  controller._marketBenchmarkData = []
  controller._financialEntities = []
  controller.camerasVisible = false
  controller.gpsJammingVisible = false
  controller._gpsJammingEntities = []
  controller._gpsJammingInterval = null
  controller.newsVisible = false
  controller.newsArcsVisible = true
  controller.newsBlobsVisible = true
  controller._newsData = []
  controller._newsEntities = []
  controller._newsArcEntities = []
  controller._newsInterval = null
  controller._newsActiveTab = "articles"
  controller.cablesVisible = false
  controller._cableEntities = []
  controller._landingPointEntities = []
  controller.portsVisible = false
  controller._portAll = []
  controller._portData = []
  controller._portEntities = []
  controller.shippingLanesVisible = false
  controller._shippingLaneEntities = []
  controller._shippingLaneData = []
  controller.pipelinesVisible = false
  controller._pipelineEntities = []
  controller._pipelineData = []
  controller.railwaysVisible = false
  controller._railwayEntities = []
  controller._railwayData = []
  controller.trainsVisible = false
  controller._trainEntities = []
  controller._trainData = []
  controller._trainPollTimer = null
  controller._rightPanelUserClosed = false
  controller.outagesVisible = false
  controller._outageData = []
  controller._outageEntities = []
  controller._outageInterval = null
  controller.insightsVisible = false
  controller._insightsData = []
  controller._insightEntities = []
  controller._insightPollInterval = null
  controller._insightFetchToken = 0
  controller.powerPlantsVisible = false
  controller._powerPlantData = []
  controller._powerPlantEntities = []
  controller.conflictsVisible = false
  controller._conflictData = []
  controller._conflictEntities = []
  controller.situationsVisible = false
  controller._conflictPulseData = []
  controller._conflictPulseZones = []
  controller._conflictPulseEntities = []
  controller._conflictPulseInterval = null
  controller._conflictPulseFetchToken = 0
  controller._conflictPulsePrev = {}
  controller._conflictPulsePrevScores = {}
  controller._conflictPulseSnapshotStatus = null
  controller._strategicSituationData = []
  controller._strikeArcData = []
  controller._hexCellData = []
  controller._strikeArcsVisible = false
  controller._hexTheaterVisible = false
  controller.chokepointsVisible = false
  controller._chokepointData = []
  controller._chokepointEntities = []
  controller._chokepointSnapshotStatus = null
  controller.militaryBasesVisible = false
  controller._militaryBaseData = []
  controller._militaryBaseEntities = []
  controller.airbasesVisible = false
  controller._airbaseEntities = []
  controller.navalVesselsVisible = false
  controller._navalVesselEntities = []
  controller.trafficVisible = false
  controller.trafficArcsVisible = true
  controller.trafficBlobsVisible = true
  controller._trafficData = null
  controller._trafficEntities = []
  controller.notamsVisible = false
  controller._notamData = []
  controller._notamEntities = []
  controller._satVisEntities = []
  controller._satVisEventPos = null
  controller.airportsVisible = false
  controller._airportEntities = []
  controller._webcamData = []
  controller._webcamEntities = []
  controller._webcamEntityMap = new Map()
  controller._webcamFetchToken = 0
  controller._webcamLastFetchCenter = null
  controller._webcamCollectionStatus = null
  controller._trainFeedFetchedAt = null
  controller._trainFeedExpiresAt = null
  controller._insightSnapshotStatus = null
  controller.countrySelectMode = false
  controller.drawMode = false
  controller._drawCenter = null
  controller._drawing = false
  controller._drawCircleEntity = null
  controller._satFootprintCountryMode = false
  controller._airlineFilter = new Set()
  controller._detectedAirlines = new Map()
  controller._pendingCountryRestore = null
  controller._entityListRequested = false
  controller._alertData = []
  controller._alertUnseenCount = 0
  controller._selectedContext = null
  controller._theaterBriefCache = new Map()
  controller._anchoredDetailState = null
  controller._pinnedAnchoredDetails = []
  controller._pinnedAnchoredDetailSeq = 0
  controller._ds = {}
  controller._backgroundRefreshRetryTimers = {}
  controller._backgroundRefreshRetryCounts = {}
}

export function wireCoreChrome(controller) {
  controller._clockInterval = setInterval(() => controller._updateClock(), 1000)
  controller._updateClock()
  controller._initTooltips()

  controller._onAlertsFeedToggle = () => controller.toggleAlertsFeed()
  controller._onRightPanelToggle = () => controller.toggleRightPanel()
  controller._onBreakingEvent = (event) => {
    const data = event.detail
    if (data.type === "earthquake" && controller.earthquakesVisible) {
      controller.fetchEarthquakes?.()
    } else if (data.type === "conflict_escalation" && controller.situationsVisible) {
      controller._fetchConflictPulse?.()
    }
  }

  controller._statBellButton = document.getElementById("stat-bell-btn")
  if (controller._statBellButton) {
    controller._statBellButton.addEventListener("click", controller._onAlertsFeedToggle)
  }

  controller._statPanelButton = document.getElementById("stat-panel-toggle")
  if (controller._statPanelButton) {
    controller._statPanelButton.addEventListener("click", controller._onRightPanelToggle)
  }

  document.addEventListener("globe:breaking-event", controller._onBreakingEvent)
}

export function teardownCore(controller) {
  controller._destroyed = true
  controller._teardownMobileUi?.()
  Object.values(controller._backgroundRefreshRetryTimers || {}).forEach(timer => clearTimeout(timer))
  TIMEOUT_PROPS.forEach(prop => {
    if (controller[prop]) clearTimeout(controller[prop])
  })
  INTERVAL_PROPS.forEach(prop => {
    if (controller[prop]) clearInterval(controller[prop])
  })
  RAF_PROPS.forEach(prop => {
    if (controller[prop]) cancelAnimationFrame(controller[prop])
  })

  if (controller._mediaRecorder) controller._stopRecording?.()
  controller._stopMiniTimeline?.()
  controller._stopAlertPolling?.()
  controller._stopInsightPolling?.()
  controller._stopConflictPulse?.()
  controller._stopTrafficBlobAnim?.()
  controller._stopNewsArcBlobAnim?.()

  if (controller._statBellButton && controller._onAlertsFeedToggle) {
    controller._statBellButton.removeEventListener("click", controller._onAlertsFeedToggle)
  }
  if (controller._statPanelButton && controller._onRightPanelToggle) {
    controller._statPanelButton.removeEventListener("click", controller._onRightPanelToggle)
  }
  if (controller._onBreakingEvent) {
    document.removeEventListener("globe:breaking-event", controller._onBreakingEvent)
  }

  if (controller._handler) controller._handler.destroy()
  if (controller._ytMessageCleanup) {
    controller._ytMessageCleanup()
    controller._ytMessageCleanup = null
  }

  const viewer = controller.viewer
  detachCameraMoveEndCallbacks(controller, viewer)

  if (viewer) {
    try {
      viewer.destroy()
    } finally {
      controller.viewer = installDeadViewerShim(viewer)
    }
  } else {
    controller.viewer = null
  }
}
