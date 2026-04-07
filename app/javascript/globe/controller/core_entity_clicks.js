export function applyCoreEntityClickMethods(GlobeController) {
  GlobeController.prototype._handleEntityClick = function(entityId, picked) {
    const flightData = this.flightData.get(entityId)
    if (flightData) {
      this.toggleFlightSelection(entityId)
      this.showDetail(entityId, flightData)
      return true
    }

    if (typeof entityId !== "string") return false

    const handlers = [
      { prefix: "tl-flight-", skip: [], handler: (id) => {
        const snap = this._timelineLastKnown?.get(`flight-${id}`)
        if (!snap) return false
        this._showTimelineFlightDetail(id, snap)
        return true
      }},
      { prefix: "tl-ship-", skip: [], handler: (id) => {
        const snap = this._timelineLastKnown?.get(`ship-${id}`)
        if (!snap) return false
        this._showTimelineShipDetail(id, snap)
        return true
      }},
      { prefix: "ship-", skip: [], handler: (id) => {
        const data = this.shipData.get(id)
        if (!data) return false
        this.toggleShipSelection(id)
        this.showShipDetail(data)
        return true
      }},
      { prefix: "border-", skip: [], handler: (id) => {
        if (!this.countrySelectMode) return false
        const data = this._borderCountryMap?.get("border-" + id)
        if (!data) return false
        this.toggleCountrySelection(data.name)
        this.showBorderDetail()
        return true
      }},
      { prefix: "sat-", skip: [], handler: (id) => {
        const noradId = parseInt(id, 10)
        const data = this.satelliteData.find(sat => sat.norad_id === noradId)
        if (!data) return false
        this.toggleSatSelection(noradId)
        this.showSatelliteDetail(data)
        return true
      }},
      { prefix: "train-", skip: [], handler: (id) => {
        const data = this._trainData?.find(train => train.id === id)
        if (!data) return false
        this.showTrainDetail(data)
        return true
      }},
      { prefix: "airport-", skip: [], handler: (id) => { this.showAirportDetail(id); return true }},
      { prefix: "eq-", skip: [], handler: (id) => {
        const data = this._earthquakeData.find(quake => quake.id === id)
        if (!data) return false
        this.showEarthquakeDetail(data)
        return true
      }},
      { prefix: "gc-", skip: [], handler: (id) => {
        const data = this._gcDetections?.find(gc => gc.id === id)
        if (!data) return false
        if (this._showCompactEntityDetail) {
          this._showCompactEntityDetail("geoconfirmed", data, { id })
        } else {
          this.showGeoconfirmedDetail(data)
        }
        return true
      }},
      { prefix: "strike-ring-", skip: [], handler: (id) => {
        const data = this._strikeDetections?.find(strike => strike.id === id)
        if (!data) return false
        this.showStrikeDetail(data, { id, picked })
        return true
      }},
      { prefix: "milflt-", skip: [], handler: (id) => {
        const data = this._milFlightData?.find(flight => flight.icao24 === id)
        if (!data) return false
        this.showDetail(id, {
          ...data,
          id,
          currentLat: data.latitude,
          currentLng: data.longitude,
          currentAlt: data.altitude,
          verticalRate: data.vertical_rate,
          originCountry: data.origin_country,
        })
        return true
      }},
      { prefix: "strike-", skip: [], handler: (id) => {
        const data = this._strikeDetections?.find(strike => strike.id === id)
        if (!data) return false
        this.showStrikeDetail(data, { id, picked })
        return true
      }},
      { prefix: "fire-cluster-ring-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._fireHotspotClusterData?.[idx]
        if (!data) return false
        this.showFireClusterDetail(data)
        return true
      }},
      { prefix: "fire-cluster-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._fireHotspotClusterData?.[idx]
        if (!data) return false
        this.showFireClusterDetail(data)
        return true
      }},
      { prefix: "fire-ring-", skip: [], handler: (id) => {
        const data = this._fireHotspotData?.find(fire => fire.id === id)
        if (!data) return false
        this.showFireHotspotDetail(data)
        return true
      }},
      { prefix: "fire-", skip: [], handler: (id) => {
        const data = this._fireHotspotData?.find(fire => fire.id === id)
        if (!data) return false
        this.showFireHotspotDetail(data)
        return true
      }},
      { prefix: "eonet-ring-", skip: [], handler: (id) => {
        const data = this._naturalEventData.find(event => event.id === id)
        if (!data) return false
        this.showNaturalEventDetail(data)
        return true
      }},
      { prefix: "eonet-", skip: [], handler: (id) => {
        const data = this._naturalEventData.find(event => event.id === id)
        if (!data) return false
        this.showNaturalEventDetail(data)
        return true
      }},
      { prefix: "news-arc-", skip: [], handler: () => {
        const idx = parseInt(entityId.replace(/^news-arc-(?:lbl-|arr-)?/, ""), 10)
        if (Number.isNaN(idx)) return false
        this.showNewsArcDetail(idx)
        return true
      }},
      { prefix: "news-", skip: ["news-arc-"], handler: (id) => {
        const data = this._newsData?.[parseInt(id, 10)]
        if (!data) return false
        this.showNewsDetail(data)
        return true
      }},
      { prefix: "outage-ring-", skip: [], handler: (id) => { this.showOutageDetail(id); return true }},
      { prefix: "outage-", skip: [], handler: (id) => { this.showOutageDetail(id); return true }},
      { prefix: "jam-lbl-", skip: [], handler: (id) => this.showGpsJammingDetail(id) },
      { prefix: "jam-", skip: ["jam-lbl-"], handler: (id) => this.showGpsJammingDetail(id) },
      { prefix: "cable-", skip: [], handler: () => {
        const props = picked.id.properties
        if (!props) return false
        this._highlightPolyline(picked.id)
        const name = props.cableName?.getValue() || "Unknown cable"
        this.detailContentTarget.innerHTML = `
          <div class="detail-callsign" style="color:#00bcd4;">
            <i class="fa-solid fa-network-wired" style="margin-right:6px;"></i>Submarine Cable
          </div>
          <div class="detail-country">${this._escapeHtml(name)}</div>
          <a href="https://www.submarinecablemap.com/submarine-cable/${props.cableId?.getValue() || ""}" target="_blank" rel="noopener" class="detail-track-btn">View on TeleGeography →</a>
        `
        this.detailPanelTarget.style.display = ""
        return true
      }},
      { prefix: "port-", skip: [], handler: (id) => {
        this.showPortDetail(id)
        return true
      }},
      { prefix: "shipping-lane-", skip: ["shipping-label-"], handler: () => {
        const laneId = picked.id.properties?.shippingLaneId?.getValue?.()
        if (!laneId) return false
        this._highlightPolyline(picked.id)
        this.showShippingLaneDetail(laneId)
        return true
      }},
      { prefix: "shipping-port-", skip: [], handler: () => {
        const laneId = picked.id.properties?.shippingLaneId?.getValue?.()
        if (!laneId) return false
        this.showShippingLaneDetail(laneId)
        return true
      }},
      { prefix: "shipping-stop-", skip: [], handler: () => {
        const laneId = picked.id.properties?.shippingLaneId?.getValue?.()
        if (!laneId) return false
        this.showShippingLaneDetail(laneId)
        return true
      }},
      { prefix: "pipeline-", skip: ["pipeline-label-"], handler: () => {
        const props = picked.id.properties
        if (!props) return false
        const pipeId = props.pipelineId?.getValue()
        if (!pipeId) return false
        this._highlightPolyline(picked.id)
        this.showPipelineDetail(pipeId)
        return true
      }},
      { prefix: "cam-", skip: [], handler: (id) => {
        const webcamId = picked.id.properties?.webcamId?.getValue?.()
        const data = this._webcamEntityMap.get("cam-" + id) ||
          this._webcamData.find(cam => String(cam.id) === id || String(cam.id) === String(webcamId))
        if (!data) return false
        this.showWebcamDetail(data)
        return true
      }},
      { prefix: "milbase-", skip: [], handler: (id) => {
        const data = this._militaryBaseData?.find(base => String(base.id) === id)
        if (!data) return false
        this.showMilitaryBaseDetail(data)
        return true
      }},
      { prefix: "airbase-", skip: [], handler: (id) => { this.showAirbaseDetail(id); return true }},
      { prefix: "naval-", skip: [], handler: (id) => {
        const data = this._navalShipData.get(id) || this._navalShipData.get(`${id}`)
        if (!data) return false
        this.showNavalVesselDetail(data)
        return true
      }},
      { prefix: "pp-atk-", skip: [], handler: (id) => {
        const data = this._powerPlantData.find(plant => plant.id === parseInt(id, 10))
        if (!data) return false
        this.showPowerPlantDetail(data)
        return true
      }},
      { prefix: "pp-", skip: [], handler: (id) => {
        const data = this._powerPlantData.find(plant => plant.id === parseInt(id, 10))
        if (!data) return false
        this.showPowerPlantDetail(data)
        return true
      }},
      { prefix: "comsite-", skip: [], handler: (id) => {
        const data = this._commoditySiteData?.find(site => `${site.id}` === `${id}`) ||
          this._commoditySiteAll?.find(site => `${site.id}` === `${id}`)
        if (!data) return false
        this.showCommoditySiteDetail(data)
        return true
      }},
      { prefix: "choke-zone-", skip: [], handler: (id) => {
        const data = this._chokepointData?.find(point => `${point.id}` === `${id}`)
        if (!data) return false
        this.showChokepointDetail(data)
        return true
      }},
      { prefix: "choke-ships-", skip: [], handler: (id) => {
        const data = this._chokepointData?.find(point => `${point.id}` === `${id}`)
        if (!data) return false
        this.showChokepointDetail(data)
        return true
      }},
      { prefix: "choke-", skip: [], handler: (id) => {
        const data = this._chokepointData?.find(point => `${point.id}` === `${id}`)
        if (!data) return false
        this.showChokepointDetail(data)
        return true
      }},
      { prefix: "rw-", skip: [], handler: (id) => {
        this._highlightPolyline(picked.id)
        this.showRailwayDetail(id)
        return true
      }},
      { prefix: "cpulse-arc-lbl-", handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._strikeArcData?.[idx]
        if (!arc) return false
        this.showStrikeArcDetail(arc)
        return true
      }},
      { prefix: "cpulse-arc-", handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._strikeArcData?.[idx]
        if (!arc) return false
        this.showStrikeArcDetail(arc)
        return true
      }},
      { prefix: "cpulse-hex-", handler: (id) => {
        const idx = parseInt(id, 10)
        const cell = this._hexCellData?.[idx]
        if (!cell) return false
        this._showHexDetail(cell)
        return true
      }},
      { prefix: "cpulse-strat-ring-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._strategicSituationData?.find(item => `${item.id || item.node_id || item.name}` === key)
        if (!data) return false
        this.showStrategicSituationDetail(data, { picked })
        return true
      }},
      { prefix: "cpulse-strat-lbl-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._strategicSituationData?.find(item => `${item.id || item.node_id || item.name}` === key)
        if (!data) return false
        this.showStrategicSituationDetail(data, { picked })
        return true
      }},
      { prefix: "cpulse-strat-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._strategicSituationData?.find(item => `${item.id || item.node_id || item.name}` === key)
        if (!data) return false
        this.showStrategicSituationDetail(data, { picked })
        return true
      }},
      { prefix: "cpulse-core-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._conflictPulseData?.find(zone => `${zone.cell_key}` === key)
        if (!data) return false
        this.showConflictPulseDetail(data, { picked })
        return true
      }},
      { prefix: "cpulse-pulse-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._conflictPulseData?.find(zone => `${zone.cell_key}` === key)
        if (!data) return false
        this.showConflictPulseDetail(data, { picked })
        return true
      }},
      { prefix: "cpulse-ring-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._conflictPulseData?.find(zone => `${zone.cell_key}` === key)
        if (!data) return false
        this.showConflictPulseDetail(data, { picked })
        return true
      }},
      { prefix: "cpulse-lbl-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._conflictPulseData?.find(zone => `${zone.cell_key}` === key)
        if (!data) return false
        this.showConflictPulseDetail(data, { picked })
        return true
      }},
      { prefix: "cpulse-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._conflictPulseData?.find(zone => `${zone.cell_key}` === key)
        if (!data) return false
        this.showConflictPulseDetail(data, { picked })
        return true
      }},
      { prefix: "conf-ring-", skip: [], handler: (id) => {
        const conflictId = /^\d+$/.test(id) ? parseInt(id, 10) : id
        const data = this._conflictData.find(event => `${event.id}` === `${conflictId}`)
        if (!data) return false
        this.showConflictDetail(data)
        return true
      }},
      { prefix: "conf-", skip: [], handler: (id) => {
        const conflictId = /^\d+$/.test(id) ? parseInt(id, 10) : id
        const data = this._conflictData.find(event => `${event.id}` === `${conflictId}`)
        if (!data) return false
        this.showConflictDetail(data)
        return true
      }},
      { prefix: "traf-lbl-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._attackArcData?.[idx]
        if (arc?.target) {
          this.showTrafficDetail(arc.target)
          return true
        }
        return false
      }},
      { prefix: "traf-atk-", skip: [], handler: (id) => { this.showTrafficDetail(id); return true }},
      { prefix: "traf-arc-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._attackArcData?.[idx]
        if (arc?.target) {
          this.showTrafficDetail(arc.target)
          return true
        }
        return false
      }},
      { prefix: "traf-", skip: [], handler: (id) => { this.showTrafficDetail(id); return true }},
      { prefix: "notam-lbl-", skip: [], handler: (id) => {
        const data = this._notamData?.find(notam => String(notam.id) === id)
        if (!data) return false
        this.showNotamDetail(data)
        return true
      }},
      { prefix: "notam-", skip: ["notam-warn-", "notam-lbl-"], handler: (id) => {
        const data = this._notamData?.find(notam => String(notam.id) === id)
        if (!data) return false
        this.showNotamDetail(data)
        return true
      }},
      { prefix: "wx-alert-", skip: [], handler: (id) => {
        const data = this._weatherAlerts?.[parseInt(id, 10)]
        if (!data) return false
        this.showWeatherAlertDetail(data)
        return true
      }},
      { prefix: "fin-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._commodityData?.[idx]
        if (!data) return false
        this.showCommodityDetail(data)
        return true
      }},
      { prefix: "insight-ring-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._insightsData?.[idx]
        if (!data) return false
        this.focusInsight({ currentTarget: { dataset: { insightIdx: String(idx) } } })
        return true
      }},
      { prefix: "insight-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._insightsData?.[idx]
        if (!data) return false
        this.focusInsight({ currentTarget: { dataset: { insightIdx: String(idx) } } })
        return true
      }},
    ]

    for (const { prefix, skip = [], handler } of handlers) {
      if (!entityId.startsWith(prefix)) continue
      if (skip.some(value => entityId.startsWith(value))) continue
      if (handler(entityId.slice(prefix.length))) return true
    }

    return false
  }
}
