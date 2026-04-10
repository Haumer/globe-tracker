import {
  regionAvailableLayers,
  regionDefaultLayers,
  regionSectorModes,
  regionalEconomyMapLegend,
  renderLocalProfileList,
  sectorModeKey,
  sectorModeLabel,
  titleizeProfileKey,
} from "globe/controller/regional_profiles/shared"

export function applyRegionalLocalProfileShellMethods(GlobeController) {
  GlobeController.prototype._renderLocalProfile = function() {
    if (!this.hasLocalProfileContentTarget) return

    const region = this._localProfileRegion()
    if (!region) {
      this.localProfileContentTarget.innerHTML = `
        <div class="local-profile-empty">
          Enter a regional profile to switch from the global globe into a denser local operating picture.
        </div>
      `
      return
    }

    const countries = (region.countries || [])
      .map(country => `<span class="local-profile-chip">${this._escapeHtml(country)}</span>`)
      .join("")
    const summaryModules = (region.summaryModules || []).map(titleizeProfileKey)
    const dataPacks = (region.dataPacks || []).map(titleizeProfileKey)
    const defaultLayerNames = regionDefaultLayers(region).map(titleizeProfileKey)
    const availableLayerNames = regionAvailableLayers(region).map(titleizeProfileKey)
    const hasExtendedLayerCatalog = availableLayerNames.join("|") !== defaultLayerNames.join("|")
    const mapView = this._regionalEconomyMapView?.(region)
    const sectorModes = regionSectorModes(region)
    const metricOptions = this._regionalEconomyMetricOptions?.(region)
    const selectedMetricKey = this._regionalEconomyMetricKey?.(region)
    const selectedMetric = this._regionalEconomyMetricConfig?.(region)
    const selectedMetricSource = this._regionalEconomyMetricSourceSummary?.(region)
    const selectedSectorKey = this._regionalEconomySectorMode?.(region)
    const selectedSectorLabel = this._regionalEconomySectorLabel?.(region)
    const showSectorFocus = mapView === "admin" && selectedMetricKey === "structure_signal"
    const mapLegend = regionalEconomyMapLegend(
      mapView,
      selectedSectorLabel,
      selectedMetric?.label || "Metric",
      selectedMetricSource,
      selectedMetricKey
    )
    const mapViewButtons = region.mode === "economic" ? `
      <div class="local-profile-section">
        <div class="local-profile-section-title">Granularity</div>
        <div class="local-profile-actions">
          <button type="button" class="local-profile-btn ${mapView === "admin" ? "" : "local-profile-btn--ghost"}" data-action="click->globe#setRegionalEconomyMapView" data-map-view="admin" aria-pressed="${mapView === "admin"}">Region</button>
          <button type="button" class="local-profile-btn ${mapView === "district" ? "" : "local-profile-btn--ghost"}" data-action="click->globe#setRegionalEconomyMapView" data-map-view="district" aria-pressed="${mapView === "district"}">District</button>
          <button type="button" class="local-profile-btn ${mapView === "country" ? "" : "local-profile-btn--ghost"}" data-action="click->globe#setRegionalEconomyMapView" data-map-view="country" aria-pressed="${mapView === "country"}">Country</button>
          <button type="button" class="local-profile-btn ${mapView === "off" ? "" : "local-profile-btn--ghost"}" data-action="click->globe#setRegionalEconomyMapView" data-map-view="off" aria-pressed="${mapView === "off"}">Normal</button>
        </div>
        ${showSectorFocus ? `
          <div class="local-profile-section-title">Sector Focus</div>
          <div class="local-profile-actions">
            ${sectorModes.map(mode => {
              const key = sectorModeKey(mode)
              return `<button type="button" class="local-profile-btn ${selectedSectorKey === key ? "" : "local-profile-btn--ghost"}" data-action="click->globe#setRegionalEconomySectorFocus" data-sector-key="${this._escapeHtml(key)}" aria-pressed="${selectedSectorKey === key}">${this._escapeHtml(sectorModeLabel(mode))}</button>`
            }).join("")}
          </div>
        ` : ""}
        ${mapView !== "off" ? `
          <div class="local-profile-section-title">Metric</div>
          <div class="local-profile-actions">
            ${metricOptions.map(metric => `
              <button type="button" class="local-profile-btn ${selectedMetricKey === metric.key ? "" : "local-profile-btn--ghost"}" data-action="click->globe#setRegionalEconomyMetric" data-metric-key="${this._escapeHtml(metric.key)}" aria-pressed="${selectedMetricKey === metric.key}">${this._escapeHtml(metric.shortLabel || metric.label)}</button>
            `).join("")}
          </div>
          <div class="local-profile-empty-row">Source · ${this._escapeHtml(selectedMetricSource)}</div>
        ` : ""}
        <div class="local-profile-legend-row">${mapLegend.chips.join("")}</div>
        <ul class="local-profile-list local-profile-list--compact">${renderLocalProfileList(mapLegend.items.map(item => this._escapeHtml(item)), "No map legend yet")}</ul>
      </div>
    ` : ""

    this.localProfileContentTarget.innerHTML = `
      <section class="local-profile-shell">
        <div class="local-profile-head">
          <div>
            <div class="local-profile-kicker">${this._escapeHtml(titleizeProfileKey(region.mode || "regional"))} Profile</div>
            <h2 class="local-profile-title">${this._escapeHtml(region.name)} Local Mode</h2>
            <p class="local-profile-desc">${this._escapeHtml(region.description || "")}</p>
          </div>
          <div class="local-profile-actions">
            <button type="button" class="local-profile-btn local-profile-btn--ghost" data-action="click->globe#closeLocalProfile">Close local mode</button>
            <button type="button" class="local-profile-btn" data-action="click->globe#exitRegion">Return to globe</button>
          </div>
        </div>

        <div class="local-profile-section">
          <div class="local-profile-section-title">Scope</div>
          <div class="local-profile-chip-row">${countries}</div>
        </div>

        ${mapViewButtons}

        <div class="local-profile-section" data-local-profile-economy>
          <div class="local-profile-section-title">Regional Economy Baseline</div>
          <div class="local-profile-empty-row">Loading regional economy baseline…</div>
        </div>

        <div class="local-profile-section" data-local-profile-admin-preview>
          <div class="local-profile-section-title">Regional Structure</div>
          <div class="local-profile-empty-row">Loading regional structure…</div>
        </div>

        <div class="local-profile-section" data-local-profile-district-preview>
          <div class="local-profile-section-title">District Metric</div>
          <div class="local-profile-empty-row">Loading district data…</div>
        </div>

        <div class="local-profile-grid">
          <div class="local-profile-section">
            <div class="local-profile-section-title">Summary Modules</div>
            <ul class="local-profile-list">${renderLocalProfileList(summaryModules, "No summary modules yet")}</ul>
          </div>

          <div class="local-profile-section">
            <div class="local-profile-section-title">Data Packs</div>
            <ul class="local-profile-list">${renderLocalProfileList(dataPacks, "No data packs yet")}</ul>
          </div>
        </div>

        <div class="local-profile-section">
          <div class="local-profile-section-title">Default Layer Mix</div>
          <ul class="local-profile-list local-profile-list--compact">${renderLocalProfileList(defaultLayerNames, "No local layers yet")}</ul>
        </div>

        <div class="local-profile-section" data-local-profile-data-sources>
          <div class="local-profile-section-title">Source Coverage</div>
          <div class="local-profile-empty-row">Loading source coverage…</div>
        </div>

        <div class="local-profile-section" data-local-profile-power-plants>
          <div class="local-profile-section-title">Curated Power Coverage</div>
          <div class="local-profile-empty-row">Loading curated power coverage…</div>
        </div>

        <div class="local-profile-section" data-local-profile-city-coverage>
          <div class="local-profile-section-title">Economic City Coverage</div>
          <div class="local-profile-empty-row">Loading city coverage…</div>
        </div>

        <div class="local-profile-section" data-local-profile-strategic-sites>
          <div class="local-profile-section-title">Strategic Site Coverage</div>
          <div class="local-profile-empty-row">Loading strategic-site coverage…</div>
        </div>

        ${hasExtendedLayerCatalog ? `
        <div class="local-profile-section">
          <div class="local-profile-section-title">Regional Layer Catalog</div>
          <ul class="local-profile-list local-profile-list--compact">${renderLocalProfileList(availableLayerNames, "No regional layers yet")}</ul>
        </div>` : ""}
      </section>
    `

    this._renderLocalRegionalEconomyBaseline?.(region)
    this._renderLocalRegionalAdminPreview?.(region)
    this._renderLocalRegionalDistrictPreview?.(region)
    this._renderLocalSourceCoverage?.(region)
    this._renderLocalPowerPlantCoverage?.(region)
    this._renderLocalCityCoverage?.(region)
    this._renderLocalStrategicSiteCoverage?.(region)
  }
}
