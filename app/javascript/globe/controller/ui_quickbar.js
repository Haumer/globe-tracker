import { LAYER_REGISTRY, QUICK_TOGGLE_MAP } from "globe/controller/ui_registry"

export function applyUiQuickBarMethods(GlobeController) {
  GlobeController.prototype.quickToggle = function(event) {
    const layer = event.currentTarget.dataset.layer

    if (layer === "satellites") {
      toggleSatelliteQuickMode.call(this)
      this._syncQuickBar()
      this._updateSatBadge()
      return
    }

    const config = QUICK_TOGGLE_MAP[layer]
    if (!config) return

    const targetName = `${config.target}Target`
    const hasTarget = `has${capitalize(config.target)}Target`
    if (this[hasTarget]) this[targetName].checked = !this[targetName].checked
    this[config.method]()
    this._syncQuickBar()
  }

  GlobeController.prototype.toggleSatChip = function(event) {
    const button = event.currentTarget
    const category = button.dataset.category
    const syntheticEvent = { target: { dataset: { category }, checked: !this.satCategoryVisible[category] } }
    this.toggleSatCategory(syntheticEvent)
    button.classList.toggle("active", this.satCategoryVisible[category])
    button.setAttribute("aria-pressed", String(this.satCategoryVisible[category]))
    this._syncQuickBar()
    this._updateSatBadge()
  }

  GlobeController.prototype._syncQuickBar = function() {
    if (this._syncQBTimer) return
    this._syncQBTimer = requestAnimationFrame(() => {
      this._syncQBTimer = null
      this._syncQuickBarImpl()
    })
  }

  GlobeController.prototype._syncQuickBarImpl = function() {
    const syncTarget = (targetName, active) => {
      const hasTarget = `has${capitalize(targetName)}Target`
      if (!this[hasTarget]) return
      this[`${targetName}Target`].classList.toggle("active", active)
      this[`${targetName}Target`].setAttribute("aria-pressed", String(active))
    }

    for (const layer of LAYER_REGISTRY) {
      syncTarget(layer.qlTarget, this[layer.visibleProp])
    }

    const anySat = Object.values(this.satCategoryVisible).some(Boolean)
    syncTarget("qlSatellites", anySat)

    if (this.hasFlightSubOptionsTarget) this.flightSubOptionsTarget.style.display = this.flightsVisible ? "" : "none"
    if (this.hasFireHotspotOptionsTarget) this.fireHotspotOptionsTarget.style.display = this.fireHotspotsVisible ? "" : "none"
    if (this.hasSituationOptionsTarget) this.situationOptionsTarget.style.display = this.situationsVisible ? "" : "none"
    if (this._weatherPanelBuilt) this._showWeatherPanel(this.weatherVisible)

    this._updateSectionCounts()
    this._renderActiveLayerPills()
    this._updateSidebarBadge()
  }

  GlobeController.prototype._updateSectionCounts = function() {
    const counts = {}
    for (const layer of LAYER_REGISTRY) {
      if (!layer.section || layer.section === "map") continue
      if (!counts[layer.section]) counts[layer.section] = 0
      if (this[layer.visibleProp]) counts[layer.section]++
    }
    if (Object.values(this.satCategoryVisible).some(Boolean)) {
      counts.tracking = (counts.tracking || 0) + 1
    }

    for (const key of ["tracking", "events", "military", "infrastructure", "cyber"]) {
      const count = counts[key] || 0
      const element = document.getElementById(`sec-count-${key}`)
      if (element) element.textContent = count > 0 ? `${count} on` : ""
    }
  }

  GlobeController.prototype._updateSidebarBadge = function() {
    const badge = document.getElementById("sidebar-layer-badge")
    if (!badge) return
    let count = LAYER_REGISTRY.filter(layer => this[layer.visibleProp]).length
    if (Object.values(this.satCategoryVisible).some(Boolean)) count++
    badge.textContent = count
    badge.style.display = count > 0 ? "" : "none"
  }

  GlobeController.prototype._renderActiveLayerPills = function() {
    if (!this.hasActiveLayerPillsTarget) return

    const layers = LAYER_REGISTRY
      .filter(layer => layer.pill)
      .map(layer => ({
        key: layer.key,
        active: this[layer.visibleProp],
        color: layer.pill.color,
        label: layer.pill.label,
      }))

    layers.splice(2, 0, {
      key: "satellites",
      active: Object.values(this.satCategoryVisible).some(Boolean),
      color: "#ab47bc",
      label: "SAT",
    })

    const active = layers.filter(layer => layer.active)
    if (active.length === 0) {
      this.activeLayerPillsTarget.innerHTML = '<span class="bs-no-layers">No layers active</span>'
      return
    }

    this.activeLayerPillsTarget.innerHTML = active
      .map(layer => `<span class="bs-pill" style="--pill-color: ${layer.color};">${layer.label}</span>`)
      .join("")
  }

  GlobeController.prototype._updateSatBadge = function() {
    if (!this.hasSatBadgeTarget) return
    const count = Object.values(this.satCategoryVisible).filter(Boolean).length
    if (count > 0) {
      this.satBadgeTarget.textContent = count
      this.satBadgeTarget.style.display = ""
    } else {
      this.satBadgeTarget.style.display = "none"
    }
  }
}

function capitalize(value) {
  return value.charAt(0).toUpperCase() + value.slice(1)
}

function toggleSatelliteQuickMode() {
  const anySat = Object.values(this.satCategoryVisible).some(Boolean)
  const defaults = ["stations", "gps-ops", "weather", "military"]
  if (anySat) {
    for (const category of Object.keys(this.satCategoryVisible)) {
      if (!this.satCategoryVisible[category]) continue
      this.toggleSatCategory({ target: { dataset: { category }, checked: false } })
    }
  } else {
    for (const category of defaults) {
      this.toggleSatCategory({ target: { dataset: { category }, checked: true } })
    }
  }

  this.element.querySelectorAll(".sb-chip[data-category]").forEach(chip => {
    const category = chip.dataset.category
    chip.classList.toggle("active", this.satCategoryVisible[category])
    chip.setAttribute("aria-pressed", String(this.satCategoryVisible[category]))
  })
}
