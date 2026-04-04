function captureMobileSurfaceState(controller) {
  return {
    detail: controller.hasDetailPanelTarget && controller.detailPanelTarget.style.display !== "none",
    panel: controller.hasRightPanelTarget && controller.rightPanelTarget.style.display !== "none",
    timeline: controller.hasTimelineBarTarget && controller.timelineBarTarget.style.display !== "none",
    layers: controller.hasSidebarTarget && controller.sidebarTarget.classList.contains("mobile-expanded"),
  }
}

function activeSceneMode(controller) {
  if (controller._currentMobileSceneMode) return controller._currentMobileSceneMode
  if (!controller.viewer?.scene || !window.Cesium) return "2d"
  return controller.viewer.scene.mode === window.Cesium.SceneMode.SCENE3D ? "3d" : "2d"
}

export function applyUiMobileMethods(GlobeController) {
  GlobeController.prototype.initMobileUi = function() {
    if (this._mobileUiReady) return
    this._mobileUiReady = true
    this._mobileSurfaceOverride = null
    this._mobileSurfaceState = captureMobileSurfaceState(this)
    this._mobileMediaQuery = window.matchMedia("(max-width: 768px)")
    this._onMobileMediaChange = () => this._syncMobileLayout()

    if (this._mobileMediaQuery.addEventListener) this._mobileMediaQuery.addEventListener("change", this._onMobileMediaChange)
    else this._mobileMediaQuery.addListener(this._onMobileMediaChange)

    this._mobilePanelObserver = new MutationObserver(() => this._handleMobileSurfaceMutation())
    ;[
      this.hasSidebarTarget ? this.sidebarTarget : null,
      this.hasRightPanelTarget ? this.rightPanelTarget : null,
      this.hasTimelineBarTarget ? this.timelineBarTarget : null,
      this.hasDetailPanelTarget ? this.detailPanelTarget : null,
    ].filter(Boolean).forEach(element => {
      this._mobilePanelObserver.observe(element, {
        attributes: true,
        attributeFilter: ["class", "style"],
      })
    })

    this._syncMobileLayout()
  }

  GlobeController.prototype._teardownMobileUi = function() {
    if (this._mobileMediaQuery && this._onMobileMediaChange) {
      if (this._mobileMediaQuery.removeEventListener) this._mobileMediaQuery.removeEventListener("change", this._onMobileMediaChange)
      else this._mobileMediaQuery.removeListener(this._onMobileMediaChange)
    }
    if (this._mobilePanelObserver) this._mobilePanelObserver.disconnect()
  }

  GlobeController.prototype._handleMobileSurfaceMutation = function() {
    if (!this._isMobile()) return

    const previous = this._mobileSurfaceState || captureMobileSurfaceState(this)
    const current = captureMobileSurfaceState(this)

    if (current.detail && !previous.detail) {
      this._mobileSurfaceOverride = null
    } else if (current.timeline && !previous.timeline) {
      this._mobileSurfaceOverride = "timeline"
    } else if (current.panel && !previous.panel) {
      this._mobileSurfaceOverride = "panel"
    } else if (current.layers && !previous.layers) {
      this._mobileSurfaceOverride = "layers"
    }

    if (this._mobileSurfaceOverride && !current[this._mobileSurfaceOverride]) {
      this._mobileSurfaceOverride = null
    }

    this._mobileSurfaceState = current
    this._syncMobileChrome()
  }

  GlobeController.prototype._syncMobileLayout = function() {
    const mobile = this._isMobile()

    if (mobile && this.hasSidebarTarget && !this.sidebarTarget.classList.contains("mobile-expanded")) {
      this.sidebarTarget.classList.add("mobile-peek")
    }

    if (!mobile && this.hasSidebarTarget) {
      this.sidebarTarget.classList.remove("mobile-peek", "mobile-expanded")
    }

    if (!mobile) {
      this._mobileSurfaceOverride = null
      if (this.viewer?.scene && window.Cesium && this.viewer.scene.mode !== window.Cesium.SceneMode.SCENE3D) {
        this._setMobileSceneMode("3d", { immediate: true, silent: true })
      }
    } else if (this.viewer) {
      this._applyInitialMobileSceneMode()
    }

    this._mobileSurfaceState = captureMobileSurfaceState(this)
    this._syncMobileChrome()
  }

  GlobeController.prototype._applyInitialMobileSceneMode = function() {
    if (!this.viewer || !this._isMobile()) return

    let preferred = "2d"
    try {
      preferred = window.localStorage.getItem("gt_mobile_scene_mode") || "2d"
    } catch {}

    this._setMobileSceneMode(preferred, { immediate: true, silent: true })
  }

  GlobeController.prototype._setMobileSceneMode = function(mode, { immediate = false, silent = false } = {}) {
    if (!this.viewer?.scene || !window.Cesium) return

    const Cesium = window.Cesium
    const nextMode = mode === "3d" ? "3d" : "2d"
    const scene = this.viewer.scene
    const controls = scene.screenSpaceCameraController
    const duration = immediate ? 0 : 0.5

    if (nextMode === "2d") {
      if (scene.mode !== Cesium.SceneMode.SCENE2D) scene.morphTo2D(duration)
      controls.enableRotate = false
      controls.enableTilt = false
      controls.enableLook = false
      controls.enableTranslate = true
      scene.skyAtmosphere.show = false
      scene.fog.enabled = false
      scene.globe.showGroundAtmosphere = false
    } else {
      if (scene.mode !== Cesium.SceneMode.SCENE3D) scene.morphTo3D(duration)
      controls.enableRotate = true
      controls.enableTilt = true
      controls.enableLook = true
      controls.enableTranslate = true
      scene.skyAtmosphere.show = true
      scene.fog.enabled = true
      scene.globe.showGroundAtmosphere = true
    }

    this._currentMobileSceneMode = nextMode
    if (this._isMobile()) {
      try {
        window.localStorage.setItem("gt_mobile_scene_mode", nextMode)
      } catch {}
    }

    this._syncMobileDock()
    if (!silent && this._isMobile()) {
      this._toast(nextMode === "2d" ? "2D map enabled" : "3D globe enabled")
    }
  }

  GlobeController.prototype.switchMobileScene = function(event) {
    const mode = event.currentTarget.dataset.mobileScene
    if (!mode) return
    this._setMobileSceneMode(mode)
  }

  GlobeController.prototype.applyScenarioPreset = function(event) {
    const scenario = event.currentTarget.dataset.scenario
    if (!scenario) return
    this._applyScenario(scenario)
    this._mobileSurfaceOverride = null
    if (this.hasSidebarTarget) this.sidebarTarget.classList.remove("mobile-expanded")
    if (this.hasSidebarTarget && this._isMobile()) this.sidebarTarget.classList.add("mobile-peek")
    this._syncMobileChrome()
  }

  GlobeController.prototype.dismissMobileSurface = function() {
    if (!this._isMobile()) return

    const surface = this.element.dataset.mobileSurface
    if (surface === "timeline" && this._timelineActive) {
      this.timelineClose()
      return
    }

    if (surface === "layers" && this.hasSidebarTarget) {
      this.sidebarTarget.classList.remove("mobile-expanded")
      this.sidebarTarget.classList.add("mobile-peek")
      this._mobileSurfaceOverride = null
      this._syncMobileChrome()
      return
    }

    if (surface === "detail" && this.hasDetailPanelTarget && this.detailPanelTarget.style.display !== "none") {
      this.closeDetail()
      return
    }

    if (surface === "panel" && this.hasRightPanelTarget && this.rightPanelTarget.style.display !== "none") {
      this.closeRightPanel()
    }
  }

  GlobeController.prototype._syncMobileChrome = function() {
    if (!this._isMobile()) {
      this.element.dataset.mobileSurface = "desktop"
      this._syncMobileDock()
      return
    }

    const state = captureMobileSurfaceState(this)
    const override = this._mobileSurfaceOverride && state[this._mobileSurfaceOverride] ? this._mobileSurfaceOverride : null
    const surface = override || (state.detail ? "detail" : state.timeline ? "timeline" : state.panel ? "panel" : state.layers ? "layers" : "map")

    this._mobileSurfaceState = state
    this.element.dataset.mobileSurface = surface
    this._syncMobileDock()
  }

  GlobeController.prototype._syncMobileDock = function() {
    const surface = this.element.dataset.mobileSurface || "map"

    this.element.querySelectorAll("[data-mobile-scene]").forEach(button => {
      const active = button.dataset.mobileScene === activeSceneMode(this)
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-selected", String(active))
    })

    this.element.querySelectorAll("[data-mobile-surface-target]").forEach(button => {
      const target = button.dataset.mobileSurfaceTarget
      const active = target !== "reset" && target === surface
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-pressed", String(active))
    })
  }
}
