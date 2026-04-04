export function applyUiPanelMethods(GlobeController) {
  GlobeController.prototype._isMobile = function() {
    return window.matchMedia("(max-width: 768px)").matches
  }

  GlobeController.prototype.toggleSidebar = function() {
    if (this._isMobile()) {
      const sidebar = this.sidebarTarget
      const expanded = sidebar.classList.contains("mobile-expanded")
      sidebar.classList.toggle("mobile-expanded", !expanded)
      sidebar.classList.toggle("mobile-peek", expanded)
      this._syncMobileChrome?.()
    } else {
      this.sidebarTarget.classList.toggle("collapsed")
    }
    this._savePrefs()
  }

  GlobeController.prototype.toggleSection = function(event) {
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return
    if (event.key === " ") event.preventDefault()

    const head = event.currentTarget
    head.classList.toggle("open")
    head.setAttribute("aria-expanded", String(head.classList.contains("open")))
    this._savePrefs()
  }

  GlobeController.prototype.toggleRightPanel = function() {
    if (!this.hasRightPanelTarget) return
    const visible = this.rightPanelTarget.style.display !== "none"
    if (visible) this.closeRightPanel()
    else this._showRightPanel("context")
  }
}
