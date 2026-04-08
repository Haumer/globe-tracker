import { kindLabel } from "globe/controller/detail_overlay/shared"

function anchoredStateById(controller, anchorId) {
  if (anchorId && anchorId !== "active") {
    return (controller._pinnedAnchoredDetails || []).find(state => state.anchorId === anchorId) || null
  }

  return controller._anchoredDetailState || null
}

function shouldPreserveAnchoredHtml(state) {
  return !!state?._strikeMediaPersistent
}

function nodeRequestKey(nodeRequest) {
  if (!nodeRequest?.kind || !nodeRequest?.id) return null
  return `${nodeRequest.kind}:${nodeRequest.id}`
}

export function applyDetailOverlayDisplayMethods(GlobeController) {
  GlobeController.prototype._anchoredDetailNow = function() {
    const highResNow = window.performance?.now?.()
    if (Number.isFinite(highResNow)) return highResNow

    const coarseNow = Date.now()
    return Number.isFinite(coarseNow) ? coarseNow : 0
  }

  GlobeController.prototype._anchoredDetailDismissGuardMs = function(kind) {
    return kind ? 420 : 0
  }

  GlobeController.prototype._anchoredDetailInteractivityWarmMs = function(kind) {
    return kind ? 180 : 0
  }

  GlobeController.prototype._resetAnchoredDetailInteractivity = function() {
    this._anchoredDetailInteractionToken = (this._anchoredDetailInteractionToken || 0) + 1
    if (!this.hasAnchorPanelTarget) return

    this.anchorPanelTarget.style.removeProperty("pointer-events")
    delete this.anchorPanelTarget.dataset.warming
  }

  GlobeController.prototype._warmAnchoredDetailInteractivity = function(delayMs) {
    if (!this.hasAnchorPanelTarget) return

    this._resetAnchoredDetailInteractivity()
    if (!(delayMs > 0)) return

    const token = this._anchoredDetailInteractionToken
    this.anchorPanelTarget.style.pointerEvents = "none"
    this.anchorPanelTarget.dataset.warming = "true"

    setTimeout(() => {
      if (token !== this._anchoredDetailInteractionToken) return
      if (!this._anchoredDetailState) return
      this.anchorPanelTarget.style.removeProperty("pointer-events")
      delete this.anchorPanelTarget.dataset.warming
    }, delayMs)
  }

  GlobeController.prototype._anchoredDetailDismissGuardActive = function(options = {}) {
    if (options.force || options.explicit) return false

    const dismissGuardUntil = this._anchoredDetailState?.dismissGuardUntil
    return Number.isFinite(dismissGuardUntil) && this._anchoredDetailNow() < dismissGuardUntil
  }

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

    const dismissGuardMs = this._anchoredDetailDismissGuardMs(payload.kind)
    const interactivityWarmMs = this._anchoredDetailInteractivityWarmMs(payload.kind)
    const mobile = window.innerWidth <= 960
    this._anchoredDetailState = {
      ...payload,
      anchorId: "active",
      dismissGuardUntil: this._anchoredDetailNow() + dismissGuardMs,
      pinned: false,
    }

    const stroke = payload.stroke || payload.accent || "#8bd8ff"
    const strokeWidth = payload.strokeWidth || 2.25
    this.anchorOverlayTarget.style.display = ""
    this.anchorPanelTarget.style.display = "none"
    this.anchorPanelTarget.dataset.mode = "anchored"
    this.anchorPanelTarget.dataset.kind = payload.kind || ""
    this.anchorPanelTarget.dataset.pinned = "false"
    this.anchorOverlayTarget.style.setProperty("--anchor-accent", payload.accent || "#8bd8ff")
    this.anchorOverlayTarget.style.setProperty("--anchor-stroke", stroke)
    this.anchorOverlayTarget.style.setProperty("--anchor-border-width", `${strokeWidth}px`)
    this.anchorPanelTarget.style.setProperty("--anchor-accent", payload.accent || "#8bd8ff")
    this.anchorPanelTarget.style.setProperty("--anchor-stroke", stroke)
    this.anchorPanelTarget.style.setProperty("--anchor-border-width", `${strokeWidth}px`)
    this._applyAnchoredDetailScale?.(this.anchorPanelTarget, this._anchoredDetailState, { mobile })
    this._warmAnchoredDetailInteractivity(interactivityWarmMs)
    this.anchorContentTarget.innerHTML = this._renderAnchoredDetailHtml(this._anchoredDetailState)

    this._refreshAnchoredDetailPosition(true)
    this._renderSelectedContext?.()
    this._requestRender?.()

  }

  GlobeController.prototype._refreshAnchoredDetailContent = function() {
    if (this._anchoredDetailState && this.hasAnchorContentTarget) {
      if (!shouldPreserveAnchoredHtml(this._anchoredDetailState)) {
        this.anchorContentTarget.innerHTML = this._renderAnchoredDetailHtml(this._anchoredDetailState)
      }
    }

    ;(this._pinnedAnchoredDetails || []).forEach(state => {
      const content = state?._elements?.content
      if (content && !shouldPreserveAnchoredHtml(state)) content.innerHTML = this._renderAnchoredDetailHtml(state)
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
      this.closeAnchoredDetail({ force: true })
      this.focusPinnedAnchoredDetail({ currentTarget: { dataset: { anchorId: existing.anchorId } } })
      this._toast?.("Already pinned on map")
      return
    }

    const pinnedState = {
      ...source,
      anchorId: this._nextPinnedAnchoredDetailId(),
      pinned: true,
    }

    delete pinnedState._elements
    this._pinnedAnchoredDetails ||= []
    this._pinnedAnchoredDetails.push(pinnedState)
    this._ensurePinnedAnchoredDetailElements(pinnedState)
    this.closeAnchoredDetail({ force: true })

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

    const anchoredNodeKey = nodeRequestKey(state.nodeRequest)
    const selectedNodeKey = nodeRequestKey(this._selectedContext?.nodeRequest)

    if (anchoredNodeKey && anchoredNodeKey === selectedNodeKey) {
      this._showRightPanel?.("context")
      return
    }

    if (state.nodeRequest && this._focusContextNode) {
      this._focusContextNode(state.nodeRequest, {
        title: state.title,
        summary: state.brief,
      }, {
        openRightPanel: true,
      })
    }

    this._showRightPanel?.("context")
  }

  GlobeController.prototype.showAnchoredContext = function(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()

    const state = anchoredStateById(this, event?.currentTarget?.dataset?.anchorId)
    if (!state) return

    const anchoredNodeKey = nodeRequestKey(state.nodeRequest)
    const selectedNodeKey = nodeRequestKey(this._selectedContext?.nodeRequest)

    if (anchoredNodeKey && anchoredNodeKey === selectedNodeKey) {
      this._showRightPanel?.("context")
      return
    }

    if (state.nodeRequest && this._focusContextNode) {
      this._focusContextNode(state.nodeRequest, {
        title: state.title,
        summary: state.brief,
      }, {
        openRightPanel: true,
      })
    }

    this._showRightPanel?.("context")
  }

  GlobeController.prototype.closeAnchoredDetail = function(options = {}) {
    if (this._anchoredDetailDismissGuardActive(options)) return false

    this._anchoredDetailState = null
    this._resetAnchoredDetailInteractivity()
    if (this.hasAnchorPanelTarget) {
      this.anchorPanelTarget.style.display = "none"
      this.anchorPanelTarget.style.left = ""
      this.anchorPanelTarget.style.top = ""
      this.anchorPanelTarget.style.removeProperty("--anchor-panel-scale")
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

    return true
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
      actionParts.push(`<button class="anchor-action-btn" type="button" data-action="click->globe#showAnchoredContext" data-anchor-id="${this._escapeHtml(anchorId)}">Context</button>`)
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

    let mediaExtraHtml = ""
    if (payload.kind === "geoconfirmed" && payload._gcData) {
      const gc = payload._gcData
      const srcUrls = gc.sourceUrls || []
      const geoUrls = gc.geoUrls || []
      const xUrl = srcUrls.find(u => u.includes("x.com/") || u.includes("twitter.com/"))
      const otherUrls = srcUrls.filter(u => u !== xUrl)
      const [primaryGeoUrl, ...extraGeoUrls] = geoUrls

      const linkHtml = (url) => {
        const label = this._urlLabel?.(url) || url.substring(0, 30)
        const icon = this._urlIcon?.(url) || "fa-solid fa-link"
        return `<a href="${this._safeUrl(url)}" target="_blank" rel="noopener" class="anchor-gc-link"><i class="${icon}"></i><span>${this._escapeHtml(label)}</span></a>`
      }

      const primaryActions = []
      if (xUrl) {
        primaryActions.push(`<a href="${this._safeUrl(xUrl)}" target="_blank" rel="noopener" class="anchor-gc-link anchor-gc-link--primary"><i class="fa-brands fa-x-twitter"></i><span>Open on X</span></a>`)
      }
      if (primaryGeoUrl) {
        const label = this._urlLabel?.(primaryGeoUrl) || "Map"
        primaryActions.push(`<a href="${this._safeUrl(primaryGeoUrl)}" target="_blank" rel="noopener" class="anchor-gc-link anchor-gc-link--geo anchor-gc-link--action"><i class="fa-solid fa-map-pin"></i><span>${this._escapeHtml(label)}</span></a>`)
      }

      const primaryActionsHtml = primaryActions.length
        ? `<div class="anchor-gc-links anchor-gc-links--row">${primaryActions.join("")}</div>`
        : ""
      const srcHtml = otherUrls.length ? `<div class="anchor-gc-links">${otherUrls.slice(0, 4).map(linkHtml).join("")}</div>` : ""
      const geoHtml = extraGeoUrls.length ? `<div class="anchor-gc-links anchor-gc-links--geo">${extraGeoUrls.slice(0, 2).map(u => {
        const label = this._urlLabel?.(u) || "Map"
        return `<a href="${this._safeUrl(u)}" target="_blank" rel="noopener" class="anchor-gc-link anchor-gc-link--geo"><i class="fa-solid fa-map-pin"></i><span>${this._escapeHtml(label)}</span></a>`
      }).join("")}</div>` : ""

      mediaExtraHtml = `${primaryActionsHtml}${srcHtml}${geoHtml}`
    }

    if (payload.kind === "strike" && payload._strikeData) {
      const strike = payload._strikeData
      const gcMatch = strike.gcMatch || null
      const sourceUrls = [
        ...(Array.isArray(gcMatch?.source_urls) ? gcMatch.source_urls : []),
        gcMatch?.source_url,
      ].filter(Boolean)
      const linkHtml = (url) => {
        const label = this._urlLabel?.(url) || url.substring(0, 30)
        const icon = this._urlIcon?.(url) || "fa-solid fa-link"
        return `<a href="${this._safeUrl(url)}" target="_blank" rel="noopener" class="anchor-gc-link"><i class="${icon}"></i><span>${this._escapeHtml(label)}</span></a>`
      }

      const confidenceText = strike.strikeConfidence === "verified" || strike.detectionKind === "verified_strike"
        ? "GeoConfirmed corroboration matches this heat signature."
        : strike.clusterSize > 0
          ? `${strike.clusterSize + 1} nearby detections support this heat signature.`
          : "Single heat signature pending stronger corroboration."
      const corroborationHtml = gcMatch || confidenceText
        ? `<div class="anchor-strike-note">
            ${gcMatch?.title ? `<div class="anchor-strike-note-title">${this._escapeHtml(gcMatch.title)}</div>` : ""}
            <div class="anchor-strike-note-body">${this._escapeHtml(gcMatch?.description || confidenceText)}</div>
          </div>`
        : ""

      const linksHtml = sourceUrls.length
        ? `<div class="anchor-gc-links">${sourceUrls.slice(0, 3).map(linkHtml).join("")}</div>`
        : ""

      mediaExtraHtml = `${corroborationHtml}${linksHtml}${mediaExtraHtml}`
    }

    return `
      <div class="anchor-head">
        <div class="anchor-chip-row">${chipsHtml}</div>
        ${payload.timeLabel ? `<div class="anchor-time">${this._escapeHtml(payload.timeLabel)}</div>` : ""}
      </div>
      <div class="anchor-title">${this._escapeHtml(payload.title || kindLabel(payload.kind))}</div>
      ${subtitleHtml}
      ${briefHtml}
      ${mediaExtraHtml}
      ${actionsHtml}
    `
  }
}
