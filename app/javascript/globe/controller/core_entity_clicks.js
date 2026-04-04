export function applyCoreEntityClickMethods(GlobeController) {
  GlobeController.prototype._handleEntityClick = function(entityId, picked, screenPosition = null) {
    const showCompact = (kind, data, extra = {}) => this._showCompactEntityDetail(kind, data, { picked, screenPosition, ...extra })

    const flightData = this.flightData.get(entityId)
    if (flightData) {
      this.toggleFlightSelection(entityId)
      return showCompact("flight", flightData, {
        id: entityId,
        focusSelection: { type: "flight", id: entityId },
      })
    }

    if (typeof entityId !== "string") return false

    const handlers = [
      { prefix: "tl-flight-", skip: [], handler: (id) => {
        const snap = this._timelineLastKnown?.get(`flight-${id}`)
        if (!snap) return false
        return showCompact("flight", snap, { id, focusSelection: { type: "flight", id } })
      }},
      { prefix: "tl-ship-", skip: [], handler: (id) => {
        const snap = this._timelineLastKnown?.get(`ship-${id}`)
        if (!snap) return false
        return showCompact("ship", snap, { id, focusSelection: { type: "ship", id } })
      }},
      { prefix: "ship-", skip: [], handler: (id) => {
        const data = this.shipData.get(id)
        if (!data) return false
        this.toggleShipSelection(id)
        return showCompact("ship", data, { id, focusSelection: { type: "ship", id } })
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
        return showCompact("satellite", data, {
          id: noradId,
          focusSelection: { type: "sat", id: noradId },
        })
      }},
      { prefix: "train-", skip: [], handler: (id) => {
        const data = this._trainData?.find(train => train.id === id)
        if (!data) return false
        return showCompact("train", data, { id })
      }},
      { prefix: "airport-", skip: [], handler: (id) => {
        const data = this._getAirport?.(id)
        if (!data) return false
        return showCompact("airport", { ...data, icao: id }, { id })
      }},
      { prefix: "eq-", skip: [], handler: (id) => {
        const data = this._earthquakeData.find(quake => quake.id === id)
        if (!data) return false
        return showCompact("earthquake", data, { id })
      }},
      { prefix: "strike-ring-", skip: [], handler: (id) => {
        const data = this._strikeDetections?.find(strike => strike.id === id)
        if (!data) return false
        return showCompact("strike", data, { id })
      }},
      { prefix: "milflt-", skip: [], handler: (id) => {
        const data = this._milFlightData?.find(flight => flight.icao24 === id)
        if (!data) return false
        return showCompact("flight", data, { id, focusSelection: { type: "flight", id } })
      }},
      { prefix: "strike-", skip: [], handler: (id) => {
        const data = this._strikeDetections?.find(strike => strike.id === id)
        if (!data) return false
        return showCompact("strike", data, { id })
      }},
      { prefix: "fire-cluster-ring-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._fireHotspotClusterData?.[idx]
        if (!data) return false
        return showCompact("fire_cluster", data, { id: idx })
      }},
      { prefix: "fire-cluster-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._fireHotspotClusterData?.[idx]
        if (!data) return false
        return showCompact("fire_cluster", data, { id: idx })
      }},
      { prefix: "fire-ring-", skip: [], handler: (id) => {
        const data = this._fireHotspotData?.find(fire => fire.id === id)
        if (!data) return false
        return showCompact("fire_hotspot", data, { id })
      }},
      { prefix: "fire-", skip: [], handler: (id) => {
        const data = this._fireHotspotData?.find(fire => fire.id === id)
        if (!data) return false
        return showCompact("fire_hotspot", data, { id })
      }},
      { prefix: "eonet-ring-", skip: [], handler: (id) => {
        const data = this._naturalEventData.find(event => event.id === id)
        if (!data) return false
        return showCompact("natural_event", data, { id })
      }},
      { prefix: "eonet-", skip: [], handler: (id) => {
        const data = this._naturalEventData.find(event => event.id === id)
        if (!data) return false
        return showCompact("natural_event", data, { id })
      }},
      { prefix: "news-arc-", skip: [], handler: () => {
        const idx = parseInt(entityId.replace(/^news-arc-(?:lbl-|arr-)?/, ""), 10)
        if (Number.isNaN(idx)) return false
        const data = this._newsArcData?.[idx]
        if (!data) return false
        return showCompact("news_arc", data, { id: idx })
      }},
      { prefix: "news-", skip: ["news-arc-"], handler: (id) => {
        const data = this._newsData?.[parseInt(id, 10)]
        if (!data) return false
        if (data.lat != null && data.lng != null) {
          const locKey = `${Number(data.lat).toFixed(0)},${Number(data.lng).toFixed(0)}`
          this._showClusterArcs?.(locKey)
        }
        if (this._buildNewsContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildNewsContext(data))
        }
        return showCompact("news", data, { id })
      }},
      { prefix: "outage-ring-", skip: [], handler: (id) => {
        const data = this._outageData?.find(outage => outage.code === id)
        if (!data) return false
        return showCompact("outage", data, { id })
      }},
      { prefix: "outage-", skip: [], handler: (id) => {
        const data = this._outageData?.find(outage => outage.code === id)
        if (!data) return false
        return showCompact("outage", data, { id })
      }},
      { prefix: "cable-", skip: [], handler: () => {
        const props = picked.id.properties
        if (!props) return false
        this._highlightPolyline(picked.id)
        const name = props.cableName?.getValue() || "Unknown cable"
        return showCompact("cable", {
          name,
          source: "TeleGeography",
        })
      }},
      { prefix: "pipeline-", skip: ["pipeline-label-"], handler: () => {
        const props = picked.id.properties
        if (!props) return false
        const pipeId = props.pipelineId?.getValue()
        if (!pipeId) return false
        this._highlightPolyline(picked.id)
        const data = (this._pipelineData || []).find(pipe => pipe.id === pipeId)
        if (!data) return false
        return showCompact("pipeline", data, { id: pipeId })
      }},
      { prefix: "cam-", skip: [], handler: (id) => {
        const webcamId = picked.id.properties?.webcamId?.getValue?.()
        const data = this._webcamEntityMap.get("cam-" + id) ||
          this._webcamData.find(cam => String(cam.id) === id || String(cam.id) === String(webcamId))
        if (!data) return false
        return showCompact("webcam", data, { id })
      }},
      { prefix: "milbase-", skip: [], handler: (id) => {
        const data = this._militaryBaseData?.find(base => String(base.id) === id)
        if (!data) return false
        return showCompact("military_base", data, { id })
      }},
      { prefix: "airbase-", skip: [], handler: (id) => {
        const data = this._airportDb?.[id]
        if (!data) return false
        return showCompact("airbase", data, { id })
      }},
      { prefix: "naval-", skip: [], handler: (id) => {
        const data = this.shipData.get(id)
        if (!data) return false
        return showCompact("naval_vessel", data, { id })
      }},
      { prefix: "pp-atk-", skip: [], handler: (id) => {
        const data = this._powerPlantData.find(plant => plant.id === parseInt(id, 10))
        if (!data) return false
        return showCompact("power_plant", data, { id })
      }},
      { prefix: "pp-", skip: [], handler: (id) => {
        const data = this._powerPlantData.find(plant => plant.id === parseInt(id, 10))
        if (!data) return false
        return showCompact("power_plant", data, { id })
      }},
      { prefix: "choke-zone-", skip: [], handler: (id) => {
        const data = this._chokepointData?.find(point => `${point.id}` === `${id}`)
        if (!data) return false
        if (this._buildChokepointContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildChokepointContext(data))
        }
        return showCompact("chokepoint", data, { id })
      }},
      { prefix: "choke-ships-", skip: [], handler: (id) => {
        const data = this._chokepointData?.find(point => `${point.id}` === `${id}`)
        if (!data) return false
        if (this._buildChokepointContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildChokepointContext(data))
        }
        return showCompact("chokepoint", data, { id })
      }},
      { prefix: "choke-", skip: [], handler: (id) => {
        const data = this._chokepointData?.find(point => `${point.id}` === `${id}`)
        if (!data) return false
        if (this._buildChokepointContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildChokepointContext(data))
        }
        return showCompact("chokepoint", data, { id })
      }},
      { prefix: "rw-", skip: [], handler: (id) => {
        this._highlightPolyline(picked.id)
        const data = (this._railwayData || []).find(entry => String(entry.id) === String(id))
        if (!data) return false
        return showCompact("railway", data, { id })
      }},
      { prefix: "cpulse-arc-lbl-", handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._strikeArcData?.[idx]
        if (!arc) return false
        return showCompact("strike_arc", arc, { id: idx })
      }},
      { prefix: "cpulse-arc-", handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._strikeArcData?.[idx]
        if (!arc) return false
        return showCompact("strike_arc", arc, { id: idx })
      }},
      { prefix: "cpulse-hex-", handler: (id) => {
        const idx = parseInt(id, 10)
        const cell = this._hexCellData?.[idx]
        if (!cell) return false
        return showCompact("hex_cell", cell, { id: idx })
      }},
      { prefix: "cpulse-strat-ring-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._strategicSituationData?.find(item => `${item.id || item.node_id || item.name}` === key)
        if (!data) return false
        return showCompact("strategic_situation", data, { id: key })
      }},
      { prefix: "cpulse-strat-lbl-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._strategicSituationData?.find(item => `${item.id || item.node_id || item.name}` === key)
        if (!data) return false
        return showCompact("strategic_situation", data, { id: key })
      }},
      { prefix: "cpulse-strat-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._strategicSituationData?.find(item => `${item.id || item.node_id || item.name}` === key)
        if (!data) return false
        return showCompact("strategic_situation", data, { id: key })
      }},
      { prefix: "cpulse-core-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._conflictPulseData?.find(zone => `${zone.cell_key}` === key)
        if (!data) return false
        if (this._buildTheaterContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildTheaterContext(data))
        }
        return showCompact("conflict_pulse", data, { id: key })
      }},
      { prefix: "cpulse-pulse-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._conflictPulseData?.find(zone => `${zone.cell_key}` === key)
        if (!data) return false
        if (this._buildTheaterContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildTheaterContext(data))
        }
        return showCompact("conflict_pulse", data, { id: key })
      }},
      { prefix: "cpulse-ring-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._conflictPulseData?.find(zone => `${zone.cell_key}` === key)
        if (!data) return false
        if (this._buildTheaterContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildTheaterContext(data))
        }
        return showCompact("conflict_pulse", data, { id: key })
      }},
      { prefix: "cpulse-lbl-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._conflictPulseData?.find(zone => `${zone.cell_key}` === key)
        if (!data) return false
        if (this._buildTheaterContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildTheaterContext(data))
        }
        return showCompact("conflict_pulse", data, { id: key })
      }},
      { prefix: "cpulse-", skip: [], handler: (id) => {
        const key = decodeURIComponent(id)
        const data = this._conflictPulseData?.find(zone => `${zone.cell_key}` === key)
        if (!data) return false
        if (this._buildTheaterContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildTheaterContext(data))
        }
        return showCompact("conflict_pulse", data, { id: key })
      }},
      { prefix: "conf-ring-", skip: [], handler: (id) => {
        const data = this._conflictData.find(event => event.id === parseInt(id, 10))
        if (!data) return false
        return showCompact("conflict_event", data, { id })
      }},
      { prefix: "conf-", skip: [], handler: (id) => {
        const data = this._conflictData.find(event => event.id === parseInt(id, 10))
        if (!data) return false
        return showCompact("conflict_event", data, { id })
      }},
      { prefix: "traf-atk-", skip: [], handler: (id) => {
        const data = this._trafficData?.traffic?.find(entry => entry.code === id)
        if (!data) return false
        return showCompact("traffic", data, { id })
      }},
      { prefix: "traf-arc-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const arc = this._attackArcData?.[idx]
        if (arc?.target) {
          const data = this._trafficData?.traffic?.find(entry => entry.code === arc.target)
          if (!data) return false
          return showCompact("traffic", data, { id: arc.target })
        }
        return false
      }},
      { prefix: "traf-", skip: [], handler: (id) => {
        const data = this._trafficData?.traffic?.find(entry => entry.code === id)
        if (!data) return false
        return showCompact("traffic", data, { id })
      }},
      { prefix: "notam-lbl-", skip: [], handler: (id) => {
        const data = this._notamData?.find(notam => String(notam.id) === id)
        if (!data) return false
        return showCompact("notam", data, { id })
      }},
      { prefix: "notam-", skip: ["notam-warn-", "notam-lbl-"], handler: (id) => {
        const data = this._notamData?.find(notam => String(notam.id) === id)
        if (!data) return false
        return showCompact("notam", data, { id })
      }},
      { prefix: "wx-alert-", skip: [], handler: (id) => {
        const data = this._weatherAlerts?.[parseInt(id, 10)]
        if (!data) return false
        return showCompact("weather_alert", data, { id })
      }},
      { prefix: "fin-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._commodityData?.[idx]
        if (!data) return false
        if (this._buildCommodityContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildCommodityContext(data))
        }
        return showCompact("commodity", data, { id: idx })
      }},
      { prefix: "insight-ring-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._insightsData?.[idx]
        if (!data) return false
        if (this._buildInsightContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildInsightContext(data))
        }
        return showCompact("insight", data, { id: idx })
      }},
      { prefix: "insight-", skip: [], handler: (id) => {
        const idx = parseInt(id, 10)
        const data = this._insightsData?.[idx]
        if (!data) return false
        if (this._buildInsightContext && this._setSelectedContext) {
          this._setSelectedContext(this._buildInsightContext(data))
        }
        return showCompact("insight", data, { id: idx })
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
