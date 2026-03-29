export function applySelectionSearchMethods(GlobeController) {
  GlobeController.prototype.onSearchInput = function() {
    clearTimeout(this._searchDebounce)
    const query = this.searchInputTarget.value.trim()

    if (query.length === 0) {
      this.searchResultsTarget.style.display = "none"
      this.searchClearTarget.style.display = "none"
      return
    }

    this.searchClearTarget.style.display = "block"
    this._searchDebounce = setTimeout(() => this._runSearch(query), 150)
  }

  GlobeController.prototype.onSearchKeydown = function(event) {
    if (event.key === "Escape") {
      this.clearSearch()
      return
    }

    const rows = this.searchResultsTarget?.querySelectorAll(".search-result-row")
    if (!rows || rows.length === 0) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this._searchHighlight = Math.min((this._searchHighlight ?? -1) + 1, rows.length - 1)
      this._highlightSearchRow(rows)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this._searchHighlight = Math.max((this._searchHighlight ?? 0) - 1, 0)
      this._highlightSearchRow(rows)
    } else if (event.key === "Enter") {
      event.preventDefault()
      const idx = this._searchHighlight ?? 0
      if (this._searchResults?.[idx]) {
        this._activateSearchResult(idx)
      }
    }
  }

  GlobeController.prototype._highlightSearchRow = function(rows) {
    rows.forEach((r, i) => {
      r.style.background = i === this._searchHighlight ? "rgba(255,255,255,0.08)" : ""
    })
    rows[this._searchHighlight]?.scrollIntoView({ block: "nearest" })
  }

  GlobeController.prototype.clearSearch = function() {
    this.searchInputTarget.value = ""
    this.searchResultsTarget.style.display = "none"
    this.searchClearTarget.style.display = "none"
  }

  const SEARCH_SOURCES = [
    {
      key: "earthquake",
      icon: "fa-house-crack",
      color: "#ff7043",
      getData: (ctrl) => ctrl._earthquakeData || [],
      fields: (item) => [item.title, `m${item.mag}`],
      toResult: (item) => ({
        name: `M${item.mag.toFixed(1)}`,
        detail: item.title,
        lat: item.lat, lng: item.lng, alt: 500000,
        data: item,
      }),
    },
    {
      key: "event",
      getData: (ctrl) => ctrl._naturalEventData || [],
      fields: (item) => [item.title, item.categoryTitle],
      toResult: (item, ctrl) => {
        const catInfo = ctrl.eonetCategoryIcons[item.categoryId] || { icon: "circle-exclamation", color: "#78909c" }
        return {
          icon: `fa-${catInfo.icon}`,
          color: catInfo.color,
          name: item.title.length > 30 ? item.title.substring(0, 28) + "…" : item.title,
          detail: item.categoryTitle,
          lat: item.lat, lng: item.lng, alt: 500000,
        }
      },
    },
    {
      key: "webcam",
      icon: "fa-video",
      color: "#29b6f6",
      getData: (ctrl) => ctrl._webcamData || [],
      fields: (item) => [item.title, item.city],
      toResult: (item) => ({
        name: item.title.length > 30 ? item.title.substring(0, 28) + "…" : item.title,
        detail: [item.city, item.country].filter(Boolean).join(", "),
        lat: item.lat, lng: item.lng, alt: 50000,
      }),
    },
    {
      key: "city",
      getData: (ctrl) => ctrl._citiesData || [],
      fields: (item) => [item.name, item.country],
      toResult: (item) => ({
        icon: item.capital ? "fa-landmark" : "fa-city",
        color: item.capital ? "#ffd54f" : "#e0e0e0",
        name: item.name,
        detail: `${item.country} · ${(item.population / 1e6).toFixed(1)}M`,
        lat: item.lat, lng: item.lng, alt: 200000,
      }),
    },
    {
      key: "power_plant",
      icon: "fa-plug",
      getData: (ctrl) => ctrl._powerPlantAll || [],
      fields: (item) => [item.name, item.fuel, item.country],
      toResult: (item) => ({
        color: item.fuel === "Nuclear" ? "#fdd835" : "#ff9800",
        name: item.name,
        detail: `${item.fuel || "?"} · ${item.capacity ? item.capacity.toLocaleString() + " MW" : "?"}`,
        lat: item.lat, lng: item.lng, alt: 200000,
        data: item,
      }),
    },
    {
      key: "conflict",
      icon: "fa-crosshairs",
      color: "#f44336",
      getData: (ctrl) => ctrl._conflictData || [],
      fields: (item) => [item.name, item.conflict],
      toResult: (item) => ({
        name: item.name || item.conflict,
        detail: item.conflict || "",
        lat: item.lat, lng: item.lng, alt: 300000,
        data: item,
      }),
    },
    {
      key: "fire_hotspot",
      icon: "fa-fire",
      color: "#ff5722",
      getData: (ctrl) => ctrl._fireHotspotData || [],
      fields: (item) => [item.satellite, "fire", "hotspot"],
      toResult: (item) => ({
        name: `Fire ${item.lat.toFixed(2)}°, ${item.lng.toFixed(2)}°`,
        detail: `${item.satellite || "?"} · ${item.frp ? item.frp.toFixed(0) + " MW" : "?"}`,
        lat: item.lat, lng: item.lng, alt: 300000,
        data: item,
      }),
    },
  ]

  GlobeController.prototype._runSearch = async function(query) {
    const q = query.toLowerCase()
    const results = []
    const MAX = 12

    for (const [id, f] of this.flightData) {
      if (results.length >= MAX) break
      const cs = (f.callsign || "").toLowerCase()
      const ic = (f.id || "").toLowerCase()
      const airlineCode = this._extractAirlineCode(f.callsign)
      const airlineName = airlineCode ? this._getAirlineName(airlineCode).toLowerCase() : ""
      if (cs.includes(q) || ic.includes(q) || airlineName.includes(q)) {
        const isMil = this._isMilitaryFlight(f)
        results.push({
          type: "flight",
          icon: isMil ? "fa-jet-fighter" : "fa-plane",
          color: isMil ? "#ef5350" : "#4fc3f7",
          name: f.callsign || f.id,
          detail: airlineCode ? this._getAirlineName(airlineCode) : (f.originCountry || ""),
          lat: f.currentLat,
          lng: f.currentLng,
          alt: f.currentAlt || 200000,
          id,
        })
      }
    }

    for (const [mmsi, s] of this.shipData) {
      if (results.length >= MAX) break
      const name = (s.name || "").toLowerCase()
      const mmsiStr = mmsi.toLowerCase()
      if (name.includes(q) || mmsiStr.includes(q)) {
        results.push({
          type: "ship",
          icon: "fa-ship",
          color: "#26c6da",
          name: s.name || mmsi,
          detail: s.flag || "",
          lat: s.latitude,
          lng: s.longitude,
          alt: 100000,
        })
      }
    }

    const localSatIds = new Set()
    for (const s of this.satelliteData) {
      if (results.length >= MAX) break
      const name = (s.name || "").toLowerCase()
      const norad = String(s.norad_id)
      if (name.includes(q) || norad.includes(q)) {
        localSatIds.add(s.norad_id)
        results.push(this._satSearchResult(s))
      }
    }

    if (q.length >= 2 && results.filter(r => r.type === "satellite").length < 4) {
      try {
        const resp = await fetch(`/api/satellites/search?q=${encodeURIComponent(query)}`)
        if (resp.ok) {
          const serverSats = await resp.json()
          for (const s of serverSats) {
            if (results.length >= MAX) break
            if (localSatIds.has(s.norad_id)) continue
            results.push(this._satSearchResult(s))
          }
        }
      } catch {}
    }

    if (this.airportsVisible) {
      for (const [icao, ap] of Object.entries(this._airportDb)) {
        if (results.length >= MAX) break
        if (icao.toLowerCase().includes(q) || ap.name.toLowerCase().includes(q)) {
          results.push({
            type: "airport",
            icon: "fa-plane-departure",
            color: "#ffd54f",
            name: ap.name,
            detail: icao,
            lat: ap.lat,
            lng: ap.lng,
            alt: 200000,
          })
        }
      }
    }

    for (const source of SEARCH_SOURCES) {
      if (results.length >= MAX) break
      const data = source.getData(this)
      for (const item of data) {
        if (results.length >= MAX) break
        const fieldValues = source.fields(item)
        const matches = fieldValues.some(f => (f || "").toLowerCase().includes(q))
        if (matches) {
          const result = source.toResult(item, this)
          results.push({
            type: source.key,
            icon: result.icon || source.icon,
            color: result.color || source.color,
            ...result,
          })
        }
      }
    }

    this._renderSearchResults(results, query)
  }

  GlobeController.prototype._satSearchResult = function(s) {
    const sat = window.satellite
    let lat = 0, lng = 0, alt = 500000
    if (sat && s.tle_line1 && s.tle_line2) {
      try {
        const now = new Date()
        const satrec = sat.twoline2satrec(s.tle_line1, s.tle_line2)
        const posVel = sat.propagate(satrec, now)
        if (posVel.position) {
          const gmst = sat.gstime(now)
          const posGd = sat.eciToGeodetic(posVel.position, gmst)
          lng = sat.degreesLong(posGd.longitude)
          lat = sat.degreesLat(posGd.latitude)
          alt = posGd.height * 1000 + 500000
        }
      } catch {}
    }
    return {
      type: "satellite",
      icon: "fa-satellite",
      color: this.satCategoryColors?.[s.category] || "#ab47bc",
      name: s.name,
      detail: s.category + (s.country_owner ? ` · ${s.country_owner}` : ""),
      lat, lng, alt,
      data: s,
    }
  }

  GlobeController.prototype._renderSearchResults = function(results, query) {
    if (results.length === 0) {
      this.searchResultsTarget.innerHTML = '<div class="search-empty">No results</div>'
      this.searchResultsTarget.style.display = "block"
      return
    }

    const html = results.map((r, i) => `
      <div class="search-result-row" data-action="click->globe#searchResultClick" data-idx="${i}">
        <span class="search-result-icon" style="color: ${r.color}"><i class="fa-solid ${r.icon}"></i></span>
        <span class="search-result-name">${r.name}</span>
        <span class="search-result-detail">${r.detail}</span>
      </div>
    `).join("")

    this.searchResultsTarget.innerHTML = html
    this.searchResultsTarget.style.display = "block"
    this._searchResults = results
    this._searchHighlight = 0
    this._highlightSearchRow(this.searchResultsTarget.querySelectorAll(".search-result-row"))
  }

  GlobeController.prototype.searchResultClick = function(event) {
    const idx = parseInt(event.currentTarget.dataset.idx)
    this._activateSearchResult(idx)
  }

  GlobeController.prototype._activateSearchResult = function(idx) {
    const r = this._searchResults?.[idx]
    if (!r) return

    const Cesium = window.Cesium
    this.viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(r.lng, r.lat, r.alt),
      duration: 1.5,
    })

    if (r.type === "flight" && r.id) {
      this.toggleFlightSelection(r.id)
      const f = this.flightData.get(r.id)
      if (f) this.showDetail(r.id, f)
    } else if (r.type === "earthquake" && r.data) {
      this.showEarthquakeDetail(r.data)
    } else if (r.type === "power_plant" && r.data) {
      this.showPowerPlantDetail(r.data)
    } else if (r.type === "conflict" && r.data) {
      this.showConflictDetail(r.data)
    } else if (r.type === "fire_hotspot" && r.data) {
      this.showFireHotspotDetail(r.data)
    } else if (r.type === "satellite" && r.data) {
      this.showSatelliteDetail(r.data)
    }

    this.clearSearch()
  }
}
