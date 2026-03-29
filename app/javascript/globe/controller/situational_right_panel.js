export function applySituationalRightPanelMethods(GlobeController) {
  GlobeController.prototype._syncRightPanels = function() {
    const hasContext = !!this._selectedContext
    const hasEntities = this.flightsVisible || this.shipsVisible || this.satellitesVisible
    const hasNews = this.newsVisible && this._newsData?.length > 0
    const hasThreats = !!this._threatsActive
    const hasCameras = this.camerasVisible && (((this._webcamData?.length) || 0) > 0 || !!this._webcamCollectionStatus)
    const hasAlerts = this.signedInValue && this._alertData?.length > 0
    const hasInsights = this.insightsVisible && ((((this._insightsData?.length) || 0) > 0) || !!this._insightSnapshotStatus)
    const hasSituations = this.situationsVisible && ((((this._conflictPulseZones?.length) || 0) > 0) || !!this._conflictPulseSnapshotStatus)

    if (this.hasRpTabContextTarget) this.rpTabContextTarget.style.display = hasContext ? "" : "none"
    if (this.hasRpTabEntitiesTarget) this.rpTabEntitiesTarget.style.display = hasEntities ? "" : "none"
    if (this.hasRpTabNewsTarget) this.rpTabNewsTarget.style.display = hasNews ? "" : "none"
    if (this.hasRpTabThreatsTarget) this.rpTabThreatsTarget.style.display = hasThreats ? "" : "none"
    if (this.hasRpTabSituationsTarget) this.rpTabSituationsTarget.style.display = hasSituations ? "" : "none"
    if (this.hasRpTabCamerasTarget) this.rpTabCamerasTarget.style.display = hasCameras ? "" : "none"
    if (this.hasRpTabAlertsTarget) this.rpTabAlertsTarget.style.display = hasAlerts ? "" : "none"
    if (this.hasRpTabInsightsTarget) this.rpTabInsightsTarget.style.display = hasInsights ? "" : "none"

    if (this._rightPanelUserClosed) {
      this._repositionDetailStack(12)
      return
    }

    const anyTabVisible = hasContext || hasEntities || hasNews || hasThreats || hasSituations || hasCameras || hasAlerts || hasInsights
    if (!anyTabVisible) {
      if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = "none"
      this._repositionDetailStack(12)
      return
    }

    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = ""

    const activePane = this.hasRightPanelTarget && this.rightPanelTarget.querySelector(".rp-pane--active")
    const activePaneKey = activePane?.dataset.rpPane
    const activeTabHidden = (activePaneKey === "context" && !hasContext) ||
      (activePaneKey === "entities" && !hasEntities) ||
      (activePaneKey === "news" && !hasNews) ||
      (activePaneKey === "threats" && !hasThreats) ||
      (activePaneKey === "situations" && !hasSituations) ||
      (activePaneKey === "cameras" && !hasCameras) ||
      (activePaneKey === "alerts" && !hasAlerts) ||
      (activePaneKey === "insights" && !hasInsights)

    if (activeTabHidden || !activePaneKey) {
      const firstVisible = hasContext ? "context" : hasSituations ? "situations" : hasEntities ? "entities" : hasNews ? "news" : hasInsights ? "insights" : hasThreats ? "threats" : hasCameras ? "cameras" : "alerts"
      this._activateRightTab(firstVisible)
    }

    this._repositionDetailStack(372)
  }

  GlobeController.prototype._repositionDetailStack = function(panelWidth) {
    if (this._isMobile && this._isMobile()) return
    const detailRight = panelWidth > 12 ? panelWidth + 12 : 12
    const detailStack = document.getElementById("detail-stack")
    if (detailStack) detailStack.style.right = `${detailRight}px`
  }

  GlobeController.prototype.switchRightTab = function(event) {
    const tab = event.currentTarget.dataset.rpTab
    this._activateRightTab(tab)
  }

  GlobeController.prototype._activateRightTab = function(tabKey) {
    if (!this.hasRightPanelTarget) return
    this.rightPanelTarget.querySelectorAll(".rp-tab").forEach(tab => tab.classList.remove("active"))
    const button = this.rightPanelTarget.querySelector(`.rp-tab[data-rp-tab="${tabKey}"]`)
    if (button) button.classList.add("active")
    this.rightPanelTarget.querySelectorAll(".rp-pane").forEach(pane => pane.classList.remove("rp-pane--active"))
    const pane = this.rightPanelTarget.querySelector(`.rp-pane[data-rp-pane="${tabKey}"]`)
    if (pane) pane.classList.add("rp-pane--active")
  }

  GlobeController.prototype._showRightPanel = function(tabKey) {
    this._rightPanelUserClosed = false
    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = ""
    this._activateRightTab(tabKey)
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
