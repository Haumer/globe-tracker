export function applySelectionAirlineMethods(GlobeController) {
  Object.defineProperty(GlobeController.prototype, "airlineNames", {
    configurable: true,
    get: function() {
      return {
        AAL: "American", AAR: "Asiana", ACA: "Air Canada", AFR: "Air France",
        AIC: "Air India", ALK: "SriLankan", ANA: "All Nippon", ANZ: "Air NZ",
        AUA: "Austrian", AZA: "Alitalia/ITA", BAW: "British Airways",
        BEL: "Brussels", CAL: "China Airlines", CCA: "Air China",
        CES: "China Eastern", CPA: "Cathay Pacific", CSN: "China Southern",
        DAL: "Delta", DLH: "Lufthansa", EIN: "Aer Lingus", ELY: "El Al",
        ETD: "Etihad", ETH: "Ethiopian", EVA: "EVA Air", EWG: "Eurowings",
        EZY: "easyJet", FDX: "FedEx", FIN: "Finnair", GAF: "German AF",
        GIA: "Garuda", HAL: "Hawaiian", IBE: "Iberia", ICE: "Icelandair",
        JAL: "Japan Airlines", JBU: "JetBlue", KAL: "Korean Air",
        KLM: "KLM", LAN: "LATAM", LOT: "LOT Polish", MAS: "Malaysia",
        MEA: "Middle East", MSR: "EgyptAir", NAX: "Norwegian", OMA: "Oman Air",
        PAL: "Philippine", PIA: "PIA", QFA: "Qantas", QTR: "Qatar",
        RAM: "Royal Air Maroc", RJA: "Royal Jordanian", ROT: "TAROM",
        RYR: "Ryanair", SAS: "SAS", SAA: "South African", SIA: "Singapore",
        SKW: "SkyWest", SLK: "Silk Air", SQC: "SQ Cargo", SVA: "Saudia",
        SWA: "Southwest", SWR: "Swiss", TAP: "TAP Portugal", THA: "Thai",
        THY: "Turkish", TUI: "TUI", UAE: "Emirates", UAL: "United",
        UPS: "UPS", VIR: "Virgin Atlantic", VOZ: "Virgin Aus",
        VJC: "VietJet", WZZ: "Wizz Air", AEE: "Aegean",
        ENY: "Envoy Air", RPA: "Republic", ASA: "Alaska",
        NKS: "Spirit", AAY: "Allegiant", FFT: "Frontier",
        AXM: "AirAsia", SBI: "S7 Airlines", AFL: "Aeroflot",
        CSZ: "Shenzhen", CQH: "Spring Airlines", HVN: "Vietnam Airlines",
        AMX: "Aeromexico", AVA: "Avianca", GOL: "Gol", AZU: "Azul",
        CMP: "Copa", TOM: "TUI Airways", SXS: "SunExpress",
        PGT: "Pegasus", OAL: "Olympic", TAR: "Tunisair",
      }
    },
  })

  GlobeController.prototype._extractAirlineCode = function(callsign) {
    if (!callsign || callsign.length < 3) return null
    const code = callsign.substring(0, 3).toUpperCase()
    if (/^[A-Z]{3}$/.test(code)) return code
    return null
  }

  GlobeController.prototype._getAirlineName = function(code) {
    return this.airlineNames[code] || code
  }

  GlobeController.prototype._detectAirlines = function() {
    const counts = new Map()
    for (const [, f] of this.flightData) {
      const code = this._extractAirlineCode(f.callsign)
      if (code) {
        counts.set(code, (counts.get(code) || 0) + 1)
      }
    }
    this._detectedAirlines = counts
    this._updateAirlineChips()
  }

  GlobeController.prototype._updateAirlineChips = function() {
    const sorted = [...this._detectedAirlines.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 20)

    if (sorted.length === 0) {
      if (this.hasAirlineFilterTarget) this.airlineFilterTarget.style.display = "none"
      if (this.hasEntityAirlineBarTarget) this.entityAirlineBarTarget.style.display = "none"
      return
    }

    const html = sorted.map(([code, count]) => {
      const active = this._airlineFilter.has(code) ? " active" : ""
      const name = this._getAirlineName(code)
      return `<span class="airline-chip${active}" data-action="click->globe#toggleAirlineFilter" data-code="${code}" title="${name}">
        ${code}<span class="airline-chip-count">${count}</span>
      </span>`
    }).join("")

    if (this.hasAirlineFilterTarget && this.hasAirlineChipsTarget) {
      this.airlineFilterTarget.style.display = this.flightsVisible ? "" : "none"
      this.airlineChipsTarget.innerHTML = html
    }

    if (this.hasEntityAirlineBarTarget && this.hasEntityAirlineChipsTarget) {
      const entityListVisible = this.entityListPanelTarget.classList.contains("rp-pane--active")
      const activeTab = this.entityListPanelTarget.querySelector(".entity-tab.active")?.dataset.tab
      this.entityAirlineBarTarget.style.display = (entityListVisible && activeTab === "flights") ? "" : "none"
      this.entityAirlineChipsTarget.innerHTML = html
    }
  }

  GlobeController.prototype.toggleAirlineFilter = function(event) {
    const code = event.currentTarget.dataset.code
    if (this._airlineFilter.has(code)) {
      this._airlineFilter.delete(code)
    } else {
      this._airlineFilter.add(code)
    }
    this._updateAirlineChips()
    if (this.entityListPanelTarget.classList.contains("rp-pane--active")) {
      this.renderEntityTab("flights")
    }
    this._savePrefs()
  }

  GlobeController.prototype._flightPassesAirlineFilter = function(f) {
    if (this._airlineFilter.size === 0) return true
    const code = this._extractAirlineCode(f.callsign)
    return code && this._airlineFilter.has(code)
  }
}
