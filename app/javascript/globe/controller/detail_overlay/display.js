import { kindLabel } from "globe/controller/detail_overlay/shared"

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
      hiddenSince: null,
    }
    const stroke = payload.stroke || payload.accent || "#8bd8ff"
    const strokeWidth = payload.strokeWidth || 2.25
    this.anchorOverlayTarget.style.display = ""
    this.anchorPanelTarget.style.display = ""
    this.anchorPanelTarget.dataset.mode = "anchored"
    this.anchorPanelTarget.dataset.kind = payload.kind || ""
    this.anchorOverlayTarget.style.setProperty("--anchor-accent", payload.accent || "#8bd8ff")
    this.anchorOverlayTarget.style.setProperty("--anchor-stroke", stroke)
    this.anchorOverlayTarget.style.setProperty("--anchor-border-width", `${strokeWidth}px`)
    this.anchorPanelTarget.style.setProperty("--anchor-accent", payload.accent || "#8bd8ff")
    this.anchorPanelTarget.style.setProperty("--anchor-stroke", stroke)
    this.anchorPanelTarget.style.setProperty("--anchor-border-width", `${strokeWidth}px`)
    this.anchorContentTarget.innerHTML = this._renderAnchoredDetailHtml(payload)

    this._refreshAnchoredDetailPosition(true)
    this._requestRender?.()
  }

  GlobeController.prototype.closeAnchoredDetail = function() {
    this._anchoredDetailState = null
    if (this.hasAnchorPanelTarget) {
      this.anchorPanelTarget.style.display = "none"
      this.anchorPanelTarget.style.left = ""
      this.anchorPanelTarget.style.top = ""
      this.anchorPanelTarget.dataset.mode = "anchored"
      delete this.anchorPanelTarget.dataset.kind
      this.anchorPanelTarget.style.removeProperty("--anchor-accent")
      this.anchorPanelTarget.style.removeProperty("--anchor-stroke")
      this.anchorPanelTarget.style.removeProperty("--anchor-border-width")
    }
    if (this.hasAnchorOverlayTarget) {
      this.anchorOverlayTarget.style.display = "none"
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

    return `
      <div class="anchor-head">
        <div class="anchor-chip-row">${chipsHtml}</div>
        ${payload.timeLabel ? `<div class="anchor-time">${this._escapeHtml(payload.timeLabel)}</div>` : ""}
      </div>
      <div class="anchor-title">${this._escapeHtml(payload.title || kindLabel(payload.kind))}</div>
      ${subtitleHtml}
      ${briefHtml}
    `
  }
}
