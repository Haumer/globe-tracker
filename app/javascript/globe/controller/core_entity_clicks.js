export function applyCoreEntityClickMethods(GlobeController) {
  GlobeController.prototype._handleEntityClick = function(entityId, picked, screenPosition = null) {
    const clickAnchor = this._anchoredDetailClickAnchor?.(screenPosition)
    if (clickAnchor) {
      picked = picked
        ? { ...picked, id: picked.id, primitive: picked.primitive, clickAnchor }
        : { clickAnchor }
    }

    const showAnchored = (kind, data, options = {}, fallback = null) => {
      if (data && this._showCompactEntityDetail?.(kind, data, { ...options, picked })) return true
      if (typeof fallback === "function") return fallback() !== false
      return false
    }

    const showNewsByIndex = (id) => {
      const data = this._newsData?.[parseInt(id, 10)]
      if (!data) return false
      if (!showAnchored("news", data, { id })) this.showNewsDetail(data)
      return true
    }

    const flightData = this.flightData.get(entityId)
    if (flightData) {
      this.toggleFlightSelection(entityId)
      if (!showAnchored("flight", flightData, { id: entityId, focusSelection: { type: "flight", id: entityId } })) {
        this.showDetail(entityId, flightData)
      }
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
        if (!showAnchored("ship", data, { id, focusSelection: { type: "ship", id } })) this.showShipDetail(data)
        return true
      }},
      { prefix: "border-fill-", skip: [], handler: (id) => {
        const data = this._borderCountryMap?.get("border-fill-" + id)
        if (!data) return false
        if (!this.countrySelectMode && this.showRegionalIndicatorCountry?.(data.name, { picked })) return true
        if (!this.countrySelectMode) return false
        this.toggleCountrySelection(data.name)
        this.showBorderDetail()
        return true
      }},
      { prefix: "border-", skip: [], handler: (id) => {
        const data = this._borderCountryMap?.get("border-" + id)
        if (!data) return false
        if (!this.countrySelectMode && this.showRegionalIndicatorCountry?.(data.name, { picked })) return true
        if (!this.countrySelectMode) return false
        this.toggleCountrySelection(data.name)
        this.showBorderDetail()
        return true
      }},
      { prefix: "sat-", skip: [], handler: (id) => {
        const noradId = parseInt(id, 10)
        const data = this.satelliteData.find(sat => sat.norad_id === noradId)
        if (!data) return false
        this.toggleSatSelection(noradId)
        if (!showAnchored("satellite", data, { id, focusSelection: { type: "sat", id: noradId } })) this.showSatelliteDetail(data)
        return true
      }},
      { prefix: "train-", skip: [], handler: (id) => {
        const data = this._trainData?.find(train => train.id === id)
        if (!data) return false
        if (!showAnchored("train", data, { id })) this.showTrainDetail(data)
        return true
      }},
      { prefix: "airport-", skip: [], handler: (id) => {
        const data = this._getAirport?.(id)
        if (!data) return false
        if (!showAnchored("airport", data, { id })) this.showAirportDetail(id)
        return true
      }},
      { prefix: "eq-", skip: [], handler: (id) => {
        const data = this._earthquakeData.find(quake => quake.id === id)
        if (!data) return false
        if (!showAnchored("earthquake", data, { id })) this.showEarthquakeDetail(data)
        return true
      }},
      { prefix: "gc-", skip: [], handler: (id) => {
        const data = this._gcDetections?.find(gc => gc.id === id)
        if (!data) return false
        if (this._showCompactEntityDetail) {
          this._showCompactEntityDetail("geoconfirmed", data, { id, picked })
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
        const detailData = {
          ...data,
          id,
          currentLat: data.latitude,
          currentLng: data.longitude,
          currentAlt: data.altitude,
          verticalRate: data.vertical_rate,
          originCountry: data.origin_country,
        }
        if (!showAnchored("flight", detailData, { id, focusSelection: { type: "flight", id } })) this.showDetail(id, detailData)
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
        if (!showAnchored("fire_cluster", data, { id })) this.showFireClusterDetail(data)
        return true
      }},
      { prefix: "fire-cluster-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._fireHotspotClusterData?.[idx]
        if (!data) return false
        if (!showAnchored("fire_cluster", data, { id })) this.showFireClusterDetail(data)
        return true
      }},
      { prefix: "fire-ring-", skip: [], handler: (id) => {
        const data = this._fireHotspotData?.find(fire => fire.id === id)
        if (!data) return false
        if (!showAnchored("fire_hotspot", data, { id })) this.showFireHotspotDetail(data)
        return true
      }},
      { prefix: "fire-", skip: [], handler: (id) => {
        const data = this._fireHotspotData?.find(fire => fire.id === id)
        if (!data) return false
        if (!showAnchored("fire_hotspot", data, { id })) this.showFireHotspotDetail(data)
        return true
      }},
      { prefix: "eonet-ring-", skip: [], handler: (id) => {
        const data = this._naturalEventData.find(event => event.id === id)
        if (!data) return false
        if (!showAnchored("natural_event", data, { id })) this.showNaturalEventDetail(data)
        return true
      }},
      { prefix: "eonet-", skip: [], handler: (id) => {
        const data = this._naturalEventData.find(event => event.id === id)
        if (!data) return false
        if (!showAnchored("natural_event", data, { id })) this.showNaturalEventDetail(data)
        return true
      }},
      { prefix: "news-arc-", skip: [], handler: () => {
        const idx = parseInt(entityId.replace(/^news-arc-(?:lbl-|arr-)?/, ""), 10)
        if (Number.isNaN(idx)) return false
        const data = this._newsArcData?.[idx]
        if (data && showAnchored("news_arc", data, { id: idx })) return true
        this.showNewsArcDetail(idx)
        return true
      }},
      // The halo and the threat ring are drawn under the pin and are larger than
      // it, so they intercept a good share of the clicks aimed at it. Both carry
      // the lead event's index, same as the pin, and resolve to the same story.
      { prefix: "news-halo-", skip: [], handler: (id) => showNewsByIndex(id) },
      { prefix: "news-threat-", skip: [], handler: (id) => showNewsByIndex(id) },
      { prefix: "news-", skip: ["news-arc-", "news-halo-", "news-threat-"], handler: (id) => showNewsByIndex(id) },
      { prefix: "outage-ring-", skip: [], handler: (id) => {
        const data = this._outageData?.find(outage => outage.code === id)
        if (!data) return false
        if (!showAnchored("outage", data, { id })) this.showOutageDetail(id)
        return true
      }},
      { prefix: "outage-", skip: [], handler: (id) => {
        const data = this._outageData?.find(outage => outage.code === id)
        if (!data) return false
        if (!showAnchored("outage", data, { id })) this.showOutageDetail(id)
        return true
      }},
      { prefix: "jam-lbl-", skip: [], handler: (id) => {
        const data = (this._gpsJammingData || []).find(entry => `${entry.lat}-${entry.lng}` === id)
        if (!data) return false
        if (!showAnchored("gps_jamming", data, { id })) return this.showGpsJammingDetail(id)
        return true
      }},
      { prefix: "jam-", skip: ["jam-lbl-"], handler: (id) => {
        const data = (this._gpsJammingData || []).find(entry => `${entry.lat}-${entry.lng}` === id)
        if (!data) return false
        if (!showAnchored("gps_jamming", data, { id })) return this.showGpsJammingDetail(id)
        return true
      }},
      { prefix: "cable-", skip: [], handler: () => {
        const props = picked.id.properties
        if (!props) return false
        this._highlightPolyline(picked.id)
        const name = props.cableName?.getValue() || "Unknown cable"
        if (showAnchored("cable", { name, id: props.cableId?.getValue?.() }, { id: props.cableId?.getValue?.() })) return true
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
        const data = (this._portAll || []).find(item => String(item.id) === String(id))
        if (!data) return false
        if (!showAnchored("port", data, { id })) this.showPortDetail(id)
        return true
      }},
      { prefix: "shipping-lane-", skip: ["shipping-label-"], handler: () => {
        const laneId = picked.id.properties?.shippingLaneId?.getValue?.()
        if (!laneId) return false
        this._highlightPolyline(picked.id)
        const data = (this._shippingLaneData || []).find(item => String(item.id) === String(laneId))
        if (!data) return false
        if (!showAnchored("shipping_lane", data, { id: laneId })) this.showShippingLaneDetail(laneId)
        return true
      }},
      { prefix: "shipping-port-", skip: [], handler: () => {
        const laneId = picked.id.properties?.shippingLaneId?.getValue?.()
        if (!laneId) return false
        const data = (this._shippingLaneData || []).find(item => String(item.id) === String(laneId))
        if (!data) return false
        if (!showAnchored("shipping_lane", data, { id: laneId })) this.showShippingLaneDetail(laneId)
        return true
      }},
      { prefix: "shipping-stop-", skip: [], handler: () => {
        const laneId = picked.id.properties?.shippingLaneId?.getValue?.()
        if (!laneId) return false
        const data = (this._shippingLaneData || []).find(item => String(item.id) === String(laneId))
        if (!data) return false
        if (!showAnchored("shipping_lane", data, { id: laneId })) this.showShippingLaneDetail(laneId)
        return true
      }},
      { prefix: "pipeline-", skip: ["pipeline-label-"], handler: () => {
        const props = picked.id.properties
        if (!props) return false
        const pipeId = props.pipelineId?.getValue()
        if (!pipeId) return false
        this._highlightPolyline(picked.id)
        this.showPipelineDetail(pipeId, { picked })
        return true
      }},
      { prefix: "cam-", skip: [], handler: (id) => {
        const webcamId = picked.id.properties?.webcamId?.getValue?.()
        const data = this._webcamEntityMap.get("cam-" + id) ||
          this._webcamData.find(cam => String(cam.id) === id || String(cam.id) === String(webcamId))
        if (!data) return false
        if (!showAnchored("webcam", data, { id })) this.showWebcamDetail(data)
        return true
      }},
      { prefix: "milbase-", skip: [], handler: (id) => {
        const data = this._militaryBaseData?.find(base => String(base.id) === id)
        if (!data) return false
        if (!showAnchored("military_base", data, { id })) this.showMilitaryBaseDetail(data)
        return true
      }},
      { prefix: "airbase-", skip: [], handler: (id) => {
        const data = this._airportDb?.[id]
        if (!data) return false
        if (!showAnchored("airbase", data, { id })) this.showAirbaseDetail(id)
        return true
      }},
      { prefix: "naval-", skip: [], handler: (id) => {
        const data = this._navalShipData.get(id) || this._navalShipData.get(`${id}`)
        if (!data) return false
        if (!showAnchored("naval_vessel", data, { id })) this.showNavalVesselDetail(data)
        return true
      }},
      { prefix: "city-", skip: [], handler: (id) => {
        const cityId = picked.id.properties?.cityId?.getValue?.() || id
        const data = this._citiesData?.find(city => `${city.id}` === `${cityId}`)
        if (!data) return false
        if (!showAnchored("city", data, { id: cityId })) this.showCityDetail?.(data)
        return true
      }},
      { prefix: "rdist-fill-", skip: [], handler: (id) => {
        const data = this._regionalDistrictRecordForEntityId?.(`rdist-fill-${id}`)
        if (!data) return false
        this.showRegionalDistrictDetail?.(data, { picked })
        return true
      }},
      { prefix: "rdist-line-", skip: [], handler: (id) => {
        const data = this._regionalDistrictRecordForEntityId?.(`rdist-line-${id}`)
        if (!data) return false
        this.showRegionalDistrictDetail?.(data, { picked })
        return true
      }},
      { prefix: "rdist-", skip: ["rdist-fill-", "rdist-line-"], handler: (id) => {
        const data = this._regionalDistrictRecordForEntityId?.(`rdist-${id}`)
        if (!data) return false
        this.showRegionalDistrictDetail?.(data, { picked })
        return true
      }},
      { prefix: "radmin-fill-", skip: [], handler: (id) => {
        const data = this._regionalAdminRecordForEntityId?.(`radmin-fill-${id}`)
        if (!data) return false
        this.showRegionalAdminDetail?.(data, { picked })
        return true
      }},
      { prefix: "radmin-line-", skip: [], handler: (id) => {
        const data = this._regionalAdminRecordForEntityId?.(`radmin-line-${id}`)
        if (!data) return false
        this.showRegionalAdminDetail?.(data, { picked })
        return true
      }},
      { prefix: "radmin-", skip: ["radmin-fill-", "radmin-line-"], handler: (id) => {
        const data = this._regionalAdminRecordForEntityId?.(`radmin-${id}`)
        if (!data) return false
        this.showRegionalAdminDetail?.(data, { picked })
        return true
      }},
      { prefix: "rmuni-", skip: [], handler: (id) => {
        const data = this._regionalMunicipalityRecordForEntityId?.(`rmuni-${id}`)
        if (!data) return false
        this.showRegionalMunicipalityDetail?.(data, { picked })
        return true
      }},
      { prefix: "econ-", skip: [], handler: (id) => {
        const data = this._regionalIndicatorMapData?.find(record =>
          `${record.country_code_alpha3 || ""}`.toLowerCase() === `${id}`.toLowerCase()
        )
        if (!data) return false
        this.showRegionalIndicatorDetail?.(data, { picked })
        return true
      }},
      { prefix: "pp-atk-", skip: [], handler: (id) => {
        const data = this._powerPlantData.find(plant => plant.id === parseInt(id, 10))
        if (!data) return false
        if (!showAnchored("power_plant", data, { id })) this.showPowerPlantDetail(data)
        return true
      }},
      { prefix: "pp-", skip: [], handler: (id) => {
        const data = this._powerPlantData.find(plant => plant.id === parseInt(id, 10))
        if (!data) return false
        if (!showAnchored("power_plant", data, { id })) this.showPowerPlantDetail(data)
        return true
      }},
      { prefix: "comsite-", skip: [], handler: (id) => {
        const data = this._commoditySiteData?.find(site => `${site.id}` === `${id}`) ||
          this._commoditySiteAll?.find(site => `${site.id}` === `${id}`)
        if (!data) return false
        if (!showAnchored("commodity_site", data, { id })) this.showCommoditySiteDetail(data)
        return true
      }},
      { prefix: "choke-zone-", skip: [], handler: (id) => {
        const data = this._chokepointData?.find(point => `${point.id}` === `${id}`)
        if (!data) return false
        this.showChokepointDetail(data, { picked })
        return true
      }},
      { prefix: "choke-ships-", skip: [], handler: (id) => {
        const data = this._chokepointData?.find(point => `${point.id}` === `${id}`)
        if (!data) return false
        this.showChokepointDetail(data, { picked })
        return true
      }},
      { prefix: "choke-", skip: [], handler: (id) => {
        const data = this._chokepointData?.find(point => `${point.id}` === `${id}`)
        if (!data) return false
        this.showChokepointDetail(data, { picked })
        return true
      }},
      { prefix: "rw-", skip: [], handler: (id) => {
        this._highlightPolyline(picked.id)
        const data = (this._railwayData || []).find(rw => String(rw.id) === String(id))
        if (!data) return false
        if (!showAnchored("railway", data, { id })) this.showRailwayDetail(id)
        return true
      }},
      { prefix: "surface-poly-", skip: [], handler: (id) => {
        const key = id.replace(/-\d+$/, "")
        const data = this._situationSurfaceByEntityKey?.(key)
        if (!data) return false
        this.showSituationSurfaceDetail(data, { picked })
        return true
      }},
      { prefix: "surface-label-", skip: [], handler: (id) => {
        const data = this._situationSurfaceByEntityKey?.(id)
        if (!data) return false
        this.showSituationSurfaceDetail(data, { picked })
        return true
      }},
      { prefix: "cpulse-arc-lbl-", handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._strikeArcData?.[idx]
        if (!arc) return false
        if (!showAnchored("strike_arc", arc, { id })) this.showStrikeArcDetail(arc)
        return true
      }},
      { prefix: "cpulse-arc-", handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._strikeArcData?.[idx]
        if (!arc) return false
        if (!showAnchored("strike_arc", arc, { id })) this.showStrikeArcDetail(arc)
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
        if (!showAnchored("conflict_event", data, { id })) this.showConflictDetail(data)
        return true
      }},
      { prefix: "conf-", skip: [], handler: (id) => {
        const conflictId = /^\d+$/.test(id) ? parseInt(id, 10) : id
        const data = this._conflictData.find(event => `${event.id}` === `${conflictId}`)
        if (!data) return false
        if (!showAnchored("conflict_event", data, { id })) this.showConflictDetail(data)
        return true
      }},
      { prefix: "traf-lbl-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._attackArcData?.[idx]
        if (arc?.target) {
          const data = this._trafficData?.traffic?.find(item => item.code === arc.target)
          if (data && showAnchored("traffic", data, { id: arc.target })) return true
          this.showTrafficDetail(arc.target)
          return true
        }
        return false
      }},
      { prefix: "traf-atk-", skip: [], handler: (id) => {
        const data = this._trafficData?.traffic?.find(item => item.code === id)
        if (!data) return false
        if (!showAnchored("traffic", data, { id })) this.showTrafficDetail(id)
        return true
      }},
      { prefix: "traf-arc-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._attackArcData?.[idx]
        if (arc?.target) {
          const data = this._trafficData?.traffic?.find(item => item.code === arc.target)
          if (data && showAnchored("traffic", data, { id: arc.target })) return true
          this.showTrafficDetail(arc.target)
          return true
        }
        return false
      }},
      { prefix: "traf-", skip: [], handler: (id) => {
        const data = this._trafficData?.traffic?.find(item => item.code === id)
        if (!data) return false
        if (!showAnchored("traffic", data, { id })) this.showTrafficDetail(id)
        return true
      }},
      { prefix: "notam-lbl-", skip: [], handler: (id) => {
        const data = this._notamData?.find(notam => String(notam.id) === id)
        if (!data) return false
        if (!showAnchored("notam", data, { id })) this.showNotamDetail(data)
        return true
      }},
      { prefix: "notam-", skip: ["notam-warn-", "notam-lbl-"], handler: (id) => {
        const data = this._notamData?.find(notam => String(notam.id) === id)
        if (!data) return false
        if (!showAnchored("notam", data, { id })) this.showNotamDetail(data)
        return true
      }},
      { prefix: "wx-alert-", skip: [], handler: (id) => {
        const data = this._weatherAlerts?.[parseInt(id, 10)]
        if (!data) return false
        if (!showAnchored("weather_alert", data, { id })) this.showWeatherAlertDetail(data)
        return true
      }},
      { prefix: "fin-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._commodityData?.[idx]
        if (!data) return false
        this.showCommodityDetail(data, { picked })
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
