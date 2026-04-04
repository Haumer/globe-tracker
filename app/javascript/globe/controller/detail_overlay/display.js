import { kindLabel } from "globe/controller/detail_overlay/shared"

function anchoredStateById(controller, anchorId) {
  if (anchorId && anchorId !== "active") {
    return (controller._pinnedAnchoredDetails || []).find(state => state.anchorId === anchorId) || null
  }

  return controller._anchoredDetailState || null
}

export function applyDetailOverlayDisplayMethods(GlobeController) {
  GlobeController.prototype._showCompactEntityDetail = function(kind, data, options = {}) {
    const payload = this._buildAnchoredDetailPayload(kind, data, options)
    if (!payload) return false

    if (options.focusSelection) {
      this._focusedSelection = options.focusSelection
      this._renderSelectionTray?.()
    }

    if (this.hasDetailPanelTarget) {
      this.detailPanelTarget.style.display = "none"
    }

    this._showAnchoredDetail(payload)
    return true
  }

  GlobeController.prototype._showAnchoredDetail = function(payload) {
    if (!this.hasAnchorOverlayTarget || !this.hasAnchorPanelTarget || !this.hasAnchorContentTarget) return

    this._anchoredDetailState = {
      ...payload,
      anchorId: "active",
      hiddenSince: null,
      pinned: false,
    }

    const stroke = payload.stroke || payload.accent || "#8bd8ff"
    const strokeWidth = payload.strokeWidth || 2.25
    this.anchorOverlayTarget.style.display = ""
    this.anchorPanelTarget.style.display = ""
    this.anchorPanelTarget.dataset.mode = "anchored"
    this.anchorPanelTarget.dataset.kind = payload.kind || ""
    this.anchorPanelTarget.dataset.pinned = "false"
    this.anchorOverlayTarget.style.setProperty("--anchor-accent", payload.accent || "#8bd8ff")
    this.anchorOverlayTarget.style.setProperty("--anchor-stroke", stroke)
    this.anchorOverlayTarget.style.setProperty("--anchor-border-width", `${strokeWidth}px`)
    this.anchorPanelTarget.style.setProperty("--anchor-accent", payload.accent || "#8bd8ff")
    this.anchorPanelTarget.style.setProperty("--anchor-stroke", stroke)
    this.anchorPanelTarget.style.setProperty("--anchor-border-width", `${strokeWidth}px`)
    this.anchorContentTarget.innerHTML = this._renderAnchoredDetailHtml(this._anchoredDetailState)

    this._refreshAnchoredDetailPosition(true)
    this._renderSelectedContext?.()
    this._requestRender?.()
  }

  GlobeController.prototype._refreshAnchoredDetailContent = function() {
    if (this._anchoredDetailState && this.hasAnchorContentTarget) {
      this.anchorContentTarget.innerHTML = this._renderAnchoredDetailHtml(this._anchoredDetailState)
    }

    ;(this._pinnedAnchoredDetails || []).forEach(state => {
      const content = state?._elements?.content
      if (content) content.innerHTML = this._renderAnchoredDetailHtml(state)
    })

    this._renderSelectedContext?.()
    this._syncRightPanels?.()
  }

  GlobeController.prototype._nextPinnedAnchoredDetailId = function() {
    this._pinnedAnchoredDetailSeq = (this._pinnedAnchoredDetailSeq || 0) + 1
    return `pin-${this._pinnedAnchoredDetailSeq}`
  }

  GlobeController.prototype._findPinnedAnchoredDetailMatch = function(source) {
    const sourceKey = source?.nodeRequest ? `${source.nodeRequest.kind}:${source.nodeRequest.id}` : null

    return (this._pinnedAnchoredDetails || []).find(state => {
      const stateKey = state?.nodeRequest ? `${state.nodeRequest.kind}:${state.nodeRequest.id}` : null
      if (sourceKey && stateKey) return sourceKey === stateKey

      return (
        state?.kind === source?.kind &&
        state?.title === source?.title &&
        `${state?.anchor?.lat || ""}` === `${source?.anchor?.lat || ""}` &&
        `${state?.anchor?.lng || ""}` === `${source?.anchor?.lng || ""}`
      )
    }) || null
  }

  GlobeController.prototype._ensurePinnedAnchoredDetailElements = function(state) {
    if (!state || state._elements || !this.hasAnchorPinsTarget) return state?._elements || null

    const wrapper = document.createElement("div")
    wrapper.className = "anchor-pin"
    wrapper.dataset.anchorId = state.anchorId
    wrapper.innerHTML = `
      <svg class="anchor-leader" aria-hidden="true">
        <path></path>
        <circle style="display:none;"></circle>
      </svg>
      <div class="anchor-panel" role="complementary" aria-label="Pinned item">
        <button class="anchor-close" type="button" data-action="click->globe#unpinAnchoredDetail" data-anchor-id="${this._escapeHtml(state.anchorId)}" aria-label="Unpin focused item">&times;</button>
        <div class="anchor-content"></div>
      </div>
    `

    this.anchorPinsTarget.appendChild(wrapper)

    const panel = wrapper.querySelector(".anchor-panel")
    const content = wrapper.querySelector(".anchor-content")
    const leader = wrapper.querySelector(".anchor-leader")
    const leaderPath = leader?.querySelector("path") || null
    const leaderSocket = leader?.querySelector("circle") || null
    const stroke = state.stroke || state.accent || "#8bd8ff"
    const strokeWidth = state.strokeWidth || 2.25

    panel.dataset.mode = "anchored"
    panel.dataset.kind = state.kind || ""
    panel.dataset.pinned = "true"
    panel.style.setProperty("--anchor-accent", state.accent || "#8bd8ff")
    panel.style.setProperty("--anchor-stroke", stroke)
    panel.style.setProperty("--anchor-border-width", `${strokeWidth}px`)
    content.innerHTML = this._renderAnchoredDetailHtml(state)

    wrapper.style.setProperty("--anchor-accent", state.accent || "#8bd8ff")
    wrapper.style.setProperty("--anchor-stroke", stroke)
    wrapper.style.setProperty("--anchor-border-width", `${strokeWidth}px`)

    state._elements = { wrapper, panel, content, leader, leaderPath, leaderSocket }
    return state._elements
  }

  GlobeController.prototype._removePinnedAnchoredDetailElements = function(state) {
    const wrapper = state?._elements?.wrapper
    if (wrapper?.parentNode) wrapper.parentNode.removeChild(wrapper)
    if (state) delete state._elements
  }

  GlobeController.prototype.pinAnchoredDetail = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()

    const source = anchoredStateById(this, event?.currentTarget?.dataset?.anchorId)
    if (!source || source.pinned) return

    const existing = this._findPinnedAnchoredDetailMatch(source)
    if (existing) {
      this.closeAnchoredDetail()
      this.focusPinnedAnchoredDetail({ currentTarget: { dataset: { anchorId: existing.anchorId } } })
      this._toast?.("Already pinned on map")
      return
    }

    const pinnedState = {
      ...source,
      anchorId: this._nextPinnedAnchoredDetailId(),
      hiddenSince: null,
      pinned: true,
    }

    delete pinnedState._elements
    this._pinnedAnchoredDetails ||= []
    this._pinnedAnchoredDetails.push(pinnedState)
    this._ensurePinnedAnchoredDetailElements(pinnedState)
    this.closeAnchoredDetail()

    if (this.hasAnchorOverlayTarget) this.anchorOverlayTarget.style.display = ""
    this._refreshPinnedAnchoredDetailPositions?.(true)
    this._refreshAnchoredDetailContent()
    this._toast?.("Pinned on map")
  }

  GlobeController.prototype.unpinAnchoredDetail = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()

    const anchorId = event?.currentTarget?.dataset?.anchorId
    if (!anchorId || anchorId === "active") return

    const pinnedStates = this._pinnedAnchoredDetails || []
    const state = pinnedStates.find(item => item.anchorId === anchorId)
    if (!state) return

    this._removePinnedAnchoredDetailElements(state)
    this._pinnedAnchoredDetails = pinnedStates.filter(item => item.anchorId !== anchorId)
    if (this.hasAnchorOverlayTarget && !this._anchoredDetailState && !(this._pinnedAnchoredDetails || []).length) {
      this.anchorOverlayTarget.style.display = "none"
    }
    this._refreshAnchoredDetailContent()
    this._toast?.("Unpinned from map")
  }

  GlobeController.prototype.unpinAllAnchoredDetails = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()

    ;(this._pinnedAnchoredDetails || []).forEach(state => this._removePinnedAnchoredDetailElements(state))
    this._pinnedAnchoredDetails = []
    if (this.hasAnchorOverlayTarget && !this._anchoredDetailState) {
      this.anchorOverlayTarget.style.display = "none"
    }
    this._refreshAnchoredDetailContent()
    this._toast?.("Cleared pinned map cards")
  }

  GlobeController.prototype.focusPinnedAnchoredDetail = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()

    const state = anchoredStateById(this, event?.currentTarget?.dataset?.anchorId)
    if (!state) return

    const lat = Number.parseFloat(state?.anchor?.lat)
    const lng = Number.parseFloat(state?.anchor?.lng)
    if (Number.isFinite(lat) && Number.isFinite(lng)) {
      this._flyToCoordinates?.(lng, lat, state?.focusHeight || 1400000, { duration: 1.0 })
    }

    if (state.nodeRequest && this._focusContextNode) {
      this._focusContextNode(state.nodeRequest, {
        title: state.title,
        summary: state.brief,
      })
    }

    this._showRightPanel?.("context")
  }

  GlobeController.prototype.showAnchoredContext = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()

    const state = anchoredStateById(this, event?.currentTarget?.dataset?.anchorId)
    if (!state) return

    if (state.nodeRequest && this._focusContextNode) {
      this._focusContextNode(state.nodeRequest, {
        title: state.title,
        summary: state.brief,
      })
    }

    this._showRightPanel?.("context")
  }

  GlobeController.prototype.closeAnchoredDetail = function() {
    this._anchoredDetailState = null
    if (this.hasAnchorPanelTarget) {
      this.anchorPanelTarget.style.display = "none"
      this.anchorPanelTarget.style.left = ""
      this.anchorPanelTarget.style.top = ""
      this.anchorPanelTarget.dataset.mode = "anchored"
      this.anchorPanelTarget.dataset.pinned = "false"
      delete this.anchorPanelTarget.dataset.kind
      this.anchorPanelTarget.style.removeProperty("--anchor-accent")
      this.anchorPanelTarget.style.removeProperty("--anchor-stroke")
      this.anchorPanelTarget.style.removeProperty("--anchor-border-width")
    }
    if (this.hasAnchorOverlayTarget) {
      this.anchorOverlayTarget.style.display = (this._pinnedAnchoredDetails || []).length > 0 ? "" : "none"
      this.anchorOverlayTarget.style.removeProperty("--anchor-accent")
      this.anchorOverlayTarget.style.removeProperty("--anchor-stroke")
      this.anchorOverlayTarget.style.removeProperty("--anchor-border-width")
    }
    if (this.hasAnchorLeaderTarget) {
      this.anchorLeaderTarget.style.display = "none"
    }
    if (this.hasAnchorLeaderPathTarget) {
      this.anchorLeaderPathTarget.setAttribute("d", "")
    }
    if (this.hasAnchorLeaderSocketTarget) {
      this.anchorLeaderSocketTarget.style.display = "none"
      this.anchorLeaderSocketTarget.setAttribute("r", "0")
    }
  }

  GlobeController.prototype._renderAnchoredDetailHtml = function(payload) {
    const chipsHtml = (payload.chips || [])
      .filter(Boolean)
      .slice(0, 2)
      .map(item => `<span class="anchor-chip anchor-chip--${this._escapeHtml(item.tone || "neutral")}">${this._escapeHtml(item.label)}</span>`)
      .join("")

    const subtitleHtml = payload.subtitle
      ? `<div class="anchor-subtitle">${this._escapeHtml(payload.subtitle)}</div>`
      : ""

    const briefHtml = payload.brief
      ? `<div class="anchor-brief">${this._escapeHtml(payload.brief)}</div>`
      : ""

    const anchorId = payload.anchorId || "active"
    const actionParts = []

    if (payload.pinned) {
      actionParts.push(`<button class="anchor-action-btn" type="button" data-action="click->globe#unpinAnchoredDetail" data-anchor-id="${this._escapeHtml(anchorId)}">Unpin</button>`)
    } else {
      actionParts.push(`<button class="anchor-action-btn anchor-action-btn--primary" type="button" data-action="click->globe#pinAnchoredDetail" data-anchor-id="${this._escapeHtml(anchorId)}">Pin</button>`)
    }

    if (payload.nodeRequest) {
      actionParts.push(`<button class="anchor-action-btn" type="button" data-action="click->globe#showAnchoredContext" data-anchor-id="${this._escapeHtml(anchorId)}">Rail</button>`)
    }

    if (payload.casePath) {
      actionParts.push(`<a class="anchor-action-btn" href="${this._safeUrl(payload.casePath)}">Case</a>`)
    }

    if (!payload.pinned && (this._pinnedAnchoredDetails || []).length > 0) {
      actionParts.push('<button class="anchor-action-btn" type="button" data-action="click->globe#unpinAllAnchoredDetails">Unpin all</button>')
    }

    const actionsHtml = actionParts.length
      ? `<div class="anchor-actions">${actionParts.join("")}</div>`
      : ""

    return `
      <div class="anchor-head">
        <div class="anchor-chip-row">${chipsHtml}</div>
        ${payload.timeLabel ? `<div class="anchor-time">${this._escapeHtml(payload.timeLabel)}</div>` : ""}
      </div>
      <div class="anchor-title">${this._escapeHtml(payload.title || kindLabel(payload.kind))}</div>
      ${subtitleHtml}
      ${briefHtml}
      ${actionsHtml}
    `
  }
}
