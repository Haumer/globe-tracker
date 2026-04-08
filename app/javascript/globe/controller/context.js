import { CONTEXT_LAYER_CONFIG, renderContextAction, renderContextItemBody, renderContextSection, renderSelectedContext } from "globe/controller/context_presenters"
import { applyContextNodeMethods } from "globe/controller/context_nodes"
import { applyContextSectionMethods } from "globe/controller/context_sections"

export function applyContextMethods(GlobeController) {
  applyContextNodeMethods(GlobeController)
  applyContextSectionMethods(GlobeController)

  GlobeController.prototype._setSelectedContext = function(context, options = {}) {
    if (this._theaterBriefPollTimer) {
      clearTimeout(this._theaterBriefPollTimer)
      this._theaterBriefPollTimer = null
    }

    this._selectedContext = context || null
    this._selectedContextRequestKey = context?.nodeRequest
      ? `${context.nodeRequest.kind}:${context.nodeRequest.id}`
      : null
    if (this._selectedContext?.nodeRequest) {
      this._selectedContext.nodeContextStatus = "loading"
      this._selectedContext.nodeContext = null
      this._loadSelectedContextNode(this._selectedContext.nodeRequest, this._selectedContextRequestKey)
    }
    if (this._selectedContext?.kind === "theater") {
      this._loadSelectedTheaterBrief(this._selectedContext)
    }
    this._renderSelectedContext()
    if (!context) {
      this._deferContextRail = false
      this._setRightTabUpdated?.("context", false)
      if (this._syncRightPanels) this._syncRightPanels()
      return
    }

    const panelVisible = this._isRightPanelVisible?.()
    const activeTab = this._currentRightPanelTab?.()
    const shouldOpenRightPanel = options.openRightPanel === true || context?.autoOpenRightPanel === true

    if (shouldOpenRightPanel) {
      this._deferContextRail = false
      this._rightPanelUserClosed = false
      this._showRightPanel("context")
      return
    }

    this._deferContextRail = panelVisible !== true

    this._setRightTabUpdated?.("context", activeTab !== "context")
    if (this._syncRightPanels) this._syncRightPanels()
  }

  GlobeController.prototype._loadSelectedContextNode = async function(nodeRequest, requestKey) {
    try {
      const params = new URLSearchParams({
        kind: nodeRequest.kind,
        id: nodeRequest.id,
      })
      const resp = await fetch(`/api/node_context?${params.toString()}`)
      if (!this._selectedContext || this._selectedContextRequestKey !== requestKey) return

      if (!resp.ok) {
        this._selectedContext.nodeContextStatus = "error"
        this._renderSelectedContext()
        return
      }

      this._selectedContext.nodeContext = await resp.json()
      this._selectedContext.nodeContextStatus = "ready"
      this._renderSelectedContext()
    } catch (_error) {
      if (!this._selectedContext || this._selectedContextRequestKey !== requestKey) return
      this._selectedContext.nodeContextStatus = "error"
      this._renderSelectedContext()
    }
  }

  GlobeController.prototype._renderSelectedContext = function() {
    if (!this.hasContextContentTarget) return

    this.contextContentTarget.innerHTML = renderSelectedContext(this, this._selectedContext)
  }

  GlobeController.prototype._theaterBriefCacheKey = function(context) {
    const theater = context?.theaterIdentifier || context?.title
    if (!theater) return null
    const zone = context?.zoneData || {}
    const signature = [
      context?.zoneKey || "",
      zone.pulse_score || 0,
      zone.escalation_trend || "",
      zone.count_24h || 0,
      zone.source_count || 0,
      zone.story_count || 0,
      zone.spike_ratio || 0,
      zone.detected_at || "",
    ].join("::")
    return `${theater}::${signature}`
  }

  GlobeController.prototype._applyTheaterBriefPayload = function(context, payload = {}) {
    if (!context || context.kind !== "theater") return

    context.theaterBriefStatus = payload.status || "error"
    context.theaterBrief = payload.brief || null
    context.theaterBriefGeneratedAt = payload.generated_at || null
    context.theaterBriefProvider = payload.provider || null
    context.theaterBriefError = payload.error || null
    context.theaterBriefScopeKey = payload.scope_key || null
    context.theaterBriefSourceContext = payload.source_context || null
    if (this._hydrateTheaterContextSections) this._hydrateTheaterContextSections(context)
  }

  GlobeController.prototype._scheduleTheaterBriefRetry = function(context, cacheKey) {
    if (this._theaterBriefPollTimer) clearTimeout(this._theaterBriefPollTimer)
    this._theaterBriefPollTimer = setTimeout(() => {
      if (this._selectedContext !== context) return
      if (this._theaterBriefCacheKey(context) !== cacheKey) return
      this._theaterBriefCache?.delete(cacheKey)
      this._loadSelectedTheaterBrief(context)
    }, 4000)
  }

  GlobeController.prototype._loadSelectedTheaterBrief = async function(context) {
    const cacheKey = this._theaterBriefCacheKey(context)
    if (!cacheKey || !context?.theaterIdentifier) return

    const cached = this._theaterBriefCache?.get(cacheKey)
    if (cached) {
      this._applyTheaterBriefPayload(context, cached)
      if (this._selectedContext === context) this._renderSelectedContext()
      if (cached.status === "pending") this._scheduleTheaterBriefRetry(context, cacheKey)
      return
    }

    context.theaterBriefStatus = "loading"
    if (this._hydrateTheaterContextSections) this._hydrateTheaterContextSections(context)

    try {
      const params = new URLSearchParams({ theater: context.theaterIdentifier })
      if (context.zoneKey) params.set("cell_key", context.zoneKey)

      const resp = await fetch(`/api/theater_brief?${params.toString()}`)
      const payload = resp.ok ? await resp.json() : { status: "error", error: `HTTP ${resp.status}` }

      this._theaterBriefCache?.set(cacheKey, payload)
      if (this._selectedContext !== context) return

      this._applyTheaterBriefPayload(context, payload)
      this._renderSelectedContext()

      if (payload.status === "pending") this._scheduleTheaterBriefRetry(context, cacheKey)
    } catch (_error) {
      if (this._selectedContext !== context) return
      this._applyTheaterBriefPayload(context, { status: "error", error: "Brief request failed" })
      this._renderSelectedContext()
    }
  }

  GlobeController.prototype._renderContextSection = function(section) {
    return renderContextSection(this, section)
  }

  GlobeController.prototype._renderContextItemBody = function(item) {
    return renderContextItemBody(this, item)
  }

  GlobeController.prototype._renderContextAction = function(action) {
    return renderContextAction(this, action)
  }

  GlobeController.prototype.focusContextLocation = function(event) {
    const lat = parseFloat(event.currentTarget.dataset.lat)
    const lng = parseFloat(event.currentTarget.dataset.lng)
    const height = parseFloat(event.currentTarget.dataset.height || "500000")
    if (isNaN(lat) || isNaN(lng)) return

    this._flyToCoordinates?.(lng, lat, height, { duration: 1.2 })
  }

  GlobeController.prototype.openContextCamera = function(event) {
    event.preventDefault()
    event.stopPropagation()

    const cameraId = event.currentTarget.dataset.cameraId
    if (!cameraId) return

    const camera = (this._webcamData || []).find(item => `${item.id}` === `${cameraId}`)
    if (!camera) return

    this.showWebcamDetail(camera)
  }

  GlobeController.prototype.openContextLayer = function(event) {
    event.preventDefault()
    event.stopPropagation()

    const layerKey = event.currentTarget.dataset.layerKey
    const tabKey = event.currentTarget.dataset.rpTab

    if (layerKey) this._ensureContextLayerVisible(layerKey)
    if (tabKey) this._showRightPanel(tabKey)

    const lat = event.currentTarget.dataset.lat
    const lng = event.currentTarget.dataset.lng
    if (lat != null && lng != null) {
      this.focusContextLocation({
        currentTarget: {
          dataset: {
            lat,
            lng,
            height: event.currentTarget.dataset.height || "500000",
          },
        },
      })
    }
  }

  GlobeController.prototype._ensureContextLayerVisible = function(layerKey) {
    const layerConfig = CONTEXT_LAYER_CONFIG[layerKey]

    if (!layerConfig) return
    if (this[layerConfig.visibleProp]) return
    if (!this[layerConfig.hasTargetProp] || !this[layerConfig.targetProp]) return

    this[layerConfig.targetProp].checked = true
    if (typeof this[layerConfig.method] === "function") this[layerConfig.method]()
  }

  GlobeController.prototype.selectContextNode = function(event) {
    const kind = event.currentTarget.dataset.kind
    const id = event.currentTarget.dataset.id
    if (!kind || !id) return

    this._focusContextNode(
      { kind, id },
      {
        title: event.currentTarget.dataset.title,
        summary: event.currentTarget.dataset.summary,
      },
      {
        openRightPanel: this._isRightPanelVisible?.() === true,
      }
    )
  }
}
