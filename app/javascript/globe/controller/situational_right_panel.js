export function applySituationalRightPanelMethods(GlobeController) {
  function availabilityFor(tabKey, availability) {
    if (tabKey === "local-profile") return availability.localProfile
    if (tabKey === "localProfile") return availability.localProfile
    return availability[tabKey]
  }

  GlobeController.prototype._rightPanelHasContext = function() {
    return !!this._selectedContext || ((this._pinnedAnchoredDetails?.length || 0) > 0)
  }

  GlobeController.prototype._rightPanelTabAvailability = function() {
    return {
      context: this._rightPanelHasContext(),
      localProfile: this._hasActiveLocalProfile?.() || false,
    }
  }

  GlobeController.prototype._rightPanelTabVisibility = function(availability = this._rightPanelTabAvailability()) {
    return {
      context: true,
    }
  }

  GlobeController.prototype._isRightPanelVisible = function() {
    return this.hasRightPanelTarget && this.rightPanelTarget.style.display !== "none"
  }

  GlobeController.prototype._currentRightPanelTab = function() {
    if (!this._isRightPanelVisible()) return null
    const pane = this.hasRightPanelTarget ? this.rightPanelTarget.querySelector(".rp-pane.rp-pane--active") : null
    return pane?.dataset?.rpPane || null
  }

  GlobeController.prototype._setRightTabUpdated = function() {}

  GlobeController.prototype._syncRightTabButton = function() {}

  GlobeController.prototype._preferredRightPanelTab = function() {
    if (this._rightPanelHasContext()) return "context"
    if (this._hasActiveLocalProfile?.()) return "local-profile"
    return "context"
  }

  GlobeController.prototype._rightPanelWidth = function() {
    return this.hasRightPanelTarget ? Math.round(this.rightPanelTarget.getBoundingClientRect().width || 360) : 360
  }

  GlobeController.prototype._syncRightPanels = function() {
    const availability = this._rightPanelTabAvailability()
    const panelVisible = this._isRightPanelVisible()

    if (this._rightPanelUserClosed) {
      this._syncPanelToggle(false)
      this._repositionDetailStack(12)
      return
    }

    if (this._deferContextRail && !panelVisible) {
      this._syncPanelToggle(false)
      this._repositionDetailStack(12)
      return
    }

    const hasPanelContent = !!availability.context || !!availability.localProfile
    if (!panelVisible && !hasPanelContent) {
      this._syncPanelToggle(false)
      this._repositionDetailStack(12)
      return
    }

    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = ""
    this._syncPanelToggle(true)
    const nextTab = availabilityFor(this._lastRightPanelTab, availability) ? this._lastRightPanelTab : this._preferredRightPanelTab()
    this._activateRightTab(nextTab)
    this._repositionDetailStack(this._rightPanelWidth())
  }

  GlobeController.prototype._repositionDetailStack = function(panelWidth) {
    if (this._isMobile && this._isMobile()) return
    const detailRight = panelWidth > 12 ? panelWidth + 12 : 12
    const detailStack = document.getElementById("detail-stack")
    if (detailStack) detailStack.style.right = `${detailRight}px`
  }

  GlobeController.prototype.switchRightTab = function(event) {
    event?.preventDefault?.()
    this._activateRightTab(this._preferredRightPanelTab())
  }

  GlobeController.prototype._activateRightTab = function(tabKey) {
    if (!this.hasRightPanelTarget) return
    const availability = this._rightPanelTabAvailability()
    let nextTab = tabKey || this._preferredRightPanelTab()
    if (nextTab === "localProfile") nextTab = "local-profile"
    if (nextTab === "local-profile" && !availability.localProfile) nextTab = availability.context ? "context" : null
    if (nextTab === "context" && !availability.context) nextTab = availability.localProfile ? "local-profile" : null
    if (!nextTab) return

    this._lastRightPanelTab = nextTab
    this.rightPanelTarget.querySelectorAll(".rp-pane").forEach(pane => pane.classList.remove("rp-pane--active"))
    const pane = this.rightPanelTarget.querySelector(`.rp-pane[data-rp-pane="${nextTab}"]`)
    if (pane) pane.classList.add("rp-pane--active")
    if (this.hasRightPanelTitleTarget) {
      this.rightPanelTitleTarget.textContent = nextTab === "local-profile" ? "LOCAL PROFILE" : "LIVE CONTEXT"
    }
  }

  GlobeController.prototype._showRightPanel = function(tabKey) {
    const availability = this._rightPanelTabAvailability()
    const wantsLocalProfile = tabKey === "localProfile" || tabKey === "local-profile"

    if (!availability.context && !availability.localProfile) {
      this._syncRightPanels()
      return
    }

    this._deferContextRail = false
    this._rightPanelUserClosed = false
    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = ""
    this._activateRightTab(wantsLocalProfile ? "local-profile" : tabKey)
    this._syncRightPanels()
    this._syncPanelToggle(true)
  }

  GlobeController.prototype.closeRightPanel = function() {
    this._deferContextRail = false
    this._rightPanelUserClosed = true
    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = "none"
    this._repositionDetailStack(12)
    this._syncPanelToggle(false)
    this._savePrefs()
  }

  GlobeController.prototype._syncPanelToggle = function(active) {
    const toggle = this.element?.querySelector(".stat-panel-toggle")
    if (toggle) toggle.classList.toggle("active", active)
  }

  GlobeController.prototype.focusCamFeedItem = function(event) {
    if (event) event.stopPropagation()
    const idx = parseInt(event.currentTarget.dataset.camIdx, 10)
    const cam = this._webcamData[idx]
    if (!cam) return
    this.showWebcamDetail(cam)
  }

  GlobeController.prototype.openCamStream = function(event) {
    event.preventDefault()
    event.stopPropagation()

    const idx = parseInt(event.currentTarget.dataset.camIdx, 10)
    const cam = this._webcamData[idx]
    if (!cam) return

    const watchUrl = this._cameraWatchUrl(cam)
    if (watchUrl) window.open(watchUrl, "_blank", "noopener")
  }
}
