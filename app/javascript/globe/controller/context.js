import { CONTEXT_LAYER_CONFIG, renderContextAction, renderContextItemBody, renderContextSection, renderSelectedContext } from "globe/controller/context_presenters"
import { applyContextNodeMethods } from "globe/controller/context_nodes"
import { applyContextSectionMethods } from "globe/controller/context_sections"

export function applyContextMethods(GlobeController) {
  applyContextNodeMethods(GlobeController)
  applyContextSectionMethods(GlobeController)

  GlobeController.prototype._setSelectedContext = function(context) {
    this._selectedContext = context || null
    this._selectedContextRequestKey = context?.nodeRequest
      ? `${context.nodeRequest.kind}:${context.nodeRequest.id}`
      : null
    if (this._selectedContext?.nodeRequest) {
      this._selectedContext.nodeContextStatus = "loading"
      this._selectedContext.nodeContext = null
      this._loadSelectedContextNode(this._selectedContext.nodeRequest, this._selectedContextRequestKey)
    }
    this._renderSelectedContext()
    if (context) this._showRightPanel("context")
    else if (this._syncRightPanels) this._syncRightPanels()
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
      }
    )
  }
}
