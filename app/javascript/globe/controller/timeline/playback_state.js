import {
  DEFAULT_TIMELINE_RANGE_DAYS,
  TIMELINE_EVENT_DEBOUNCE_MS,
} from "globe/controller/timeline/constants"
import {
  eventPlaybackLayersVisible,
  movementPlaybackLayersVisible,
} from "globe/controller/timeline_contract"

export function initializeTimelineState(controller, range) {
  controller._timelineActive = true
  controller._timelinePlaying = false
  controller._timelineSpeed = 5
  controller._timelineFrames = {}
  controller._timelineKeys = []
  controller._timelineFrameIndex = 0
  controller._timelineAppliedFrameIndex = -1
  controller._timelineEventCount = 0
  controller._timelineSituationCount = 0
  controller._timelineEventFetchKey = null
  controller._timelineFetchedGeneralEvents = []
  controller._timelineFetchedStrikeEvents = []
  controller._timelineConflictFetchKey = null
  controller._timelineFetchedConflictEvents = []
  controller._timelineCommodityFetchKey = null
  controller._timelineSatelliteFetchKey = null
  controller._timelineLastRenderedCursorMs = null
  controller._timelineLastRenderedCursorKey = null
  controller._timelinePulseStarts = new Map()
  controller._timelinePulseAnimationActive = false
  controller._timelinePulseRaf = null

  const oldest = new Date(range.oldest)
  const newest = new Date(Math.min(new Date(range.newest).getTime(), Date.now()))
  const defaultRangeMs = DEFAULT_TIMELINE_RANGE_DAYS * 24 * 60 * 60 * 1000
  const defaultStart = new Date(newest.getTime() - defaultRangeMs)

  controller._timelineRangeStart = defaultStart > oldest ? defaultStart : oldest
  controller._timelineRangeEnd = newest
  controller._timelineOldest = oldest
  controller._timelineCursor = new Date(controller._timelineRangeStart.getTime())
  controller._timelineAutoEnabledLayers = []
}

export function resetTimelineState(controller) {
  controller._timelineLastKnown = null
  controller._timelineAppliedFrameIndex = -1
  controller._timelineEventFetchKey = null
  controller._timelineFetchedGeneralEvents = []
  controller._timelineFetchedStrikeEvents = []
  controller._timelineConflictFetchKey = null
  controller._timelineFetchedConflictEvents = []
  controller._timelineCommodityFetchKey = null
  controller._timelineSatelliteFetchKey = null
  controller._timelineLastRenderedCursorMs = null
  controller._timelineLastRenderedCursorKey = null
  controller._timelinePulseStarts = null
  controller._timelinePulseAnimationActive = false
  controller._timelinePulseRaf = null
}

export function syncTimelineScrubber(controller) {
  if (!controller.hasTimelineScrubberTarget) return
  const range = controller._timelineRangeEnd.getTime() - controller._timelineRangeStart.getTime()
  if (range <= 0) return
  const pos = ((controller._timelineCursor.getTime() - controller._timelineRangeStart.getTime()) / range) * 10000
  controller.timelineScrubberTarget.value = Math.round(pos)
}

export function updateTimelineCursorDisplay(controller) {
  if (!controller._timelineCursor) return
  const cursor = controller._timelineCursor
  if (controller.hasTimelineCursorDateTarget) controller.timelineCursorDateTarget.textContent = cursor.toISOString().slice(0, 10)
  if (controller.hasTimelineCursorTimeTarget) controller.timelineCursorTimeTarget.textContent = cursor.toUTCString().slice(17, 25)
}

export function debounceTimelineRefresh(controller) {
  if (controller._timelinePlaying && controller._timelineEventTimer) return
  if (controller._timelineEventTimer) clearTimeout(controller._timelineEventTimer)
  controller._timelineEventTimer = setTimeout(async () => {
    controller._timelineEventTimer = null
    await controller._timelineRefreshPlaybackState()
  }, controller._timelinePlaying ? TIMELINE_EVENT_DEBOUNCE_MS.playing : TIMELINE_EVENT_DEBOUNCE_MS.scrub)
}

export function autoEnablePlaybackLayers(controller) {
  const movementDefs = [
    { key: "flights", hasTargetProp: "hasFlightsToggleTarget", targetProp: "flightsToggleTarget", visibleProp: "flightsVisible" },
    { key: "ships", hasTargetProp: "hasShipsToggleTarget", targetProp: "shipsToggleTarget", visibleProp: "shipsVisible" },
  ]
  const eventDefs = [
    { key: "situations", hasTargetProp: "hasSituationsToggleTarget", targetProp: "situationsToggleTarget", visibleProp: "situationsVisible" },
    { key: "news", hasTargetProp: "hasNewsToggleTarget", targetProp: "newsToggleTarget", visibleProp: "newsVisible" },
    { key: "verifiedStrikes", hasTargetProp: "hasVerifiedStrikesToggleTarget", targetProp: "verifiedStrikesToggleTarget", visibleProp: "verifiedStrikesVisible" },
    { key: "heatSignatures", hasTargetProp: "hasHeatSignaturesToggleTarget", targetProp: "heatSignaturesToggleTarget", visibleProp: "heatSignaturesVisible" },
    { key: "earthquakes", hasTargetProp: "hasEarthquakesToggleTarget", targetProp: "earthquakesToggleTarget", visibleProp: "earthquakesVisible" },
    { key: "naturalEvents", hasTargetProp: "hasNaturalEventsToggleTarget", targetProp: "naturalEventsToggleTarget", visibleProp: "naturalEventsVisible" },
    { key: "gpsJamming", hasTargetProp: "hasGpsJammingToggleTarget", targetProp: "gpsJammingToggleTarget", visibleProp: "gpsJammingVisible" },
    { key: "outages", hasTargetProp: "hasOutagesToggleTarget", targetProp: "outagesToggleTarget", visibleProp: "outagesVisible" },
    { key: "financial", hasTargetProp: "hasFinancialToggleTarget", targetProp: "financialToggleTarget", visibleProp: "financialVisible" },
    { key: "traffic", hasTargetProp: "hasTrafficToggleTarget", targetProp: "trafficToggleTarget", visibleProp: "trafficVisible" },
  ]

  controller._timelineAutoEnabledLayers = []

  if (controller.hasActiveFilter?.() && !movementPlaybackLayersVisible(controller)) {
    autoEnableLayerSet(controller, movementDefs)
  }

  if (!eventPlaybackLayersVisible(controller)) {
    autoEnableLayerSet(controller, eventDefs)
  }

  if (controller._timelineAutoEnabledLayers.length === 0) return

  controller._syncStrikeSignalsVisibility?.()
  controller._syncQuickBar?.()
  controller._updateStats?.()
}

export function revertAutoEnabledPlaybackLayers(controller) {
  if (!Array.isArray(controller._timelineAutoEnabledLayers) || controller._timelineAutoEnabledLayers.length === 0) return

  controller._timelineAutoEnabledLayers.forEach((def) => {
    controller[def.visibleProp] = false
    if (def.targetProp && controller[def.targetProp]) controller[def.targetProp].checked = false
  })

  controller._syncStrikeSignalsVisibility?.()
  controller._timelineAutoEnabledLayers = []
}

export function showTimelineAvailabilityToast(controller, frameStatus, eventCount, situationCount, opening) {
  const frameCount = frameStatus?.frameCount || 0
  const hasEventPlayback = controller.earthquakesVisible || controller.naturalEventsVisible || controller.newsVisible ||
    controller.gpsJammingVisible || controller.outagesVisible || controller.weatherVisible || controller.notamsVisible ||
    controller.conflictsVisible || controller.financialVisible || controller.trafficVisible || controller.situationsVisible ||
    controller.fireHotspotsVisible || strikeSignalsVisible(controller) || Object.values(controller.satCategoryVisible || {}).some(Boolean)

  if (frameStatus?.boundsRequired) {
    if ((eventCount || 0) > 0 || (situationCount || 0) > 0) {
      controller._toast("Zoom in or apply a region filter for movement playback. Time-scoped events and theaters are active.")
    } else {
      controller._toast("Zoom in or apply a region filter to load movement playback.")
    }
    return
  }

  if (frameCount > 0) {
    const suffix = opening ? " — press play" : ""
    controller._toast(`Time travel: ${frameCount} movement frames loaded${suffix}`, "success")
    return
  }

  if (hasEventPlayback) {
    if ((eventCount || 0) > 0 || (situationCount || 0) > 0) {
      const parts = []
      if ((eventCount || 0) > 0) parts.push(`${eventCount} timeline events`)
      if ((situationCount || 0) > 0) parts.push(`${situationCount} situation zones`)
      controller._toast(`Event playback ready: ${parts.join(" · ")}`)
      return
    }

    if (frameStatus?.movementEnabled === false) {
      controller._toast("Event playback ready. Enable flights or ships if you also want movement snapshots.")
      return
    }

    controller._toast("No flight or ship snapshots in this range. Event playback is still available.")
    return
  }

  controller._toast("No playback data found for this time range", "error")
}

export async function refreshTimelineCursorLayers(controller) {
  if (!controller._timelineActive) return

  const tasks = []
  if (controller.financialVisible) tasks.push(Promise.resolve(controller.fetchCommodities?.()))
  if (controller.trafficVisible) tasks.push(Promise.resolve(controller.fetchTraffic?.({ silent: true })))
  if (Object.values(controller.satCategoryVisible || {}).some(Boolean)) {
    tasks.push(Promise.resolve(controller.fetchPlaybackSatellites?.()))
  }

  if (tasks.length === 0) return
  await Promise.all(tasks)
}

function autoEnableLayerSet(controller, defs) {
  defs.forEach((def) => {
    if (controller[def.visibleProp]) return
    if (def.hasTargetProp && !controller[def.hasTargetProp]) return

    controller[def.visibleProp] = true
    if (def.targetProp && controller[def.targetProp]) controller[def.targetProp].checked = true
    controller._timelineAutoEnabledLayers.push(def)
  })
}

function strikeSignalsVisible(controller) {
  return typeof controller._strikeSignalsVisible === "function"
    ? controller._strikeSignalsVisible()
    : !!(controller?.verifiedStrikesVisible || controller?.heatSignaturesVisible || controller?.strikesVisible)
}
