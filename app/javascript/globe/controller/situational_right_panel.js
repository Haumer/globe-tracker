export function applySituationalRightPanelMethods(GlobeController) {
  GlobeController.prototype._rightPanelHasContext = function() {
    return !!this._selectedContext || ((this._pinnedAnchoredDetails?.length || 0) > 0)
  }

  GlobeController.prototype._rightPanelTabAvailability = function() {
    return {
      context: this._rightPanelHasContext(),
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
    return this._isRightPanelVisible() ? "context" : null
  }

  GlobeController.prototype._setRightTabUpdated = function() {}

  GlobeController.prototype._syncRightTabButton = function() {}

  GlobeController.prototype._preferredRightPanelTab = function() {
    return "context"
  }

  GlobeController.prototype._rightPanelWidth = function() {
    return this.hasRightPanelTarget ? Math.round(this.rightPanelTarget.getBoundingClientRect().width || 360) : 360
  }

  GlobeController.prototype._syncRightPanels = function() {
    const availability = this._rightPanelTabAvailability()

    if (this._rightPanelUserClosed) {
      this._syncPanelToggle(false)
      this._repositionDetailStack(12)
      return
    }

    const hasPanelContent = !!availability.context
    const panelVisible = this._isRightPanelVisible()
    if (!panelVisible && !hasPanelContent) {
      this._syncPanelToggle(false)
      this._repositionDetailStack(12)
      return
    }

    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = ""
    this._syncPanelToggle(true)
    this._activateRightTab("context")
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
    this._activateRightTab("context")
  }

  GlobeController.prototype._activateRightTab = function(tabKey) {
    if (!this.hasRightPanelTarget) return
    this._lastRightPanelTab = "context"
    this.rightPanelTarget.querySelectorAll(".rp-pane").forEach(pane => pane.classList.remove("rp-pane--active"))
    const pane = this.rightPanelTarget.querySelector(`.rp-pane[data-rp-pane="context"]`)
    if (pane) pane.classList.add("rp-pane--active")
  }

  GlobeController.prototype._showRightPanel = function(tabKey) {
    if (!this._rightPanelHasContext()) {
      this._syncRightPanels()
      return
    }

    this._rightPanelUserClosed = false
    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = ""
    this._activateRightTab("context")
    this._syncRightPanels()
    this._syncPanelToggle(true)
  }

  GlobeController.prototype.closeRightPanel = function() {
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
