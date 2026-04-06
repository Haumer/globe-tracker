import { ADVANCED_LIBRARY_KEYS, LAYER_REGISTRY_BY_KEY, QUICK_TOGGLE_MAP, isLayerTemporarilyDisabled } from "globe/controller/ui/registry"

const ADVANCED_LIBRARY_SET = new Set(ADVANCED_LIBRARY_KEYS)

export function applyUiLayerLibraryMethods(GlobeController) {
  GlobeController.prototype.toggleLayerEnablement = function(event) {
    if (!this.signedInValue) return

    const key = event.currentTarget.dataset.layerEnableKey
    if (!key || !ADVANCED_LIBRARY_SET.has(key)) return
    if (isLayerTemporarilyDisabled(key)) {
      this._toast?.("Layer temporarily disabled during cleanup")
      return
    }

    this._enabledAdvancedLayers ||= new Set()

    if (this._enabledAdvancedLayers.has(key)) {
      this._disableAdvancedLayer(key)
    } else {
      this._enabledAdvancedLayers.add(key)
      this._activateAdvancedLayer(key)
    }

    openAdditionalLayersSection(this)
    this._syncLayerLibrary()
    this._syncQuickBar()
    this._savePrefs()
  }

  GlobeController.prototype._ensureAdvancedLayersEnabled = function(layerKeys = []) {
    if (!this.signedInValue || !Array.isArray(layerKeys)) return

    this._enabledAdvancedLayers ||= new Set()
    let changed = false

    layerKeys.forEach((key) => {
      if (!ADVANCED_LIBRARY_SET.has(key) || this._enabledAdvancedLayers.has(key) || isLayerTemporarilyDisabled(key)) return
      this._enabledAdvancedLayers.add(key)
      changed = true
    })

    if (changed) this._syncLayerLibrary()
  }

  GlobeController.prototype._syncLayerLibrary = function() {
    this._enabledAdvancedLayers ||= new Set()
    let visibleCount = 0

    this.element.querySelectorAll("[data-enabled-layer-row]").forEach((row) => {
      const key = row.dataset.enabledLayerRow
      const visible = this._enabledAdvancedLayers.has(key) || advancedLayerIsActive(this, key)
      row.style.display = visible ? "" : "none"
      if (visible) visibleCount += 1
    })

    this.element.querySelectorAll("[data-layer-enable-key]").forEach((button) => {
      const key = button.dataset.layerEnableKey
      const disabled = isLayerTemporarilyDisabled(key)
      if (disabled) this._enabledAdvancedLayers.delete(key)
      const active = !disabled && this._enabledAdvancedLayers.has(key)
      button.classList.toggle("active", active && !disabled)
      button.classList.toggle("is-disabled", disabled)
      button.setAttribute("aria-pressed", String(active))
      button.setAttribute("aria-disabled", String(disabled))
      button.dataset.state = active ? "enabled" : disabled ? "disabled" : "available"

      const state = button.querySelector("[data-layer-library-state]")
      if (state) state.textContent = active ? "Enabled" : disabled ? "Soon" : "Add"
    })

    const emptyState = this.element.querySelector("[data-advanced-empty-state]")
    if (emptyState) {
      emptyState.style.display = visibleCount > 0 ? "none" : ""
    }
  }

  GlobeController.prototype._disableAdvancedLayer = function(key) {
    this._enabledAdvancedLayers.delete(key)

    if (key === "satellites") {
      disableSatelliteCategories.call(this)
      return
    }

    const layer = LAYER_REGISTRY_BY_KEY[key]
    const config = QUICK_TOGGLE_MAP[key]
    if (!layer || !config || !this[layer.visibleProp]) return

    const targetName = `${config.target}Target`
    const hasTarget = `has${capitalize(config.target)}Target`
    if (this[hasTarget]) this[targetName].checked = false
    this[config.method]()
  }

  GlobeController.prototype._activateAdvancedLayer = function(key) {
    if (key === "satellites") {
      activateDefaultSatelliteCategories.call(this)
      return
    }

    const layer = LAYER_REGISTRY_BY_KEY[key]
    const config = QUICK_TOGGLE_MAP[key]
    if (!layer || !config || this[layer.visibleProp]) return

    const targetName = `${config.target}Target`
    const hasTarget = `has${capitalize(config.target)}Target`
    if (this[hasTarget]) this[targetName].checked = true
    this[config.method]()
  }
}

function disableSatelliteCategories() {
  if (!this.satCategoryVisible) return

  Object.keys(this.satCategoryVisible).forEach((category) => {
    if (!this.satCategoryVisible[category]) return
    this.toggleSatCategory({ target: { dataset: { category }, checked: false } })
  })

  this.element.querySelectorAll(".sb-chip[data-category]").forEach((chip) => {
    const category = chip.dataset.category
    chip.classList.toggle("active", !!this.satCategoryVisible[category])
    chip.setAttribute("aria-pressed", String(!!this.satCategoryVisible[category]))
  })

  this._updateSatBadge()
}

function activateDefaultSatelliteCategories() {
  if (!this.satCategoryVisible) return

  const anySat = Object.values(this.satCategoryVisible).some(Boolean)
  if (anySat) return

  const defaults = ["stations", "gps-ops", "weather", "military"]
  defaults.forEach((category) => {
    this.toggleSatCategory({ target: { dataset: { category }, checked: true } })
  })

  this.element.querySelectorAll(".sb-chip[data-category]").forEach((chip) => {
    const category = chip.dataset.category
    chip.classList.toggle("active", !!this.satCategoryVisible[category])
    chip.setAttribute("aria-pressed", String(!!this.satCategoryVisible[category]))
  })

  this._updateSatBadge()
}

function advancedLayerIsActive(controller, key) {
  if (key === "satellites") {
    return Object.values(controller.satCategoryVisible || {}).some(Boolean)
  }

  const layer = LAYER_REGISTRY_BY_KEY[key]
  return !!(layer && controller[layer.visibleProp])
}

function openAdditionalLayersSection(controller) {
  const head = controller.element.querySelector('.sb-section[data-section="additional-layers"] .sb-section-head')
  if (!head) return
  head.classList.add("open")
  head.setAttribute("aria-expanded", "true")
}

function capitalize(value) {
  return value.charAt(0).toUpperCase() + value.slice(1)
}
