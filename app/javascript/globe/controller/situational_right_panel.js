const PERSISTENT_RIGHT_TABS = new Set(["context", "situations", "news", "insights"])

export function applySituationalRightPanelMethods(GlobeController) {
  GlobeController.prototype._rightPanelTabAvailability = function() {
    return {
      context: !!this._selectedContext || ((this._pinnedAnchoredDetails?.length || 0) > 0),
      entities: this.flightsVisible || this.shipsVisible || this.satellitesVisible,
      news: this.newsVisible && this._newsData?.length > 0,
      threats: !!this._threatsActive,
      situations: this.situationsVisible && ((((this._conflictPulseZones?.length) || 0) > 0) || !!this._conflictPulseSnapshotStatus),
      cameras: this.camerasVisible && (((this._webcamData?.length) || 0) > 0 || !!this._webcamCollectionStatus),
      alerts: this.signedInValue && this._alertData?.length > 0,
      insights: this.insightsVisible && ((((this._insightsData?.length) || 0) > 0) || !!this._insightSnapshotStatus),
    }
  }

  GlobeController.prototype._rightPanelTabVisibility = function(availability = this._rightPanelTabAvailability()) {
    return {
      context: true,
      entities: availability.entities,
      news: true,
      threats: availability.threats,
      situations: true,
      cameras: availability.cameras,
      alerts: availability.alerts,
      insights: true,
    }
  }

  GlobeController.prototype._isRightPanelVisible = function() {
    return this.hasRightPanelTarget && this.rightPanelTarget.style.display !== "none"
  }

  GlobeController.prototype._currentRightPanelTab = function() {
    if (!this.hasRightPanelTarget) return null
    return this.rightPanelTarget.querySelector(".rp-pane--active")?.dataset.rpPane || null
  }

  GlobeController.prototype._setRightTabUpdated = function(tabKey, updated) {
    if (!this.hasRightPanelTarget) return
    const button = this.rightPanelTarget.querySelector(`.rp-tab[data-rp-tab="${tabKey}"]`)
    if (!button) return
    button.dataset.updated = updated ? "true" : "false"
  }

  GlobeController.prototype._syncRightTabButton = function(tabKey, visible, hasContent) {
    if (!this.hasRightPanelTarget) return
    const button = this.rightPanelTarget.querySelector(`.rp-tab[data-rp-tab="${tabKey}"]`)
    if (!button) return

    button.style.display = visible ? "" : "none"
    button.classList.toggle("rp-tab--empty", visible && !hasContent)
    button.dataset.hasContent = hasContent ? "true" : "false"
  }

  GlobeController.prototype._preferredRightPanelTab = function(availability = this._rightPanelTabAvailability(), visibility = this._rightPanelTabVisibility(availability)) {
    const candidates = [
      this._lastRightPanelTab,
      availability.context ? "context" : null,
      "situations",
      availability.news ? "news" : null,
      availability.insights ? "insights" : null,
      availability.entities ? "entities" : null,
      availability.threats ? "threats" : null,
      availability.cameras ? "cameras" : null,
      availability.alerts ? "alerts" : null,
      "news",
      "insights",
      "context",
    ].filter(Boolean)

    return candidates.find(tabKey => visibility[tabKey]) || "situations"
  }

  GlobeController.prototype._rightPanelWidth = function() {
    return this.hasRightPanelTarget ? Math.round(this.rightPanelTarget.getBoundingClientRect().width || 360) : 360
  }

  GlobeController.prototype._syncRightPanels = function() {
    const availability = this._rightPanelTabAvailability()
    const visibility = this._rightPanelTabVisibility(availability)

    this._syncRightTabButton("context", visibility.context, availability.context)
    this._syncRightTabButton("entities", visibility.entities, availability.entities)
    this._syncRightTabButton("news", visibility.news, availability.news)
    this._syncRightTabButton("threats", visibility.threats, availability.threats)
    this._syncRightTabButton("situations", visibility.situations, availability.situations)
    this._syncRightTabButton("cameras", visibility.cameras, availability.cameras)
    this._syncRightTabButton("alerts", visibility.alerts, availability.alerts)
    this._syncRightTabButton("insights", visibility.insights, availability.insights)

    if (this._rightPanelUserClosed) {
      this._syncPanelToggle(false)
      this._repositionDetailStack(12)
      return
    }

    const hasPanelContent = Object.values(availability).some(Boolean)
    const panelVisible = this._isRightPanelVisible()
    if (!panelVisible && !hasPanelContent) {
      this._syncPanelToggle(false)
      this._repositionDetailStack(12)
      return
    }

    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = ""
    this._syncPanelToggle(true)

    const activePaneKey = this._currentRightPanelTab()
    const activeTabHidden = activePaneKey ? !visibility[activePaneKey] : true

    if (activeTabHidden) {
      this._activateRightTab(this._preferredRightPanelTab(availability, visibility))
    }

    this._repositionDetailStack(this._rightPanelWidth())
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
    this._lastRightPanelTab = tabKey
    this.rightPanelTarget.querySelectorAll(".rp-tab").forEach(tab => tab.classList.remove("active"))
    const button = this.rightPanelTarget.querySelector(`.rp-tab[data-rp-tab="${tabKey}"]`)
    this.rightPanelTarget.querySelectorAll(".rp-tab").forEach(tab => tab.setAttribute("aria-selected", "false"))
    if (button) {
      button.classList.add("active")
      button.setAttribute("aria-selected", "true")
      button.dataset.updated = "false"
    }
    this.rightPanelTarget.querySelectorAll(".rp-pane").forEach(pane => pane.classList.remove("rp-pane--active"))
    const pane = this.rightPanelTarget.querySelector(`.rp-pane[data-rp-pane="${tabKey}"]`)
    if (pane) pane.classList.add("rp-pane--active")
  }

  GlobeController.prototype._showRightPanel = function(tabKey) {
    this._rightPanelUserClosed = false
    if (this.hasRightPanelTarget) this.rightPanelTarget.style.display = ""
    this._activateRightTab(tabKey || this._preferredRightPanelTab())
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
