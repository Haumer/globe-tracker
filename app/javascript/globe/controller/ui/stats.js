export function applyUiStatMethods(GlobeController) {
  GlobeController.prototype._updateStats = function() {
    updateStat("stat-flights", this.flightData.size, () => this.flightsVisible && this.flightData.size > 0 && this._markFresh("flights"))
    updateStat("stat-sats", this.satelliteEntities.size)
    updateStat("stat-ships", this.shipData.size, () => this.shipsVisible && this.shipData.size > 0 && this._markFresh("ships"))

    const eventCount = (this.earthquakesVisible ? this._earthquakeData.length : 0) +
      (this.naturalEventsVisible ? this._naturalEventData.length : 0) +
      (this.camerasVisible ? this._webcamData.length : 0) +
      (this.powerPlantsVisible ? this._powerPlantData.length : 0) +
      (this.conflictsVisible ? this._conflictData.length : 0) +
      (this.fireHotspotsVisible ? this._fireHotspotData.length : 0)

    updateStat("stat-events", eventCount, () => {
      if (this.earthquakesVisible && this._earthquakeData.length > 0) this._markFresh("earthquakes")
      if (this.naturalEventsVisible && this._naturalEventData.length > 0) this._markFresh("naturalEvents")
      if (this.camerasVisible && this._webcamData.length > 0) this._markFresh("cameras")
      if (this.conflictsVisible && this._conflictData.length > 0) this._markFresh("conflicts")
    })

    this._syncQuickBar()
    this._updateSatBadge()
  }

  GlobeController.prototype._updateClock = function() {
    const clock = document.getElementById("stat-clock")
    if (!clock) return
    clock.textContent = new Date().toUTCString().slice(17, 22)
  }

  GlobeController.prototype._initTooltips = function() {
    const tip = document.getElementById("gt-tooltip")
    if (!tip) return
    this._tipEl = tip

    const gap = 8
    let currentEl = null

    const show = event => {
      const target = event.target
      if (!target?.closest) return
      const element = target.closest("[data-tip]")
      if (!element || element === currentEl) return
      currentEl = element
      const text = element.getAttribute("data-tip")
      if (!text) return

      tip.textContent = text
      tip.style.left = "-9999px"
      tip.style.top = "-9999px"
      tip.style.opacity = "1"
      tip.style.display = "block"

      const tipW = tip.offsetWidth
      const tipH = tip.offsetHeight
      const pos = element.getAttribute("data-tip-pos") || "above"
      const rect = element.getBoundingClientRect()

      let left
      let top
      if (pos === "right") {
        left = rect.right + gap
        top = rect.top + rect.height / 2 - tipH / 2
      } else if (pos === "below") {
        left = rect.left + rect.width / 2 - tipW / 2
        top = rect.bottom + gap
      } else {
        left = rect.left + rect.width / 2 - tipW / 2
        top = rect.top - tipH - gap
      }

      if (left < 4) left = 4
      if (left + tipW > window.innerWidth - 4) left = window.innerWidth - tipW - 4
      if (top < 4) top = 4

      tip.style.left = `${left}px`
      tip.style.top = `${top}px`
    }

    const hide = event => {
      const target = event.target
      const element = target?.closest ? target.closest("[data-tip]") : null
      if (element !== currentEl) return
      tip.style.opacity = "0"
      currentEl = null
    }

    document.addEventListener("pointerenter", show, true)
    document.addEventListener("pointerleave", hide, true)
    document.addEventListener("mouseover", show)
    document.addEventListener("mouseout", hide)
  }
}

function updateStat(id, count, callback) {
  const element = document.getElementById(id)
  if (!element) return
  element.textContent = count.toLocaleString()
  callback?.()
}
