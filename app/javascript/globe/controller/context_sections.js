export function applyContextSectionMethods(GlobeController) {
  GlobeController.prototype._durableContextSections = function(context) {
    if (!context?.nodeRequest) return []
    if (context.nodeContextStatus === "loading") {
      return [{ title: "Graph context", html: '<div class="insight-empty">Loading durable node context…</div>' }]
    }
    if (context.nodeContextStatus === "error") {
      return [{ title: "Graph context", html: '<div class="insight-empty">Durable node context is unavailable for this selection.</div>' }]
    }
    if (context.nodeContextStatus !== "ready" || !context.nodeContext) return []

    const payload = context.nodeContext
    const sections = []

    if ((payload.memberships || []).length) {
      sections.push({
        title: "Canonical actors",
        items: payload.memberships.map(membership => ({
          label: membership.node?.name || membership.role,
          meta: [membership.role, membership.confidence != null ? `${Math.round(membership.confidence * 100)}%` : null].filter(Boolean).join(" · "),
          nodeRequest: this._nodeRequestForGraphNode(membership.node),
        })),
      })
    }

    if ((payload.evidence || []).length) {
      sections.push({
        title: "Durable evidence",
        items: payload.evidence.map(item => ({
          label: item.label,
          meta: [item.role, item.meta].filter(Boolean).join(" · "),
          nodeRequest: this._nodeRequestForEvidence(item),
          url: item.url,
        })),
      })
    }

    if ((payload.relationships || []).length) {
      sections.push({
        title: "Relationships",
        items: payload.relationships.map(rel => ({
          label: rel.node?.name || rel.relation_type,
          meta: [
            rel.relation_type?.replace(/_/g, " "),
            rel.confidence != null ? `${Math.round(rel.confidence * 100)}%` : null,
            rel.evidence?.length ? rel.evidence.map(ev => ev.label).filter(Boolean).slice(0, 2).join(" · ") : null,
          ].filter(Boolean).join(" · "),
          nodeRequest: this._nodeRequestForGraphNode(rel.node),
        })),
      })
    }

    return sections
  }

  GlobeController.prototype._dynamicContextSections = function(context) {
    const coords = this._contextCoordinates(context)
    if (!coords) return []

    return [
      this._buildObservationContextSection(coords),
      this._buildLayerDiscoverabilitySection(coords),
    ].filter(Boolean)
  }

  GlobeController.prototype._contextCoordinates = function(context) {
    const direct = context?.coordinates
    if (Number.isFinite(direct?.lat) && Number.isFinite(direct?.lng)) return direct

    const node = context?.nodeContext?.node
    if (Number.isFinite(node?.latitude) && Number.isFinite(node?.longitude)) {
      return {
        lat: node.latitude,
        lng: node.longitude,
        height: direct?.height || 450000,
      }
    }

    const focusAction = (context?.actions || []).find(action => Number.isFinite(action?.lat) && Number.isFinite(action?.lng))
    if (focusAction) {
      return {
        lat: focusAction.lat,
        lng: focusAction.lng,
        height: focusAction.height || 450000,
      }
    }

    return null
  }

  GlobeController.prototype._buildObservationContextSection = function(coords) {
    const nearbyCameras = this._nearbyCamerasForContext(coords).slice(0, 4)
    if (nearbyCameras.length) {
      return {
        title: "Nearby observation",
        items: nearbyCameras.map(cam => {
          const badge = this._cameraModeBadge(cam)
          const distance = `${cam.distanceKm.toFixed(cam.distanceKm < 10 ? 1 : 0)} km`
          return {
            label: cam.title || "Nearby camera",
            meta: [
              this._cameraSourceLabel(cam),
              this._cameraFreshnessLabel(cam),
              distance,
            ].filter(Boolean).join(" · "),
            badge: {
              label: badge.label,
              variant: this._cameraModeChipVariant(cam),
            },
            cameraId: cam.id,
          }
        }),
      }
    }

    if (!this.camerasVisible) {
      return {
        title: "Nearby observation",
        items: [{
          label: "Enable cameras",
          meta: "Show nearby live streams and webcam feeds around this location.",
          badge: { label: "CAM", variant: "news" },
          layerKey: "cameras",
          rpTab: "cameras",
          lat: coords.lat,
          lng: coords.lng,
          height: coords.height || 300000,
        }],
      }
    }

    return null
  }

  GlobeController.prototype._buildLayerDiscoverabilitySection = function(coords) {
    const items = []
    const suggestions = []

    const newsCount = this._countNearbyRecords(this._newsData || [], coords, 180, item => ({ lat: item.lat, lng: item.lng }))
    if (newsCount > 0) {
      items.push({
        label: "News reporting",
        meta: `${newsCount} nearby stor${newsCount === 1 ? "y" : "ies"} in the loaded news layer`,
        badge: { label: "NEWS", variant: "news" },
        layerKey: "news",
        rpTab: "news",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 400000,
      })
    } else if (!this.newsVisible) {
      suggestions.push({
        label: "News reporting",
        meta: "Enable the news layer to inspect nearby corroborating reporting.",
        badge: { label: "NEWS", variant: "news" },
        layerKey: "news",
        rpTab: "news",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 400000,
      })
    }

    const weatherCount = this._countNearbyRecords(this._weatherAlerts || [], coords, 220, item => ({ lat: item.latitude, lng: item.longitude }))
    if (weatherCount > 0) {
      items.push({
        label: "Weather alerts",
        meta: `${weatherCount} nearby alert${weatherCount === 1 ? "" : "s"} in the weather layer`,
        badge: { label: "WX", variant: "event" },
        layerKey: "weather",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 600000,
      })
    } else if (!this.weatherVisible) {
      suggestions.push({
        label: "Weather alerts",
        meta: "Enable weather to check for storm, flood, or wind disruption nearby.",
        badge: { label: "WX", variant: "event" },
        layerKey: "weather",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 600000,
      })
    }

    const earthquakeCount = this._countNearbyRecords(this._earthquakeData || [], coords, 280, item => ({ lat: item.lat, lng: item.lng }))
    if (earthquakeCount > 0) {
      items.push({
        label: "Earthquakes",
        meta: `${earthquakeCount} recent event${earthquakeCount === 1 ? "" : "s"} in the earthquake layer`,
        badge: { label: "EQ", variant: "eq" },
        layerKey: "earthquakes",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 900000,
      })
    } else if (!this.earthquakesVisible) {
      suggestions.push({
        label: "Earthquakes",
        meta: "Enable quakes to check for nearby seismic corroboration.",
        badge: { label: "EQ", variant: "eq" },
        layerKey: "earthquakes",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 900000,
      })
    }

    const outageCount = this._countNearbyRecords(this._outageData || [], coords, 260, item => ({ lat: item.lat, lng: item.lng }))
    if (outageCount > 0) {
      items.push({
        label: "Internet outages",
        meta: `${outageCount} nearby outage${outageCount === 1 ? "" : "s"} in the outage layer`,
        badge: { label: "OUT", variant: "outage" },
        layerKey: "outages",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 700000,
      })
    } else if (!this.outagesVisible) {
      suggestions.push({
        label: "Internet outages",
        meta: "Enable outages to check for communications disruption nearby.",
        badge: { label: "OUT", variant: "outage" },
        layerKey: "outages",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 700000,
      })
    }

    const situationCount = this._countNearbyRecords(
      [...(this._conflictPulseZones || []), ...(this._strategicSituationData || [])],
      coords,
      260,
      item => ({ lat: item.lat, lng: item.lng })
    )
    if (situationCount > 0) {
      items.push({
        label: "Situations",
        meta: `${situationCount} nearby theater or strategic situation marker${situationCount === 1 ? "" : "s"}`,
        badge: { label: "SIT", variant: "conf" },
        rpTab: "situations",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 900000,
      })
    }

    const insightCount = this._countNearbyRecords(this._insightsData || [], coords, 260, item => ({ lat: item.lat, lng: item.lng }))
    if (insightCount > 0) {
      items.push({
        label: "Insights",
        meta: `${insightCount} nearby cross-layer insight${insightCount === 1 ? "" : "s"}`,
        badge: { label: "INS", variant: "fire" },
        rpTab: "insights",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 900000,
      })
    }

    const flightCount = this._countNearbyRecords(Array.from(this.flightData?.values?.() || []), coords, 180, item => ({ lat: item.lat || item.latitude, lng: item.lng || item.longitude }))
    if (flightCount > 0) {
      items.push({
        label: "Flights",
        meta: `${flightCount} nearby aircraft in the live flight layer`,
        badge: { label: "FLT", variant: "flight" },
        layerKey: "flights",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 550000,
      })
    }

    const shipCount = this._countNearbyRecords(Array.from(this.shipData?.values?.() || []), coords, 180, item => ({ lat: item.lat || item.latitude, lng: item.lng || item.longitude }))
    if (shipCount > 0) {
      items.push({
        label: "Ships",
        meta: `${shipCount} nearby vessel${shipCount === 1 ? "" : "s"} in the AIS layer`,
        badge: { label: "AIS", variant: "cable" },
        layerKey: "ships",
        lat: coords.lat,
        lng: coords.lng,
        height: coords.height || 550000,
      })
    }

    const renderedItems = items.slice(0, 6)
    if (suggestions.length && renderedItems.length < 6) {
      renderedItems.push(...suggestions.slice(0, 6 - renderedItems.length))
    }

    if (!renderedItems.length) return null

    return {
      title: "Other layers here",
      items: renderedItems,
    }
  }

  GlobeController.prototype._nearbyCamerasForContext = function(coords, radiusKm = 160) {
    return this._sortWebcams(this._webcamData || [])
      .filter(cam => Number.isFinite(cam?.lat) && Number.isFinite(cam?.lng))
      .map(cam => ({
        ...cam,
        distanceKm: this.haversineDistance(coords, { lat: cam.lat, lng: cam.lng }),
      }))
      .filter(cam => cam.distanceKm <= radiusKm)
      .sort((a, b) => {
        const priorityDelta = this._cameraPriorityScore(b) - this._cameraPriorityScore(a)
        if (priorityDelta !== 0) return priorityDelta
        return a.distanceKm - b.distanceKm
      })
  }

  GlobeController.prototype._cameraModeChipVariant = function(cam) {
    return {
      realtime: "fire",
      live: "event",
      periodic: "eq",
      stale: "outage",
    }[this._cameraMode(cam)] || "eq"
  }

  GlobeController.prototype._countNearbyRecords = function(records, coords, radiusKm, extractor) {
    return (records || []).filter(record => {
      const point = extractor(record)
      if (!Number.isFinite(point?.lat) || !Number.isFinite(point?.lng)) return false
      return this.haversineDistance(coords, point) <= radiusKm
    }).length
  }
}
