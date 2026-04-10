// ── Region Mode ──────────────────────────────────────────────
// Focused regional analysis with curated layer profiles.
// Entering a region: snapshots current state, clears layers,
// flies camera to region, enables region-specific layers,
// and scopes all data fetches to the region's bounding box.

import { REGIONS, REGION_MAP, REGION_GROUPS } from "globe/regions"
import { applyDeepLink } from "globe/deeplinks"
import { COUNTRY_CENTROIDS } from "globe/country_centroids"
import { getDataSource, LABEL_DEFAULTS } from "globe/utils"
import { defaultRegionalMetricKey, regionalMetricConfig, regionalMetricOptions, regionalMetricSourceSummary } from "globe/controller/regional_profiles/catalog"

export function applyRegionMethods(GlobeController) {
  const USD_COMPACT_FORMAT = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    notation: "compact",
    maximumFractionDigits: 1,
  })
  const NUMBER_COMPACT_FORMAT = new Intl.NumberFormat("en-US", {
    notation: "compact",
    maximumFractionDigits: 1,
  })
  const DECIMAL_FORMAT = new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 1,
  })
  const REGIONAL_SECTOR_MATCHERS = {
    automotive: ["automotive", "vehicle", "vehicles", "truck", "mobility", "driveline"],
    semiconductors: ["semiconductor", "chip", "chips", "electronics", "microtechnology", "microelectronics"],
    chemicals: ["chemical", "chemicals", "refining", "refinery", "fuel", "silicones", "materials", "battery materials"],
    energy: ["energy", "power", "hydropower", "electricity", "utilities", "green hydrogen"],
    finance_services: ["finance", "banking", "insurance", "private banking", "professional services", "commodity trading"],
    logistics_trade: ["logistics", "port", "trade", "distribution", "warehousing", "air cargo", "danube logistics", "rail logistics", "cross-border trade", "wholesale"],
    government_policy: ["government", "public administration", "federal administration", "policy", "administration", "public services", "institutions"],
    life_sciences: ["pharma", "pharmaceuticals", "biopharma", "life sciences", "medical technology", "health services"],
    machinery_engineering: ["machinery", "engineering", "industrial automation", "industrial technology", "metals", "steel", "forgings", "precision manufacturing"],
    knowledge_tech: ["software", "digital", "research", "ai", "education", "technology", "telecom"],
    tourism: ["tourism", "hospitality", "winter sports"],
  }

  function regionBoundsCenter(bounds = {}) {
    return {
      lat: ((bounds.lamin || 0) + (bounds.lamax || 0)) / 2.0,
      lng: ((bounds.lomin || 0) + (bounds.lomax || 0)) / 2.0,
    }
  }

  function regionCameraCenter(region) {
    const center = regionBoundsCenter(region.bounds)
    return {
      lat: region.camera?.lat ?? center.lat,
      lng: region.camera?.lng ?? center.lng,
    }
  }

  function regionCameraHeight(region) {
    const bounds = region.bounds || {}
    const center = regionBoundsCenter(bounds)
    const latSpanKm = Math.abs((bounds.lamax || 0) - (bounds.lamin || 0)) * 111.0
    const lngSpanKm = Math.abs((bounds.lomax || 0) - (bounds.lomin || 0)) * 111.0 * Math.abs(Math.cos(center.lat * Math.PI / 180))
    const derivedHeight = Math.round((Math.max(latSpanKm, lngSpanKm) * 1250.0) / 10000) * 10000
    return Math.max(region.camera?.height || 0, derivedHeight, 300000)
  }

  function regionDefaultLayers(region = {}) {
    return [...(region.defaultLayers || region.layers || [])]
  }

  function regionAvailableLayers(region = {}) {
    return [...(region.availableLayers || region.defaultLayers || region.layers || [])]
  }

  function regionCountryCodes(region = {}) {
    return [...(region.countryCodes || [])]
  }

  function regionSectorModes(region = {}) {
    const modes = Array.isArray(region.sectorModes) ? region.sectorModes : []
    if (modes.length > 0) return modes
    return [{ key: "all", label: "All" }]
  }

  function sectorModeKey(sectorMode) {
    return typeof sectorMode === "string" ? sectorMode : sectorMode?.key
  }

  function sectorModeLabel(sectorMode) {
    return typeof sectorMode === "string"
      ? titleizeProfileKey(sectorMode)
      : (sectorMode?.label || titleizeProfileKey(sectorMode?.key))
  }

  function titleizeProfileKey(value) {
    return `${value || ""}`
      .split(/[_-]+/)
      .filter(Boolean)
      .map(part => part.charAt(0).toUpperCase() + part.slice(1))
      .join(" ")
  }

  function renderLocalProfileList(items = [], emptyLabel) {
    if (!items.length) return `<div class="local-profile-empty-row">${emptyLabel}</div>`
    return items.map(item => `<li>${item}</li>`).join("")
  }

  function renderLegendSwatch(colorCss, label) {
    return `
      <span class="local-profile-legend-chip">
        <span class="local-profile-legend-swatch" style="background:${colorCss};"></span>
        <span>${label}</span>
      </span>
    `
  }

  function geometryOuterRings(geometry = {}) {
    if (geometry?.type === "Polygon") return [Array(geometry.coordinates || [])[0]].filter(Boolean)
    if (geometry?.type === "MultiPolygon") return Array(geometry.coordinates || []).map(polygon => Array(polygon || [])[0]).filter(Boolean)
    return []
  }

  function sourceStatusLabel(value) {
    switch (`${value || ""}`.toLowerCase()) {
      case "active":
        return "Active"
      case "seed":
        return "Seed"
      case "planned":
        return "Planned"
      case "deprecated":
        return "Deprecated"
      default:
        return "Unknown"
    }
  }

  function numericMetricValue(value) {
    const number = Number(value)
    return Number.isFinite(number) ? number : null
  }

  function formatCompactCurrency(value) {
    const number = numericMetricValue(value)
    return number == null ? "—" : USD_COMPACT_FORMAT.format(number)
  }

  function formatCompactNumber(value) {
    const number = numericMetricValue(value)
    return number == null ? "—" : NUMBER_COMPACT_FORMAT.format(number)
  }

  function formatPercent(value) {
    const number = numericMetricValue(value)
    return number == null ? "—" : `${DECIMAL_FORMAT.format(number)}%`
  }

  function metricValue(record, key) {
    return numericMetricValue(record?.metrics?.[key])
  }

  function regionalMetricValue(record, metricKey) {
    if (metricKey === "trade_net_pct_gdp") {
      const exportsShare = metricValue(record, "exports_goods_services_pct_gdp")
      const importsShare = metricValue(record, "imports_goods_services_pct_gdp")
      if (exportsShare == null || importsShare == null) return null
      return exportsShare - importsShare
    }

    if (metricKey === "structure_signal") return metricValue(record, "preview_score")

    return metricValue(record, metricKey)
  }

  function formatRegionalMetric(metricConfig, value) {
    const number = numericMetricValue(value)
    if (number == null || !metricConfig) return "—"

    switch (metricConfig.valueType) {
      case "currency":
        return formatCompactCurrency(number)
      case "count":
        return formatCompactNumber(number)
      case "percent":
        return formatPercent(number)
      default:
        return formatCompactNumber(number)
    }
  }

  function sumMetric(records = [], key) {
    const values = records
      .map(record => metricValue(record, key))
      .filter(value => value != null)
    if (values.length === 0) return null
    return values.reduce((sum, value) => sum + value, 0)
  }

  function clampNumber(value, min, max) {
    return Math.min(Math.max(value, min), max)
  }

  function mixHexColors(leftHex, rightHex, ratio) {
    const safeRatio = clampNumber(ratio, 0, 1)
    const parse = (hex) => {
      const value = `${hex || ""}`.replace("#", "")
      return {
        r: Number.parseInt(value.slice(0, 2), 16) || 0,
        g: Number.parseInt(value.slice(2, 4), 16) || 0,
        b: Number.parseInt(value.slice(4, 6), 16) || 0,
      }
    }
    const left = parse(leftHex)
    const right = parse(rightHex)
    const toHex = (value) => Math.round(value).toString(16).padStart(2, "0")

    return `#${toHex(left.r + ((right.r - left.r) * safeRatio))}${toHex(left.g + ((right.g - left.g) * safeRatio))}${toHex(left.b + ((right.b - left.b) * safeRatio))}`
  }

  function regionalEconomyMetricLabel(record, metricConfig, value) {
    const label = metricConfig?.shortLabel || metricConfig?.label || "Metric"
    return `${record.country_name || record.country_code_alpha3 || "Regional economy"}\n${label} ${formatRegionalMetric(metricConfig, value)}`
  }

  function regionalEconomyBorderStyles(records = [], metricKey = "gdp_nominal_usd") {
    const ranked = records
      .slice()
      .sort((left, right) =>
        (regionalMetricValue(right, metricKey) || -1) - (regionalMetricValue(left, metricKey) || -1) ||
        (left.country_name || "").localeCompare(right.country_name || "")
      )
    const palette = ["#2a6f97", "#b28704", "#9d4edd"]

    return ranked.reduce((memo, record, index) => {
      const fillCss = palette[index] || mixHexColors("d97706", "2563eb", index / Math.max(ranked.length - 1, 1))
      const Cesium = window.Cesium
      memo[record.country_name] = {
        fillColor: Cesium.Color.fromCssColorString(fillCss).withAlpha(0.38),
        accentCss: fillCss,
      }
      return memo
    }, {})
  }

  function normalizeRegionalBoundaryLabel(value) {
    return `${value || ""}`
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/ß/g, "ss")
      .replace(/[^a-z0-9]+/gi, "")
      .toLowerCase()
  }

  function regionalAdminPreviewStyles(records = [], scoreAccessor = null) {
    const Cesium = window.Cesium
    const values = records
      .map(record => typeof scoreAccessor === "function" ? scoreAccessor(record) : metricValue(record, "preview_score"))
      .map(numericMetricValue)
      .filter(value => value != null && value >= 0)
    const maxValue = values.length > 0 ? Math.max(...values, 1) : 1

    return records.reduce((memo, record) => {
      const score = typeof scoreAccessor === "function" ? scoreAccessor(record) : metricValue(record, "preview_score")
      const ratio = clampNumber((numericMetricValue(score) || 0) / maxValue, 0, 1)
      const accentCss = mixHexColors("#255f85", "#f59e0b", ratio)

      memo[record.id] = {
        accentCss,
        fillColor: Cesium.Color.fromCssColorString(accentCss).withAlpha(0.14 + (ratio * 0.36)),
        lineColor: Cesium.Color.fromCssColorString(accentCss).withAlpha(0.92),
        lineWidth: ratio >= 0.75 ? 2.8 : ratio >= 0.45 ? 2.3 : 1.9,
      }
      return memo
    }, {})
  }

  function regionalAdminPreviewLabel(record, options = {}) {
    const score = numericMetricValue(options.score)
    const rounded = score == null ? "—" : Math.round(score)
    const sectorLabel = options.sectorLabel && options.sectorLabel !== "All" ? options.sectorLabel : null
    return `${record.name || "Admin area"}\n${sectorLabel || "Signal"} ${rounded}`
  }

  function regionalAreaMetricLabel(record, metricConfig, value) {
    const label = metricConfig?.shortLabel || metricConfig?.label || "Metric"
    return `${record.name || "Region"}\n${label} ${formatRegionalMetric(metricConfig, value)}`
  }

  function normalizeRegionalSectorValue(value) {
    return `${value || ""}`
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
  }

  function municipalitySectorKeys(profile = {}) {
    const haystack = [
      ...(Array.isArray(profile.strategic_sectors) ? profile.strategic_sectors : []),
      ...(Array.isArray(profile.role_tags) ? profile.role_tags : []),
      profile.summary,
    ].map(normalizeRegionalSectorValue).filter(Boolean)

    const matched = Object.entries(REGIONAL_SECTOR_MATCHERS).filter(([, terms]) =>
      terms.some(term => haystack.some(value => value.includes(normalizeRegionalSectorValue(term))))
    )

    return matched.map(([key]) => key)
  }

  function municipalitySectorNames(profile = {}) {
    return municipalitySectorKeys(profile).map(titleizeProfileKey)
  }

  function regionalEconomyMapLegend(view, sectorLabel = "All sectors", metricLabel = "GDP", metricSource = "Source not wired yet", metricKey = null) {
    if (view === "admin") {
      const structureMetric = metricKey === "structure_signal"
      return {
        chips: [
          renderLegendSwatch("#255f85", structureMetric ? "Lower signal" : "Lower value"),
          renderLegendSwatch(mixHexColors("#255f85", "#f59e0b", 0.52), structureMetric ? "Mid signal" : "Mid value"),
          renderLegendSwatch("#f59e0b", structureMetric ? "Higher signal" : "Higher value"),
        ],
        items: [
          structureMetric
            ? `Fill = ${sectorLabel} signal intensity from profiled cities, strategic sites, and curated power`
            : `Fill = ${metricLabel} rank across DACH region-equivalent units`,
          structureMetric
            ? "Labels = top 12 regional nodes in the current DACH sector view"
            : `Labels = top 12 regions by ${metricLabel}`,
          `Source = ${metricSource}`,
          "Click any polygon or label to open the anchored connector card",
        ],
      }
    }

    if (view === "district") {
      return {
        chips: [],
        items: [
          `District data = ${metricLabel} across official district-equivalent units`,
          `Source = ${metricSource}`,
          "Map overlay is intentionally off until official district geometry is wired",
          "Use the district list in the right panel to compare states and top districts",
        ],
      }
    }

    if (view === "country") {
      return {
        chips: [
          renderLegendSwatch("#2a6f97", "Rank 1"),
          renderLegendSwatch("#b28704", "Rank 2"),
          renderLegendSwatch("#9d4edd", "Rank 3"),
        ],
        items: [
          `Fill = ${metricLabel} rank across Germany, Austria, and Switzerland`,
          `Badges = country label plus ${metricLabel}`,
          `Source = ${metricSource}`,
          "Click a country badge or border to open the anchored connector card",
        ],
      }
    }

    return {
      chips: [],
      items: [
        "Economic overlays are hidden",
        "Use Country, Region, or District to compare the DACH baseline and subnational structure",
      ],
    }
  }

  GlobeController.prototype._initRegions = function() {
    this._activeRegion ||= null
    this._preRegionState ||= null
    this._renderRegionDropdown()
    this._renderRegionIndicator()
    this._renderLocalProfile?.()
  }

  GlobeController.prototype._regionalEconomyRegion = function() {
    const localRegion = this._localProfileRegion?.()
    if (localRegion?.mode === "economic") return localRegion

    if (this._activeRegion?.mode === "economic") return this._activeRegion

    return null
  }

  GlobeController.prototype._regionalEconomyMapView = function(region = this._regionalEconomyRegion?.()) {
    if (!region || region.mode !== "economic") return "off"

    if (!this._hasActiveLocalProfile?.() || this._localProfileRegion?.()?.key !== region.key) {
      return "country"
    }

    return ["admin", "district", "country", "off"].includes(this._regionalEconomyMapViewSelection)
      ? this._regionalEconomyMapViewSelection
      : "admin"
  }

  GlobeController.prototype._regionalEconomyGranularityKey = function(region = this._regionalEconomyRegion?.()) {
    const view = this._regionalEconomyMapView?.(region)
    if (view === "country") return "country"
    if (view === "admin") return "region"
    if (view === "district") return "district"
    return "normal"
  }

  GlobeController.prototype._regionalEconomyMetricOptionsForGranularity = function(region = this._regionalEconomyRegion?.(), granularityKey = this._regionalEconomyGranularityKey?.(region)) {
    return regionalMetricOptions(region || {}, granularityKey)
  }

  GlobeController.prototype._regionalEconomyMetricOptions = function(region = this._regionalEconomyRegion?.()) {
    return this._regionalEconomyMetricOptionsForGranularity?.(region, this._regionalEconomyGranularityKey?.(region))
  }

  GlobeController.prototype._regionalEconomyMetricKeyForGranularity = function(region = this._regionalEconomyRegion?.(), granularityKey = this._regionalEconomyGranularityKey?.(region)) {
    const options = this._regionalEconomyMetricOptionsForGranularity?.(region, granularityKey)
    const allowedKeys = options.map(metric => metric.key)
    if (allowedKeys.includes(this._regionalEconomyMetricSelection)) return this._regionalEconomyMetricSelection

    return defaultRegionalMetricKey(region || {}, granularityKey)
  }

  GlobeController.prototype._regionalEconomyMetricKey = function(region = this._regionalEconomyRegion?.()) {
    return this._regionalEconomyMetricKeyForGranularity?.(region, this._regionalEconomyGranularityKey?.(region))
  }

  GlobeController.prototype._regionalEconomyMetricConfigForGranularity = function(region = this._regionalEconomyRegion?.(), granularityKey = this._regionalEconomyGranularityKey?.(region)) {
    return regionalMetricConfig(this._regionalEconomyMetricKeyForGranularity?.(region, granularityKey))
  }

  GlobeController.prototype._regionalEconomyMetricConfig = function(region = this._regionalEconomyRegion?.()) {
    return this._regionalEconomyMetricConfigForGranularity?.(region, this._regionalEconomyGranularityKey?.(region))
  }

  GlobeController.prototype._regionalEconomyMetricValueForGranularity = function(record, region = this._regionalEconomyRegion?.(), granularityKey = this._regionalEconomyGranularityKey?.(region)) {
    return regionalMetricValue(record, this._regionalEconomyMetricKeyForGranularity?.(region, granularityKey))
  }

  GlobeController.prototype._regionalEconomyMetricValue = function(record, region = this._regionalEconomyRegion?.()) {
    return this._regionalEconomyMetricValueForGranularity?.(record, region, this._regionalEconomyGranularityKey?.(region))
  }

  GlobeController.prototype._regionalEconomyMetricSourceSummaryForGranularity = function(region = this._regionalEconomyRegion?.(), granularityKey = this._regionalEconomyGranularityKey?.(region)) {
    return regionalMetricSourceSummary(
      region || {},
      granularityKey,
      this._regionalEconomyMetricKeyForGranularity?.(region, granularityKey)
    )
  }

  GlobeController.prototype._regionalEconomyMetricSourceSummary = function(region = this._regionalEconomyRegion?.()) {
    return this._regionalEconomyMetricSourceSummaryForGranularity?.(region, this._regionalEconomyGranularityKey?.(region))
  }

  GlobeController.prototype._regionalEconomySectorMode = function(region = this._regionalEconomyRegion?.()) {
    const allowed = regionSectorModes(region).map(mode => sectorModeKey(mode))
    return allowed.includes(this._regionalEconomySectorSelection)
      ? this._regionalEconomySectorSelection
      : "all"
  }

  GlobeController.prototype._regionalEconomySectorLabel = function(region = this._regionalEconomyRegion?.()) {
    const mode = this._regionalEconomySectorMode(region)
    const configured = regionSectorModes(region).find(item => sectorModeKey(item) === mode)
    return sectorModeLabel(configured || mode)
  }

  GlobeController.prototype._regionalAdminSelectedSectorProfile = function(record, sectorKey = this._regionalEconomySectorMode?.()) {
    const metricKey = this._regionalEconomyMetricKeyForGranularity?.(this._regionalEconomyRegion?.(), "region")
    if (metricKey !== "structure_signal") return null
    if (!record || !Array.isArray(record.sector_profiles) || sectorKey === "all") return null
    return record.sector_profiles.find(profile => profile?.sector_key === sectorKey) || null
  }

  GlobeController.prototype._regionalAdminDisplayScore = function(record, sectorKey = this._regionalEconomySectorMode?.()) {
    const metricKey = this._regionalEconomyMetricKeyForGranularity?.(this._regionalEconomyRegion?.(), "region")
    if (metricKey && metricKey !== "structure_signal") return regionalMetricValue(record, metricKey)

    const profile = this._regionalAdminSelectedSectorProfile?.(record, sectorKey)
    if (sectorKey && sectorKey !== "all") return numericMetricValue(profile?.score) || 0
    if (profile) return numericMetricValue(profile.score)
    return metricValue(record, "preview_score")
  }

  GlobeController.prototype._regionalAdminRankedRecords = function(sectorKey = this._regionalEconomySectorMode?.()) {
    const records = Array.isArray(this._localProfileRegionalAdminCatalog) ? this._localProfileRegionalAdminCatalog : []
    return records
      .slice()
      .sort((left, right) =>
        (this._regionalAdminDisplayScore?.(right, sectorKey) || 0) - (this._regionalAdminDisplayScore?.(left, sectorKey) || 0) ||
        (left.country_name || "").localeCompare(right.country_name || "") ||
        (left.name || "").localeCompare(right.name || "")
      )
  }

  GlobeController.prototype._regionalAdminRankForRecord = function(record, sectorKey = this._regionalEconomySectorMode?.()) {
    if (!record?.id) return null
    const ranked = this._regionalAdminRankedRecords?.(sectorKey)
    const index = ranked.findIndex(item => item?.id === record.id)
    if (index < 0) return null
    return { rank: index + 1, total: ranked.length }
  }

  GlobeController.prototype._regionalEconomyAccent = function(record) {
    return this._regionalEconomyBorderStyles?.[record?.country_name]?.accentCss || "#b28704"
  }

  GlobeController.prototype._regionalEconomyCoordinates = function(record) {
    const code = `${record?.country_code_alpha3 || record?.country_code || ""}`.toUpperCase()
    const centroid = COUNTRY_CENTROIDS[code]
    if (!Array.isArray(centroid) || centroid.length < 2) return null

    const [lat, lng] = centroid
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null

    return { lat, lng, height: 1200000 }
  }

  GlobeController.prototype._regionalEconomyRecordForCountry = function(countryName) {
    if (!countryName || !Array.isArray(this._regionalIndicatorMapData)) return null

    return this._regionalIndicatorMapData.find(record =>
      `${record?.country_name || ""}`.toLowerCase() === `${countryName}`.toLowerCase()
    ) || null
  }

  GlobeController.prototype.showRegionalIndicatorCountry = function(countryName, options = {}) {
    const region = this._regionalEconomyRegion?.()
    if (!region) return false
    if (this._regionalEconomyMapView?.(region) === "off") return false

    const record = this._regionalEconomyRecordForCountry?.(countryName)
    if (!record) return false

    this.showRegionalIndicatorDetail?.(record, options)
    return true
  }

  GlobeController.prototype._buildRegionalEconomyContext = function(record) {
    if (!record) return null

    const region = this._regionalEconomyRegion?.()
    const metricConfig = this._regionalEconomyMetricConfig?.(region)
    const selectedMetricValue = this._regionalEconomyMetricValue?.(record, region)
    const metricSourceSummary = this._regionalEconomyMetricSourceSummary?.(region)
    const coordinates = this._regionalEconomyCoordinates(record)
    const sourceLabel = [record.source_name, record.latest_year].filter(Boolean).join(" · ")
    const topSectorItems = Array.isArray(record.top_sectors)
      ? record.top_sectors
        .slice(0, 3)
        .filter(sector => sector?.sector_name)
        .map(sector => ({
          label: sector.sector_name,
          meta: sector.share_pct != null ? `${formatPercent(sector.share_pct)} share` : "Sector mix",
        }))
      : []

    return {
      kind: "regional_economy",
      severity: "low",
      statusLabel: "baseline",
      icon: "fa-chart-column",
      accentColor: this._regionalEconomyAccent(record),
      eyebrow: "REGIONAL ECONOMY",
      title: record.country_name || record.country_code_alpha3 || "Regional economy",
      subtitle: sourceLabel || "Economic baseline",
      summary: [
        `${metricConfig?.label || "Metric"} ${formatRegionalMetric(metricConfig, selectedMetricValue)}`,
        `GDP / capita ${formatCompactCurrency(metricValue(record, "gdp_per_capita_usd"))}`,
        `Energy dep. ${formatPercent(metricValue(record, "energy_imports_net_pct_energy_use"))}`,
      ].join(" · "),
      meta: [
        record.country_code_alpha3 ? { label: "Code", value: record.country_code_alpha3 } : null,
        { label: metricConfig?.shortLabel || "Metric", value: formatRegionalMetric(metricConfig, selectedMetricValue) },
        { label: "Source", value: metricSourceSummary || sourceLabel || "—" },
        { label: "GDP", value: formatCompactCurrency(metricValue(record, "gdp_nominal_usd")) },
        { label: "Population", value: formatCompactNumber(metricValue(record, "population_total")) },
      ].filter(Boolean),
      coordinates,
      actions: coordinates ? [
        { label: "Focus map", lat: coordinates.lat, lng: coordinates.lng, height: coordinates.height, icon: "fa-location-crosshairs" },
      ] : [],
      sections: [
        {
          title: "Economic snapshot",
          rows: [
            { label: metricConfig?.label || "Selected Metric", value: formatRegionalMetric(metricConfig, selectedMetricValue) },
            { label: "Metric Source", value: metricSourceSummary || sourceLabel || "—" },
            { label: "GDP", value: formatCompactCurrency(metricValue(record, "gdp_nominal_usd")) },
            { label: "GDP / Capita", value: formatCompactCurrency(metricValue(record, "gdp_per_capita_usd")) },
            { label: "Population", value: formatCompactNumber(metricValue(record, "population_total")) },
            { label: "Manufacturing Share", value: formatPercent(metricValue(record, "manufacturing_share_pct")) },
            { label: "Exports / GDP", value: formatPercent(metricValue(record, "exports_goods_services_pct_gdp")) },
            { label: "Energy Imports", value: formatPercent(metricValue(record, "energy_imports_net_pct_energy_use")) },
          ],
        },
        topSectorItems.length ? {
          title: "Top sectors",
          items: topSectorItems,
        } : null,
      ].filter(Boolean),
    }
  }

  GlobeController.prototype._regionalAdminEconomyEnabled = function(region = this._regionalEconomyRegion?.()) {
    return !!(
      region &&
      region.mode === "economic" &&
      this._hasActiveLocalProfile?.() &&
      this._localProfileRegion?.()?.key === region.key &&
      this._regionalEconomyMapView?.(region) === "admin"
    )
  }

  GlobeController.prototype._regionalMunicipalityEconomyEnabled = function(region = this._regionalEconomyRegion?.()) {
    return !!(
      region &&
      region.mode === "economic" &&
      this._hasActiveLocalProfile?.() &&
      this._localProfileRegion?.()?.key === region.key &&
      this._regionalEconomyMapView?.(region) === "municipality"
    )
  }

  GlobeController.prototype._regionalCountryEconomyEnabled = function(region = this._regionalEconomyRegion?.()) {
    return !!(region && region.mode === "economic" && this._regionalEconomyMapView?.(region) === "country")
  }

  GlobeController.prototype._regionalAdminEconomyAccent = function(record) {
    const records = Array.isArray(this._localProfileRegionalAdminCatalog) && this._localProfileRegionalAdminCatalog.length > 0
      ? this._localProfileRegionalAdminCatalog
      : [record]
    const styles = regionalAdminPreviewStyles(records, entry => this._regionalAdminDisplayScore?.(entry))
    return styles[record?.id]?.accentCss || "#2f7ea7"
  }

  GlobeController.prototype._regionalAdminCoordinates = function(record) {
    const lat = numericMetricValue(record?.lat)
    const lng = numericMetricValue(record?.lng)
    if (lat == null || lng == null) return null

    return { lat, lng, height: 450000 }
  }

  GlobeController.prototype._regionalAdminRecordForEntityId = function(entityId) {
    if (!entityId || !(this._regionalAdminEconomyIndex instanceof Map)) return null
    return this._regionalAdminEconomyIndex.get(entityId) || null
  }

  GlobeController.prototype._regionalMunicipalityRecords = function(region = this._localProfileRegion?.()) {
    const countryNames = new Set(region?.countries || [])
    return Array.isArray(this._localProfileCityProfiles)
      ? this._localProfileCityProfiles.filter(profile => countryNames.has(profile.country_name))
      : []
  }

  GlobeController.prototype._regionalMunicipalityCoordinates = function(profile) {
    const lat = numericMetricValue(profile?.lat)
    const lng = numericMetricValue(profile?.lng)
    if (lat == null || lng == null) return null
    return { lat, lng, height: 180000 }
  }

  GlobeController.prototype._regionalMunicipalitySelectedSectorKeys = function(profile, sectorKey = this._regionalEconomySectorMode?.()) {
    const keys = municipalitySectorKeys(profile)
    if (sectorKey && sectorKey !== "all") return keys.filter(key => key === sectorKey)
    return keys
  }

  GlobeController.prototype._regionalMunicipalityDisplayScore = function(profile, sectorKey = this._regionalEconomySectorMode?.()) {
    const priority = numericMetricValue(profile?.priority) || 100
    const baseScore = clampNumber(110 - priority, 12, 100)
    const sectorMatches = this._regionalMunicipalitySelectedSectorKeys?.(profile, sectorKey)
    if (sectorKey && sectorKey !== "all") {
      return sectorMatches.length > 0 ? clampNumber(baseScore + (sectorMatches.length * 8), 16, 100) : 0
    }

    const roleBonus = Array.isArray(profile?.role_tags) && profile.role_tags.some(tag => ["capital", "state_capital"].includes(tag))
      ? 12
      : 0
    const sectorBonus = municipalitySectorKeys(profile).length * 4
    return clampNumber(baseScore + roleBonus + sectorBonus, 16, 100)
  }

  GlobeController.prototype._regionalMunicipalityAccent = function(profile, sectorKey = this._regionalEconomySectorMode?.()) {
    const ratio = clampNumber((this._regionalMunicipalityDisplayScore?.(profile, sectorKey) || 0) / 100.0, 0, 1)
    return mixHexColors("#2a6f97", "#f59e0b", ratio)
  }

  GlobeController.prototype._regionalMunicipalityRecordForEntityId = function(entityId) {
    if (!entityId || !(this._regionalMunicipalityIndex instanceof Map)) return null
    return this._regionalMunicipalityIndex.get(entityId) || null
  }

  GlobeController.prototype._regionalMunicipalityBoundaryFeatureForProfile = function(profile) {
    const profileId = `${profile?.id || ""}`
    if (!profileId || !(this._regionalMunicipalityBoundaryIndex instanceof Map)) return null
    return this._regionalMunicipalityBoundaryIndex.get(profileId) || null
  }

  GlobeController.prototype._buildRegionalAdminEconomyContext = function(record) {
    if (!record) return null

    const coordinates = this._regionalAdminCoordinates(record)
    const sectorKey = this._regionalEconomySectorMode?.()
    const sectorLabel = this._regionalEconomySectorLabel?.()
    const selectedSector = this._regionalAdminSelectedSectorProfile?.(record, sectorKey)
    const rank = this._regionalAdminRankForRecord?.(record, sectorKey)
    const sourceModels = Array.isArray(record.source_models) ? record.source_models.map(titleizeProfileKey) : []
    const sourcePacks = Array.isArray(record.source_packs) ? record.source_packs : []
    const topSectors = Array.isArray(record.top_sectors) ? record.top_sectors.slice(0, 4) : []
    const topNodes = Array.isArray(record.top_nodes) ? record.top_nodes.slice(0, 6) : []
    const selectedSignalCount = selectedSector?.signal_count
    const selectedSites = selectedSector?.strategic_site_count
    const selectedCities = selectedSector?.city_signal_count
    const selectedNodes = selectedSector?.node_count

    return {
      kind: "regional_admin_economy",
      severity: "low",
      statusLabel: sectorKey === "all" ? "structure" : "sector",
      icon: "fa-chart-area",
      accentColor: this._regionalAdminEconomyAccent(record),
      eyebrow: sectorKey === "all" ? "ADMIN AREA STRUCTURE" : `${sectorLabel.toUpperCase()} SIGNAL`,
      title: record.name || "Admin area",
      subtitle: [record.country_name, sectorKey === "all" ? "Derived industrial structure" : `${sectorLabel} focus`].filter(Boolean).join(" · "),
      summary: [
        rank ? `Rank ${rank.rank} of ${rank.total} in DACH` : null,
        selectedSector
          ? `${sectorLabel} · ${formatCompactNumber(selectedSignalCount)} signals`
          : (sectorKey === "all" ? (record.summary || "No profiled enrichment yet") : `No ${sectorLabel.toLowerCase()} signal in current packs`),
        selectedSector && selectedNodes != null ? `${formatCompactNumber(selectedNodes)} nodes` : null,
      ].filter(Boolean).join(" · "),
      meta: [
        record.country_code_alpha3 ? { label: "Code", value: record.country_code_alpha3 } : null,
        selectedSector
          ? { label: "Sector Nodes", value: formatCompactNumber(selectedNodes) }
          : { label: "Cities", value: formatCompactNumber(metricValue(record, "city_count")) },
        selectedSector
          ? { label: "Sector Sites", value: formatCompactNumber(selectedSites) }
          : { label: "Sites", value: formatCompactNumber(metricValue(record, "strategic_site_count")) },
        { label: "Power", value: `${DECIMAL_FORMAT.format((metricValue(record, "curated_power_capacity_mw") || 0) / 1000)} GW` },
      ].filter(Boolean),
      coordinates,
      actions: coordinates ? [
        { label: "Focus map", lat: coordinates.lat, lng: coordinates.lng, height: coordinates.height, icon: "fa-location-crosshairs" },
      ] : [],
      sections: [
        {
          title: selectedSector ? `${sectorLabel} focus` : "Structure footprint",
          rows: [
            rank ? { label: "DACH Rank", value: `${rank.rank} / ${rank.total}` } : null,
            { label: selectedSector ? `${sectorLabel} Score` : "Overall Signal", value: formatCompactNumber(this._regionalAdminDisplayScore?.(record, sectorKey)) },
            { label: selectedSector ? `${sectorLabel} City Signals` : "Profiled Cities", value: formatCompactNumber(selectedSector ? selectedCities : metricValue(record, "city_count")) },
            { label: selectedSector ? `${sectorLabel} Site Signals` : "Strategic Sites", value: formatCompactNumber(selectedSector ? selectedSites : metricValue(record, "strategic_site_count")) },
            { label: "Curated Power Plants", value: formatCompactNumber(metricValue(record, "curated_power_plant_count")) },
            { label: "Curated Power Capacity", value: `${DECIMAL_FORMAT.format((metricValue(record, "curated_power_capacity_mw") || 0) / 1000)} GW` },
            { label: "Sector Diversity", value: formatCompactNumber(metricValue(record, "sector_diversity_count")) },
          ].filter(Boolean),
        },
        topSectors.length ? {
          title: "Sector mix",
          items: topSectors.map(profile => ({
            label: profile.sector_name,
            meta: `${formatCompactNumber(profile.signal_count)} signals · ${formatCompactNumber(profile.node_count)} nodes`,
          })),
        } : null,
        topNodes.length ? {
          title: "Leading nodes",
          items: topNodes.map(node => ({
            label: node.name,
            meta: [
              titleizeProfileKey(node.node_kind),
              Array.isArray(node.sector_names) ? node.sector_names.slice(0, 2).join(" · ") : null,
            ].filter(Boolean).join(" · "),
          })),
        } : null,
        sourceModels.length || sourcePacks.length ? {
          title: "Sources",
          items: [
            sourceModels.length ? {
              label: "Source models",
              meta: sourceModels.join(" · "),
            } : null,
            sourcePacks.length ? {
              label: "Source packs",
              meta: sourcePacks.slice(0, 4).join(" · "),
            } : null,
          ].filter(Boolean),
        } : null,
      ].filter(Boolean),
    }
  }

  GlobeController.prototype._buildRegionalAreaMetricContext = function(record) {
    if (!record) return null

    const region = this._regionalEconomyRegion?.()
    const metricConfig = this._regionalEconomyMetricConfigForGranularity?.(region, "region")
    const metricValueForRecord = this._regionalEconomyMetricValueForGranularity?.(record, region, "region")
    const metricSourceSummary = this._regionalEconomyMetricSourceSummaryForGranularity?.(region, "region")
    const coordinates = this._regionalAdminCoordinates(record)
    const rank = this._regionalAdminRankForRecord?.(record, "all")
    const nativeLevelLabel = titleizeProfileKey(record?.native_level || "region")
    const sourceLabel = [
      record.source_name,
      record.source_dataset,
      record.latest_year,
      nativeLevelLabel,
    ].filter(Boolean).join(" · ")

    return {
      kind: "regional_area_metric",
      severity: "low",
      statusLabel: "region",
      icon: "fa-chart-area",
      accentColor: this._regionalAdminEconomyAccent(record),
      eyebrow: "REGIONAL METRIC",
      title: record.name || "Region",
      subtitle: [record.country_name, nativeLevelLabel].filter(Boolean).join(" · "),
      summary: [
        rank ? `Rank ${rank.rank} of ${rank.total} in DACH` : null,
        `${metricConfig?.label || "Metric"} ${formatRegionalMetric(metricConfig, metricValueForRecord)}`,
        metricSourceSummary || sourceLabel || null,
      ].filter(Boolean).join(" · "),
      meta: [
        record.country_code_alpha3 ? { label: "Code", value: record.country_code_alpha3 } : null,
        { label: metricConfig?.shortLabel || "Metric", value: formatRegionalMetric(metricConfig, metricValueForRecord) },
        { label: "Source", value: metricSourceSummary || sourceLabel || "—" },
        { label: "Level", value: nativeLevelLabel },
      ].filter(Boolean),
      coordinates,
      actions: coordinates ? [
        { label: "Focus map", lat: coordinates.lat, lng: coordinates.lng, height: coordinates.height, icon: "fa-location-crosshairs" },
      ] : [],
      sections: [
        {
          title: "Metric snapshot",
          rows: [
            rank ? { label: "DACH Rank", value: `${rank.rank} / ${rank.total}` } : null,
            { label: metricConfig?.label || "Metric", value: formatRegionalMetric(metricConfig, metricValueForRecord) },
            { label: "Latest Year", value: record.latest_year ? `${record.latest_year}` : "—" },
            { label: "Native Level", value: nativeLevelLabel },
            { label: "Source", value: metricSourceSummary || sourceLabel || "—" },
          ].filter(Boolean),
        },
      ],
    }
  }

  GlobeController.prototype._buildRegionalMunicipalityContext = function(profile) {
    if (!profile) return null

    const sectorKey = this._regionalEconomySectorMode?.()
    const sectorLabel = this._regionalEconomySectorLabel?.()
    const coordinates = this._regionalMunicipalityCoordinates(profile)
    const allSectorNames = municipalitySectorNames(profile)
    const selectedSectorNames = this._regionalMunicipalitySelectedSectorKeys?.(profile, sectorKey).map(titleizeProfileKey)
    const activeSectorNames = sectorKey === "all" ? allSectorNames : selectedSectorNames
    const signalScore = this._regionalMunicipalityDisplayScore?.(profile, sectorKey)

    return {
      kind: "regional_municipality",
      severity: "low",
      statusLabel: "municipality",
      icon: "fa-city",
      accentColor: this._regionalMunicipalityAccent(profile, sectorKey),
      eyebrow: "MUNICIPAL STRUCTURE",
      title: profile.name || "Municipality",
      subtitle: [profile.admin_area, profile.country_name].filter(Boolean).join(" · "),
      summary: [
        sectorKey === "all" ? "Municipal node" : `${sectorLabel} focus`,
        signalScore ? `Signal ${Math.round(signalScore)}` : null,
        activeSectorNames.length ? activeSectorNames.slice(0, 2).join(" · ") : "No tagged sector yet",
      ].filter(Boolean).join(" · "),
      meta: [
        { label: "Country", value: profile.country_name || profile.country_code || "—" },
        profile.admin_area ? { label: "Region", value: profile.admin_area } : null,
        profile.priority != null ? { label: "Priority", value: `${profile.priority}` } : null,
      ].filter(Boolean),
      coordinates,
      actions: coordinates ? [
        { label: "Focus map", lat: coordinates.lat, lng: coordinates.lng, height: coordinates.height, icon: "fa-location-crosshairs" },
      ] : [],
      sections: [
        {
          title: "Municipal profile",
          rows: [
            { label: "Signal", value: formatCompactNumber(signalScore) },
            { label: "Sector Focus", value: sectorKey === "all" ? "All sectors" : sectorLabel },
            { label: "Tagged Sectors", value: allSectorNames.length ? allSectorNames.slice(0, 4).join(" · ") : "—" },
            { label: "Roles", value: Array.isArray(profile.role_tags) && profile.role_tags.length > 0 ? profile.role_tags.map(titleizeProfileKey).join(" · ") : "—" },
          ],
        },
        profile.summary ? {
          title: "Summary",
          rows: [{ label: "Profile", value: profile.summary }],
        } : null,
      ].filter(Boolean),
    }
  }

  GlobeController.prototype.showRegionalAdminDetail = function(record, options = {}) {
    if (!record) return

    const region = this._regionalEconomyRegion?.()
    const metricConfig = this._regionalEconomyMetricConfigForGranularity?.(region, "region")
    const structureMetric = metricConfig?.key === "structure_signal"
    const coordinates = this._regionalAdminCoordinates(record)
    const sectorKey = this._regionalEconomySectorMode?.()
    const sectorLabel = this._regionalEconomySectorLabel?.()
    const selectedSector = this._regionalAdminSelectedSectorProfile?.(record, sectorKey)
    const rank = this._regionalAdminRankForRecord?.(record, sectorKey)
    const selectedMetricValue = this._regionalEconomyMetricValueForGranularity?.(record, region, "region")
    const selectedMetricSource = this._regionalEconomyMetricSourceSummaryForGranularity?.(region, "region")
    const anchoredRecord = coordinates
      ? {
          ...record,
          lat: coordinates.lat,
          lng: coordinates.lng,
          accent_color: this._regionalAdminEconomyAccent(record),
          selected_sector_key: sectorKey,
          selected_sector_label: sectorLabel,
          selected_sector_profile: selectedSector,
          selected_rank: rank,
          selected_metric_key: metricConfig?.key,
          selected_metric_label: metricConfig?.label,
          selected_metric_short_label: metricConfig?.shortLabel,
          selected_metric_value: selectedMetricValue,
          selected_metric_source: selectedMetricSource,
        }
      : {
          ...record,
          accent_color: this._regionalAdminEconomyAccent(record),
          selected_sector_key: sectorKey,
          selected_sector_label: sectorLabel,
          selected_sector_profile: selectedSector,
          selected_rank: rank,
          selected_metric_key: metricConfig?.key,
          selected_metric_label: metricConfig?.label,
          selected_metric_short_label: metricConfig?.shortLabel,
          selected_metric_value: selectedMetricValue,
          selected_metric_source: selectedMetricSource,
        }

    if (!options.contextOnly && this._showCompactEntityDetail) {
      this._showCompactEntityDetail(structureMetric ? "regional_admin_economy" : "regional_area_metric", anchoredRecord, {
        id: record.id || record.name,
        picked: options.picked,
      })
    }

    const context = structureMetric
      ? this._buildRegionalAdminEconomyContext?.(record)
      : this._buildRegionalAreaMetricContext?.(record)
    if (context && this._setSelectedContext) {
      this._setSelectedContext(context, {
        openRightPanel: options.openRightPanel === true || this._currentRightPanelTab?.() === "context",
      })
    }

    if (this.hasDetailPanelTarget) this.detailPanelTarget.style.display = "none"
  }

  GlobeController.prototype.setRegionalEconomyMapView = function(event) {
    event?.preventDefault?.()
    const view = event?.currentTarget?.dataset?.mapView
    if (!["admin", "district", "country", "off"].includes(view)) return

    const panel = this.hasLocalProfilePanelTarget ? this.localProfilePanelTarget : null
    const scrollTop = panel?.scrollTop || 0
    this._regionalEconomyMapViewSelection = view
    this._syncRegionalEconomyMap?.()
    this._renderLocalProfile?.()
    if (panel) panel.scrollTop = scrollTop
    this._requestRender?.()
  }

  GlobeController.prototype.setRegionalEconomySectorFocus = function(event) {
    event?.preventDefault?.()
    const region = this._regionalEconomyRegion?.()
    const sectorKey = event?.currentTarget?.dataset?.sectorKey
    const allowed = regionSectorModes(region).map(mode => sectorModeKey(mode))
    if (!allowed.includes(sectorKey)) return

    const panel = this.hasLocalProfilePanelTarget ? this.localProfilePanelTarget : null
    const scrollTop = panel?.scrollTop || 0
    this._regionalEconomySectorSelection = sectorKey
    this._syncRegionalEconomyMap?.()
    this._renderLocalProfile?.()
    if (panel) panel.scrollTop = scrollTop
    this._requestRender?.()
  }

  GlobeController.prototype.setRegionalEconomyMetric = function(event) {
    event?.preventDefault?.()
    const region = this._regionalEconomyRegion?.()
    const metricKey = event?.currentTarget?.dataset?.metricKey
    const allowed = this._regionalEconomyMetricOptions?.(region).map(metric => metric.key)
    if (!allowed.includes(metricKey)) return

    const panel = this.hasLocalProfilePanelTarget ? this.localProfilePanelTarget : null
    const scrollTop = panel?.scrollTop || 0
    this._regionalEconomyMetricSelection = metricKey
    this._syncRegionalEconomyMap?.()
    this._renderLocalProfile?.()
    if (panel) panel.scrollTop = scrollTop
    this._requestRender?.()
  }

  GlobeController.prototype.enterRegion = function(regionKey) {
    const region = REGION_MAP[regionKey]
    if (!region) return

    // Snapshot current state for restore on exit
    if (!this._activeRegion) {
      this._preRegionState = this._buildWorkspacePayload("__snapshot__")
    }

    // Clear all current layers
    this._clearAllLayers()

    // Set active region
    if (this._activeLocalProfileKey && this._activeLocalProfileKey !== region.key) {
      this._activeLocalProfileKey = null
    }
    this._activeRegion = region
    this.setCountrySelection?.(region.countries || [], {
      refresh: false,
      showBorders: regionDefaultLayers(region).includes("borders"),
      useHull: false,
    })

    // Fly camera to region — offset south so the tilted view centers on the region.
    // When pitch is not straight-down, the camera looks north of its position,
    // so we shift the camera south proportional to height and tilt angle.
    const Cesium = window.Cesium
    if (Cesium && this.viewer) {
      const center = regionCameraCenter(region)
      const height = regionCameraHeight(region)
      const pitch = region.camera?.pitch || -Cesium.Math.PI_OVER_TWO
      const tiltFromDown = Math.abs(pitch + Math.PI / 2) // 0 = straight down, ~0.7 = 45°
      const heightKm = height / 1000
      // Degrees-lat offset: sqrt of height keeps it sane at high altitudes
      const latOffset = tiltFromDown * Math.sqrt(heightKm) * 0.25
      const camLat = center.lat - latOffset

      this.viewer.camera.flyTo({
        destination: Cesium.Cartesian3.fromDegrees(
          center.lng, camLat, height
        ),
        orientation: {
          heading: region.camera?.heading || 0,
          pitch: pitch,
          roll: 0,
        },
        duration: 2.0,
      })
    }

    // Enable region layers via applyDeepLink (reuses existing toggle logic)
    const state = {
      layers: regionDefaultLayers(region),
      satCategories: region.satCategories || [],
    }

    // Region presets should preserve the old "full picture" behavior even now that
    // civilian and military feeds are split into separate toggles.
    if (state.layers.includes("flights") && !state.layers.includes("militaryFlights")) {
      state.layers.push("militaryFlights")
      state.showMilitary = true
      state.showCivilian = true
    }
    if (state.layers.includes("ships") && !state.layers.includes("navalVessels")) {
      state.layers.push("navalVessels")
    }

    applyDeepLink(this, state)

    // Update UI
    this._renderRegionIndicator()
    this._renderLocalProfile?.()
    this._loadRegionalEconomyMap?.(region)
    this._syncQuickBar()
    this._savePrefs()

    // Sync dropdown
    const select = document.getElementById("region-select")
    if (select) select.value = regionKey
  }

  GlobeController.prototype.exitRegion = function() {
    if (!this._activeRegion) return
    this._activeRegion = null
    this._activeLocalProfileKey = null
    this._regionalEconomyMapViewSelection = "country"
    this._regionalEconomySectorSelection = "all"
    this._regionalIndicatorMapData = []
    this._clearRegionalEconomyMap?.()
    this._clearRegionalAdminEconomyMap?.()
    this._clearRegionalMunicipalityMap?.()

    // Restore previous state or go to global default
    if (this._preRegionState) {
      this._clearAllLayers()
      this.setCountrySelection?.([], { refresh: false })

      const state = { camera: {} }
      const pre = this._preRegionState
      if (pre.camera_lat != null) {
        state.camera = {
          lat: pre.camera_lat,
          lng: pre.camera_lng,
          height: pre.camera_height || 20000000,
          heading: pre.camera_heading || 0,
          pitch: pre.camera_pitch || -Math.PI / 2,
        }
      }

      // Rebuild layer list from saved state
      if (pre.layers) {
        state.layers = Object.entries(pre.layers)
          .filter(([k, v]) => v === true && k !== "showCivilian" && k !== "showMilitary" && k !== "terrain")
          .map(([k]) => k)
        if (pre.layers.terrain) state.layers.push("terrain")
        state.showCivilian = pre.layers.showCivilian
        state.showMilitary = pre.layers.showMilitary
        if (pre.layers.satCategories) {
          state.satCategories = Object.entries(pre.layers.satCategories)
            .filter(([, v]) => v)
            .map(([k]) => k)
        }
      }
      if (pre.filters?.selected_countries?.length > 0) {
        state.countries = pre.filters.selected_countries
      }

      applyDeepLink(this, state)
      this._preRegionState = null
    } else {
      this._clearAllLayers()
      this.setCountrySelection?.([], { refresh: false })
      const Cesium = window.Cesium
      if (Cesium && this.viewer) {
        this.viewer.camera.flyTo({
          destination: Cesium.Cartesian3.fromDegrees(10, 30, 20000000),
          duration: 1.5,
        })
      }
    }

    this._renderRegionIndicator()
    this._renderLocalProfile?.()
    this._syncQuickBar()
    this._savePrefs()

    // Reset dropdown
    const select = document.getElementById("region-select")
    if (select) select.value = ""
  }

  GlobeController.prototype.selectRegion = function(event) {
    const key = event.target.value
    if (key) {
      this.enterRegion(key)
    } else {
      this.exitRegion()
    }
  }

  GlobeController.prototype._renderRegionDropdown = function() {
    const select = document.getElementById("region-select")
    if (!select) return

    // Build optgroups
    let html = '<option value="">Select Region</option>'
    for (const group of REGION_GROUPS) {
      const regions = REGIONS.filter(r => r.group === group)
      html += `<optgroup label="${group}">`
      for (const r of regions) {
        html += `<option value="${r.key}">${r.name}</option>`
      }
      html += '</optgroup>'
    }
    select.innerHTML = html
  }

  GlobeController.prototype._renderRegionIndicator = function() {
    const indicator = document.getElementById("region-indicator")
    if (!indicator) return

    if (this._activeRegion) {
      const bar = document.createElement("div")
      bar.className = "region-active-bar"

      const badge = document.createElement("span")
      badge.className = "region-badge"
      badge.textContent = this._activeRegion.name
      bar.appendChild(badge)

      const desc = document.createElement("span")
      desc.className = "region-desc"
      desc.textContent = this._activeRegion.description
      bar.appendChild(desc)

      if (this.signedInValue) {
        const payload = this._buildAreaWorkspacePayload()
        if (payload && this._buildAreaWorkspaceForm) {
          bar.appendChild(this._buildAreaWorkspaceForm(payload, {
            formClass: "region-track-form",
            submitClass: "region-track-btn",
            submitLabel: "Track Area",
            submitTitle: "Track area",
          }))
        }
      } else {
        const link = document.createElement("a")
        link.className = "region-track-btn"
        link.href = "/users/sign_in"
        link.textContent = "Sign In"
        bar.appendChild(link)
      }

      const localBtn = document.createElement("button")
      localBtn.type = "button"
      localBtn.className = "region-local-btn"
      localBtn.textContent = "Local View"
      localBtn.addEventListener("click", event => {
        event.preventDefault()
        this.openLocalProfile?.(this._activeRegion?.key)
      })
      bar.appendChild(localBtn)

      const exitBtn = document.createElement("button")
      exitBtn.type = "button"
      exitBtn.className = "region-exit-btn"
      exitBtn.title = "Exit region"
      exitBtn.textContent = "\u00d7"
      exitBtn.addEventListener("click", event => {
        event.preventDefault()
        this.exitRegion()
      })
      bar.appendChild(exitBtn)

      indicator.replaceChildren(bar)

      indicator.style.display = ""
    } else {
      indicator.innerHTML = ""
      indicator.style.display = "none"
    }
  }

  GlobeController.prototype._hasActiveLocalProfile = function() {
    return !!(this._activeLocalProfileKey && this._activeRegion?.key === this._activeLocalProfileKey)
  }

  GlobeController.prototype._localProfileRegion = function() {
    return this._hasActiveLocalProfile() ? REGION_MAP[this._activeLocalProfileKey] : null
  }

  GlobeController.prototype.openDachLocalProfile = function(event) {
    event?.preventDefault?.()
    this.openLocalProfile("dach")
  }

  GlobeController.prototype.openLocalProfile = function(regionKey = this._activeRegion?.key) {
    const targetKey = regionKey || this._activeRegion?.key
    if (!targetKey) return
    const targetRegion = REGION_MAP[targetKey]

    if (this._activeRegion?.key !== targetKey) {
      this.enterRegion(targetKey)
    }

    if (targetRegion?.mode === "economic") {
      this._regionalEconomyMapViewSelection = "admin"
      this._regionalEconomySectorSelection = "all"
    }

    this._activeLocalProfileKey = targetKey
    this._renderLocalProfile()
    this._syncRegionalEconomyMap?.()
    this._showRightPanel?.("localProfile")
    this._savePrefs()
  }

  GlobeController.prototype.closeLocalProfile = function(event) {
    event?.preventDefault?.()
    this._activeLocalProfileKey = null
    this._regionalEconomyMapViewSelection = "country"
    this._regionalEconomySectorSelection = "all"
    this._renderLocalProfile()
    this._clearRegionalAdminEconomyMap?.()
    this._clearRegionalMunicipalityMap?.()
    this._loadRegionalEconomyMap?.()
    this._syncRightPanels?.()
    this._savePrefs()
  }

  GlobeController.prototype.getRegionalEconomyDataSource = function() {
    return getDataSource(this.viewer, this._ds, "regionalEconomy")
  }

  GlobeController.prototype.getRegionalAdminEconomyDataSource = function() {
    return getDataSource(this.viewer, this._ds, "regionalAdminEconomy")
  }

  GlobeController.prototype.getRegionalMunicipalityDataSource = function() {
    return getDataSource(this.viewer, this._ds, "regionalMunicipalities")
  }

  GlobeController.prototype._clearRegionalEconomyMap = function() {
    const ds = this._ds["regionalEconomy"]
    if (ds && Array.isArray(this._regionalEconomyMapEntities)) {
      ds.entities.suspendEvents()
      this._regionalEconomyMapEntities.forEach(entity => ds.entities.remove(entity))
      ds.entities.resumeEvents()
      ds.show = false
    }
    this._regionalEconomyMapEntities = []
    this._regionalEconomyBorderStyles = null
    if (this.selectedCountries?.size > 0) this.updateBorderColors?.()
    this._requestRender?.()
  }

  GlobeController.prototype._clearRegionalAdminEconomyMap = function() {
    const ds = this._ds["regionalAdminEconomy"]
    if (ds && Array.isArray(this._regionalAdminEconomyEntities)) {
      ds.entities.suspendEvents()
      this._regionalAdminEconomyEntities.forEach(entity => ds.entities.remove(entity))
      ds.entities.resumeEvents()
      ds.show = false
    }
    this._regionalAdminEconomyEntities = []
    this._regionalAdminEconomyIndex = new Map()
    if (this.selectedCountries?.size > 0) this.updateBorderColors?.()
    this._requestRender?.()
  }

  GlobeController.prototype._clearRegionalMunicipalityMap = function() {
    const ds = this._ds["regionalMunicipalities"]
    if (ds && Array.isArray(this._regionalMunicipalityEntities)) {
      ds.entities.suspendEvents()
      this._regionalMunicipalityEntities.forEach(entity => ds.entities.remove(entity))
      ds.entities.resumeEvents()
      ds.show = false
    }
    this._regionalMunicipalityEntities = []
    this._regionalMunicipalityIndex = new Map()
    this._requestRender?.()
  }

  GlobeController.prototype._syncRegionalEconomyMap = function() {
    const region = this._regionalEconomyRegion?.()
    const view = this._regionalEconomyMapView?.(region)
    const cityDataSource = this._ds["cities"]
    if (cityDataSource) cityDataSource.show = this.citiesVisible
    if (!region) {
      this._clearRegionalEconomyMap?.()
      this._clearRegionalAdminEconomyMap?.()
      this._clearRegionalMunicipalityMap?.()
      return
    }

    if (view === "off") {
      this._clearRegionalEconomyMap?.()
      this._clearRegionalAdminEconomyMap?.()
      this._clearRegionalMunicipalityMap?.()
      return
    }

    if (this._regionalAdminEconomyEnabled?.(region)) {
      this._clearRegionalEconomyMap?.()
      this._clearRegionalMunicipalityMap?.()
      this._loadRegionalAdminEconomyMap?.(region)
      return
    }

    if (view === "district") {
      this._clearRegionalEconomyMap?.()
      this._clearRegionalAdminEconomyMap?.()
      this._clearRegionalMunicipalityMap?.()
      return
    }

    if (this._regionalMunicipalityEconomyEnabled?.(region)) {
      this._clearRegionalEconomyMap?.()
      this._clearRegionalAdminEconomyMap?.()
      this._loadRegionalMunicipalityMap?.(region)
      return
    }

    this._clearRegionalAdminEconomyMap?.()
    this._clearRegionalMunicipalityMap?.()
    if (!this.bordersVisible) {
      this._clearRegionalEconomyMap?.()
      return
    }

    this._renderRegionalEconomyMap?.(region, this._regionalIndicatorMapData)
  }

  GlobeController.prototype._ensureRegionalIndicatorRecords = async function(region) {
    const countryNames = Array.isArray(region?.countries) ? region.countries : []
    const filterKey = countryNames.join("|")

    let records = this._localProfileRegionalIndicatorCatalog
    if (!Array.isArray(records) || this._localProfileRegionalIndicatorFilterKey !== filterKey) {
      const params = new URLSearchParams()
      if (countryNames.length > 0) params.set("country_names", countryNames.join(","))

      const response = await fetch(`/api/regional_indicators?${params.toString()}`)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const payload = await response.json()
      this._localProfileRegionalIndicatorCatalog = Array.isArray(payload) ? payload : []
      this._localProfileRegionalIndicatorFilterKey = filterKey
      records = this._localProfileRegionalIndicatorCatalog
    }

    return Array.isArray(records) ? records : []
  }

  GlobeController.prototype._ensureRegionalAdminRecords = async function(region) {
    const regionKey = region?.key || ""
    const granularityKey = "region"
    const metricKey = this._regionalEconomyMetricKeyForGranularity?.(region, granularityKey)
    const cacheKey = `${regionKey}:${metricKey}`

    let records = this._localProfileRegionalAdminCatalog
    if (!Array.isArray(records) || this._localProfileRegionalAdminRegionKey !== cacheKey) {
      const endpoint = metricKey === "structure_signal"
        ? `/api/regional_admin_profiles?region_key=${encodeURIComponent(regionKey)}`
        : `/api/regional_area_indicators?region_key=${encodeURIComponent(regionKey)}&comparable_level=region`
      const response = await fetch(endpoint)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const payload = await response.json()
      this._localProfileRegionalAdminCatalog = Array.isArray(payload) ? payload : []
      this._localProfileRegionalAdminRegionKey = cacheKey
      records = this._localProfileRegionalAdminCatalog
    }

    return Array.isArray(records) ? records : []
  }

  GlobeController.prototype._ensureRegionalDistrictRecords = async function(region) {
    const regionKey = region?.key || ""
    const metricKey = this._regionalEconomyMetricKeyForGranularity?.(region, "district")
    const cacheKey = `${regionKey}:district:${metricKey}`

    let records = this._localProfileRegionalDistrictCatalog
    if (!Array.isArray(records) || this._localProfileRegionalDistrictRegionKey !== cacheKey) {
      const response = await fetch(`/api/regional_area_indicators?region_key=${encodeURIComponent(regionKey)}&comparable_level=district`)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const payload = await response.json()
      this._localProfileRegionalDistrictCatalog = Array.isArray(payload) ? payload : []
      this._localProfileRegionalDistrictRegionKey = cacheKey
      records = this._localProfileRegionalDistrictCatalog
    }

    return Array.isArray(records) ? records : []
  }

  GlobeController.prototype._ensureRegionalMunicipalityRecords = async function(region) {
    const countryCodes = Array.isArray(region?.countryCodes) ? region.countryCodes : []

    let profiles = this._localProfileCityProfiles
    if (!Array.isArray(profiles)) {
      const response = await fetch(`/api/city_profiles?country_codes=${encodeURIComponent(countryCodes.join(","))}`)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const payload = await response.json()
      this._localProfileCityProfiles = Array.isArray(payload) ? payload : []
      profiles = this._localProfileCityProfiles
    }

    const countryNames = new Set(region?.countries || [])
    return Array.isArray(profiles) ? profiles.filter(profile => countryNames.has(profile.country_name)) : []
  }

  GlobeController.prototype._ensureRegionalAdminBoundaries = async function() {
    if (Array.isArray(this._regionalAdminBoundaryCache?.features) && this._regionalAdminBoundaryCache.features.length > 0) {
      return this._regionalAdminBoundaryCache
    }

    const response = await fetch("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson")
    if (!response.ok) throw new Error(`HTTP ${response.status}`)

    const payload = await response.json()
    this._regionalAdminBoundaryCache = payload
    return payload
  }

  GlobeController.prototype._findRegionalAdminBoundaryFeature = function(record, featureCollection) {
    const features = Array.isArray(featureCollection?.features) ? featureCollection.features : Array.isArray(featureCollection) ? featureCollection : []
    if (!record || features.length === 0) return null

    const countryCode = `${record.country_code_alpha3 || ""}`.toUpperCase()
    const isoCode = `${record.iso_3166_2 || ""}`.toUpperCase()
    if (isoCode) {
      const directMatch = features.find(feature =>
        `${feature?.properties?.adm0_a3 || ""}`.toUpperCase() === countryCode &&
        `${feature?.properties?.iso_3166_2 || ""}`.toUpperCase() === isoCode
      )
      if (directMatch) return directMatch
    }

    const desiredNames = new Set(
      [record.name, ...(Array.isArray(record.boundary_names) ? record.boundary_names : [])]
        .map(normalizeRegionalBoundaryLabel)
        .filter(Boolean)
    )
    if (desiredNames.size === 0) return null

    return features.find(feature => {
      if (`${feature?.properties?.adm0_a3 || ""}`.toUpperCase() !== countryCode) return false

      const featureNames = [
        feature.properties?.name,
        feature.properties?.name_en,
        feature.properties?.woe_name,
        feature.properties?.gn_name,
        feature.properties?.name_alt,
      ]
        .flatMap(value => `${value || ""}`.split(/[|;,/]+/))
        .map(normalizeRegionalBoundaryLabel)
        .filter(Boolean)

      return featureNames.some(name => desiredNames.has(name))
    }) || null
  }

  GlobeController.prototype._loadRegionalEconomyMap = async function(region = this._regionalEconomyRegion?.()) {
    if (!region || region.mode !== "economic") {
      this._regionalIndicatorMapData = []
      this._clearRegionalEconomyMap?.()
      this._clearRegionalAdminEconomyMap?.()
      this._clearRegionalMunicipalityMap?.()
      return
    }

    const token = ++this._localProfileRegionalIndicatorFetchToken

    try {
      const records = await this._ensureRegionalIndicatorRecords(region)
      if (token !== this._localProfileRegionalIndicatorFetchToken) return

      this._regionalIndicatorMapData = records
      this._syncRegionalEconomyMap?.()
    } catch (error) {
      console.error("Failed to load regional economy map:", error)
      if (token !== this._localProfileRegionalIndicatorFetchToken) return
      this._regionalIndicatorMapData = []
      this._clearRegionalEconomyMap?.()
      this._clearRegionalAdminEconomyMap?.()
      this._clearRegionalMunicipalityMap?.()
    }
  }

  GlobeController.prototype._loadRegionalAdminEconomyMap = async function(region = this._localProfileRegion?.()) {
    if (!this._regionalAdminEconomyEnabled?.(region)) {
      this._clearRegionalAdminEconomyMap?.()
      return
    }

    const token = ++this._localProfileRegionalAdminFetchToken

    try {
      const [records, boundaryCollection] = await Promise.all([
        this._ensureRegionalAdminRecords(region),
        this._ensureRegionalAdminBoundaries(),
      ])
      if (token !== this._localProfileRegionalAdminFetchToken || !this._regionalAdminEconomyEnabled?.(region)) return

      this._renderRegionalAdminEconomyMap?.(region, records, boundaryCollection)
    } catch (error) {
      console.error("Failed to load regional admin economy map:", error)
      if (token !== this._localProfileRegionalAdminFetchToken) return
      this._clearRegionalAdminEconomyMap?.()
    }
  }

  GlobeController.prototype._loadRegionalMunicipalityMap = async function(region = this._localProfileRegion?.()) {
    if (!this._regionalMunicipalityEconomyEnabled?.(region)) {
      this._clearRegionalMunicipalityMap?.()
      return
    }

    const token = ++this._regionalMunicipalityMapFetchToken

    try {
      const records = await this._ensureRegionalMunicipalityRecords(region)
      if (token !== this._regionalMunicipalityMapFetchToken || !this._regionalMunicipalityEconomyEnabled?.(region)) return

      this._renderRegionalMunicipalityMap?.(region, records)
    } catch (error) {
      console.error("Failed to load regional municipality map:", error)
      if (token !== this._regionalMunicipalityMapFetchToken) return
      this._clearRegionalMunicipalityMap?.()
    }
  }

  GlobeController.prototype._renderRegionalEconomyMap = function(region, records = []) {
    if (!region || !this.bordersVisible || !Array.isArray(records) || records.length === 0) {
      this._clearRegionalEconomyMap?.()
      return
    }

    const Cesium = window.Cesium
    if (!Cesium) return

    const dataSource = this.getRegionalEconomyDataSource()
    dataSource.show = true
    dataSource.entities.suspendEvents()
    this._regionalEconomyMapEntities.forEach(entity => dataSource.entities.remove(entity))
    this._regionalEconomyMapEntities = []

    const metricConfig = this._regionalEconomyMetricConfig?.(region)
    const metricKey = metricConfig?.key || "gdp_nominal_usd"
    this._regionalEconomyBorderStyles = regionalEconomyBorderStyles(records, metricKey)
    this.updateBorderColors?.()

    records.forEach(record => {
      const code = `${record.country_code || ""}`.toUpperCase()
      const centroid = COUNTRY_CENTROIDS[code]
      if (!centroid) return

      const style = this._regionalEconomyBorderStyles?.[record.country_name]
      const accent = style?.accentCss || "#80cbc4"
      const metricDisplayValue = this._regionalEconomyMetricValue?.(record, region)
      const [lat, lng] = centroid
      const entity = dataSource.entities.add({
        id: `econ-${`${record.country_code_alpha3 || code}`.toLowerCase()}`,
        position: Cesium.Cartesian3.fromDegrees(lng, lat, 5000),
        point: {
          pixelSize: 22,
          color: Cesium.Color.fromCssColorString(accent).withAlpha(0.95),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.7),
          outlineWidth: 2,
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: regionalEconomyMetricLabel(record, metricConfig, metricDisplayValue),
          font: "bold 13px JetBrains Mono, monospace",
          fillColor: Cesium.Color.WHITE.withAlpha(0.96),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: LABEL_DEFAULTS.pixelOffsetAbove(),
          scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
          translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          showBackground: true,
          backgroundColor: Cesium.Color.fromCssColorString("#081019").withAlpha(0.72),
        },
        properties: {
          countryCodeAlpha3: record.country_code_alpha3,
        },
      })
      this._regionalEconomyMapEntities.push(entity)
    })

    dataSource.entities.resumeEvents()
    this._requestRender?.()
  }

  GlobeController.prototype._renderRegionalAdminEconomyMap = function(region, records = [], boundaryCollection = null) {
    if (!this._regionalAdminEconomyEnabled?.(region) || !Array.isArray(records) || records.length === 0) {
      this._clearRegionalAdminEconomyMap?.()
      return
    }

    const Cesium = window.Cesium
    if (!Cesium) return

    const features = Array.isArray(boundaryCollection?.features) ? boundaryCollection.features : []
    if (features.length === 0) {
      this._clearRegionalAdminEconomyMap?.()
      return
    }

    const dataSource = this.getRegionalAdminEconomyDataSource()
    dataSource.show = true
    dataSource.entities.suspendEvents()
    this._regionalAdminEconomyEntities.forEach(entity => dataSource.entities.remove(entity))
    this._regionalAdminEconomyEntities = []
    this._regionalAdminEconomyIndex = new Map()

    const sectorKey = this._regionalEconomySectorMode?.(region)
    const sectorLabel = this._regionalEconomySectorLabel?.(region)
    const metricConfig = this._regionalEconomyMetricConfigForGranularity?.(region, "region")
    const structureMetric = metricConfig?.key === "structure_signal"
    const scoreForRecord = (entry) => this._regionalAdminDisplayScore?.(entry, sectorKey)
    const styles = regionalAdminPreviewStyles(records, scoreForRecord)
    const labeledIds = new Set(
      records
        .slice()
        .sort((left, right) =>
          (scoreForRecord(right) || 0) - (scoreForRecord(left) || 0) ||
          (left.country_name || "").localeCompare(right.country_name || "") ||
          (left.name || "").localeCompare(right.name || "")
        )
        .slice(0, 12)
        .map(record => record.id)
    )

    records.forEach(record => {
      const feature = this._findRegionalAdminBoundaryFeature?.(record, features)
      const renderRecord = feature?.properties && (record?.lat == null || record?.lng == null)
        ? { ...record, lat: feature.properties.latitude, lng: feature.properties.longitude }
        : record
      const style = styles[record.id] || styles[record.name] || {
        accentCss: "#2f7ea7",
        fillColor: Cesium.Color.fromCssColorString("#2f7ea7").withAlpha(0.3),
        lineColor: Cesium.Color.fromCssColorString("#2f7ea7").withAlpha(0.9),
        lineWidth: 2.1,
      }
      if (feature?.geometry) {
        const geom = feature.geometry
        const rings = []
        if (geom.type === "Polygon") rings.push(geom.coordinates[0])
        else if (geom.type === "MultiPolygon") geom.coordinates.forEach(polygon => rings.push(polygon[0]))

        rings.forEach((ring, ringIndex) => {
          if (!Array.isArray(ring) || ring.length < 3) return

          const positions = ring.map(coord => Cesium.Cartesian3.fromDegrees(coord[0], coord[1]))
          const fillId = `radmin-fill-${record.id}-${ringIndex}`
          const fillEntity = dataSource.entities.add({
            id: fillId,
            polygon: {
              hierarchy: new Cesium.PolygonHierarchy(positions),
              material: style.fillColor,
              clampToGround: true,
              classificationType: Cesium.ClassificationType.BOTH,
              outline: false,
            },
          })
          this._regionalAdminEconomyEntities.push(fillEntity)
          this._regionalAdminEconomyIndex.set(fillId, renderRecord)

          const lineId = `radmin-line-${record.id}-${ringIndex}`
          const lineEntity = dataSource.entities.add({
            id: lineId,
            polyline: {
              positions,
              width: style.lineWidth,
              material: style.lineColor,
              clampToGround: true,
              classificationType: Cesium.ClassificationType.BOTH,
            },
          })
          this._regionalAdminEconomyEntities.push(lineEntity)
          this._regionalAdminEconomyIndex.set(lineId, renderRecord)
        })
      }

      const coordinates = this._regionalAdminCoordinates(renderRecord)
      if (!coordinates || !labeledIds.has(renderRecord.id)) return

      const labelId = `radmin-${renderRecord.id}`
      const labelEntity = dataSource.entities.add({
        id: labelId,
        position: Cesium.Cartesian3.fromDegrees(coordinates.lng, coordinates.lat, 4000),
        point: {
          pixelSize: 11,
          color: Cesium.Color.fromCssColorString(style.accentCss).withAlpha(0.96),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.7),
          outlineWidth: 2,
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: structureMetric
            ? regionalAdminPreviewLabel(renderRecord, {
                score: scoreForRecord(renderRecord),
                sectorLabel,
              })
            : regionalAreaMetricLabel(renderRecord, metricConfig, scoreForRecord(renderRecord)),
          font: "bold 11px JetBrains Mono, monospace",
          fillColor: Cesium.Color.WHITE.withAlpha(0.96),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: LABEL_DEFAULTS.pixelOffsetAbove(),
          scaleByDistance: new Cesium.NearFarScalar(6e4, 1, 2.2e6, 0.18),
          translucencyByDistance: new Cesium.NearFarScalar(6e4, 1, 2.2e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          showBackground: true,
          backgroundColor: Cesium.Color.fromCssColorString("#081019").withAlpha(0.78),
        },
      })
      this._regionalAdminEconomyEntities.push(labelEntity)
      this._regionalAdminEconomyIndex.set(labelId, renderRecord)
    })

    dataSource.entities.resumeEvents()
    if (this.selectedCountries?.size > 0) this.updateBorderColors?.()
    this._requestRender?.()
  }

  GlobeController.prototype._renderRegionalMunicipalityMap = function(region, records = []) {
    if (!this._regionalMunicipalityEconomyEnabled?.(region) || !Array.isArray(records) || records.length === 0) {
      this._clearRegionalMunicipalityMap?.()
      return
    }

    const Cesium = window.Cesium
    if (!Cesium) return

    const sectorKey = this._regionalEconomySectorMode?.(region)
    const sectorLabel = this._regionalEconomySectorLabel?.(region)
    const filtered = records
      .filter(profile => this._regionalMunicipalityDisplayScore?.(profile, sectorKey) > 0)
      .sort((left, right) =>
        (this._regionalMunicipalityDisplayScore?.(right, sectorKey) || 0) - (this._regionalMunicipalityDisplayScore?.(left, sectorKey) || 0) ||
        (left.country_name || "").localeCompare(right.country_name || "") ||
        (left.name || "").localeCompare(right.name || "")
      )
      .slice(0, 80)

    const dataSource = this.getRegionalMunicipalityDataSource()
    dataSource.show = true
    dataSource.entities.suspendEvents()
    this._regionalMunicipalityEntities.forEach(entity => dataSource.entities.remove(entity))
    this._regionalMunicipalityEntities = []
    this._regionalMunicipalityIndex = new Map()

    const labeledIds = new Set(filtered.slice(0, 18).map(profile => profile.id))

    filtered.forEach(profile => {
      const coordinates = this._regionalMunicipalityCoordinates(profile)
      if (!coordinates) return

      const accent = this._regionalMunicipalityAccent(profile, sectorKey)
      const score = Math.round(this._regionalMunicipalityDisplayScore?.(profile, sectorKey) || 0)
      const pointId = `rmuni-${profile.id}`
      const entity = dataSource.entities.add({
        id: pointId,
        position: Cesium.Cartesian3.fromDegrees(coordinates.lng, coordinates.lat, 3000),
        point: {
          pixelSize: labeledIds.has(profile.id) ? 14 : 9,
          color: Cesium.Color.fromCssColorString(accent).withAlpha(0.96),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.75),
          outlineWidth: 2,
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: labeledIds.has(profile.id) ? {
          text: `${profile.name}\n${sectorKey === "all" ? "Signal" : sectorLabel} ${score}`,
          font: "bold 11px JetBrains Mono, monospace",
          fillColor: Cesium.Color.WHITE.withAlpha(0.96),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: LABEL_DEFAULTS.pixelOffsetAbove(),
          scaleByDistance: new Cesium.NearFarScalar(4e4, 1, 1.6e6, 0.15),
          translucencyByDistance: new Cesium.NearFarScalar(4e4, 1, 1.6e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          showBackground: true,
          backgroundColor: Cesium.Color.fromCssColorString("#081019").withAlpha(0.78),
        } : undefined,
        properties: {
          municipalityId: profile.id,
        },
      })

      this._regionalMunicipalityEntities.push(entity)
      this._regionalMunicipalityIndex.set(pointId, profile)
    })

    dataSource.entities.resumeEvents()
    this._requestRender?.()
  }

  GlobeController.prototype.showRegionalIndicatorDetail = function(record, options = {}) {
    if (!record) return

    const region = this._regionalEconomyRegion?.()
    const coordinates = this._regionalEconomyCoordinates(record)
    const metricConfig = this._regionalEconomyMetricConfig?.(region)
    const selectedMetricValue = this._regionalEconomyMetricValue?.(record, region)
    const selectedMetricSource = this._regionalEconomyMetricSourceSummary?.(region)
    const anchoredRecord = coordinates
      ? {
          ...record,
          lat: coordinates.lat,
          lng: coordinates.lng,
          accent_color: this._regionalEconomyAccent(record),
          selected_metric_key: metricConfig?.key,
          selected_metric_label: metricConfig?.label,
          selected_metric_short_label: metricConfig?.shortLabel,
          selected_metric_value: selectedMetricValue,
          selected_metric_source: selectedMetricSource,
        }
      : {
          ...record,
          accent_color: this._regionalEconomyAccent(record),
          selected_metric_key: metricConfig?.key,
          selected_metric_label: metricConfig?.label,
          selected_metric_short_label: metricConfig?.shortLabel,
          selected_metric_value: selectedMetricValue,
          selected_metric_source: selectedMetricSource,
        }

    if (!options.contextOnly && this._showCompactEntityDetail) {
      this._showCompactEntityDetail("regional_economy", anchoredRecord, {
        id: record.country_code_alpha3 || record.country_code || record.country_name,
        picked: options.picked,
      })
    }

    const context = this._buildRegionalEconomyContext?.(record)
    if (context && this._setSelectedContext) {
      this._setSelectedContext(context, {
        openRightPanel: options.openRightPanel === true || this._currentRightPanelTab?.() === "context",
      })
    }

    if (this.hasDetailPanelTarget) this.detailPanelTarget.style.display = "none"
  }

  GlobeController.prototype.showRegionalMunicipalityDetail = function(profile, options = {}) {
    if (!profile) return

    const coordinates = this._regionalMunicipalityCoordinates(profile)
    const sectorKey = this._regionalEconomySectorMode?.()
    const sectorLabel = this._regionalEconomySectorLabel?.()
    const selectedSectorKeys = this._regionalMunicipalitySelectedSectorKeys?.(profile, sectorKey)
    const anchoredRecord = coordinates
      ? {
          ...profile,
          lat: coordinates.lat,
          lng: coordinates.lng,
          accent_color: this._regionalMunicipalityAccent(profile, sectorKey),
          selected_sector_key: sectorKey,
          selected_sector_label: sectorLabel,
          selected_sector_names: selectedSectorKeys.map(titleizeProfileKey),
          signal_score: this._regionalMunicipalityDisplayScore?.(profile, sectorKey),
        }
      : {
          ...profile,
          accent_color: this._regionalMunicipalityAccent(profile, sectorKey),
          selected_sector_key: sectorKey,
          selected_sector_label: sectorLabel,
          selected_sector_names: selectedSectorKeys.map(titleizeProfileKey),
          signal_score: this._regionalMunicipalityDisplayScore?.(profile, sectorKey),
        }

    if (!options.contextOnly && this._showCompactEntityDetail) {
      this._showCompactEntityDetail("regional_municipality", anchoredRecord, {
        id: profile.id || profile.name,
        picked: options.picked,
      })
    }

    const context = this._buildRegionalMunicipalityContext?.(profile)
    if (context && this._setSelectedContext) {
      this._setSelectedContext(context, {
        openRightPanel: options.openRightPanel === true || this._currentRightPanelTab?.() === "context",
      })
    }

    if (this.hasDetailPanelTarget) this.detailPanelTarget.style.display = "none"
  }

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
    const mapLegend = regionalEconomyMapLegend(mapView, selectedSectorLabel, selectedMetric?.label || "Metric", selectedMetricSource, selectedMetricKey)
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

  GlobeController.prototype._renderLocalRegionalEconomyBaseline = async function(region) {
    const shell = this.localProfileContentTarget.querySelector("[data-local-profile-economy]")
    if (!shell) return

    const token = ++this._localProfileRegionalIndicatorFetchToken
    const countryNames = Array.isArray(region.countries) ? region.countries : []
    const filterKey = countryNames.join("|")

    try {
      let records = this._localProfileRegionalIndicatorCatalog
      if (!Array.isArray(records) || this._localProfileRegionalIndicatorFilterKey !== filterKey) {
        records = await this._ensureRegionalIndicatorRecords(region)
      }

      if (token !== this._localProfileRegionalIndicatorFetchToken || this._localProfileRegion?.()?.key !== region.key) return

      const regionalRecords = Array.isArray(records) ? records : []
      if (regionalRecords.length === 0) {
        this._regionalIndicatorMapData = []
        this._clearRegionalEconomyMap?.()
        this._clearRegionalAdminEconomyMap?.()
        shell.innerHTML = `
          <div class="local-profile-section-title">Regional Economy Baseline</div>
          <div class="local-profile-empty-row">No regional indicator baseline is available for this region yet.</div>
        `
        return
      }

      const totalGdp = sumMetric(regionalRecords, "gdp_nominal_usd")
      const totalPopulation = sumMetric(regionalRecords, "population_total")
      const granularityKey = this._regionalEconomyGranularityKey?.(region)
      const currentMetric = this._regionalEconomyMetricConfig?.(region)
      const countryMetric = this._regionalEconomyMetricConfigForGranularity?.(region, "country")
      const countryMetricSource = this._regionalEconomyMetricSourceSummaryForGranularity?.(region, "country")
      const manufacturingLeader = regionalRecords
        .slice()
        .sort((left, right) =>
          (metricValue(right, "manufacturing_share_pct") || -1) - (metricValue(left, "manufacturing_share_pct") || -1) ||
          (left.country_name || "").localeCompare(right.country_name || "")
        )[0]
      const sampleRecords = regionalRecords
        .slice()
        .sort((left, right) =>
          (metricValue(right, "gdp_nominal_usd") || 0) - (metricValue(left, "gdp_nominal_usd") || 0) ||
          (left.country_name || "").localeCompare(right.country_name || "")
        )

      this._regionalIndicatorMapData = regionalRecords
      this._syncRegionalEconomyMap?.()

      shell.innerHTML = `
        <div class="local-profile-section-title">Regional Economy Baseline</div>
        <div class="local-profile-chip-row">
          <span class="local-profile-chip">${regionalRecords.length} Country Snapshots</span>
          <span class="local-profile-chip">Country Metric ${this._escapeHtml(countryMetric?.label || "GDP")}</span>
          <span class="local-profile-chip">GDP ${this._escapeHtml(formatCompactCurrency(totalGdp))}</span>
          <span class="local-profile-chip">Population ${this._escapeHtml(formatCompactNumber(totalPopulation))}</span>
          <span class="local-profile-chip">Top Manufacturing ${this._escapeHtml(manufacturingLeader?.country_name || "—")}</span>
        </div>
        <div class="local-profile-grid">
          <div class="local-profile-section">
            <div class="local-profile-section-title">Regional Read</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList([
                `Combined GDP · ${this._escapeHtml(formatCompactCurrency(totalGdp))}`,
                `Combined Population · ${this._escapeHtml(formatCompactNumber(totalPopulation))}`,
                `Manufacturing Leader · ${this._escapeHtml(manufacturingLeader?.country_name || "Unknown")} · ${this._escapeHtml(formatPercent(metricValue(manufacturingLeader, "manufacturing_share_pct")))}`,
                `Country Baseline · World Bank WDI snapshots across Germany, Austria, and Switzerland`,
                `Granularity · Use Region, District, Country, or Normal to switch the DACH economic explorer`,
                `Country Metric · ${this._escapeHtml(countryMetric?.label || "GDP")}`,
                `Country Metric Source · ${this._escapeHtml(countryMetricSource)}`,
                granularityKey === "country"
                  ? `Country mode is source-backed by World Bank WDI`
                  : (granularityKey === "region" && currentMetric?.key !== "structure_signal"
                    ? `Region mode is source-backed by official DACH population feeds`
                    : granularityKey === "district"
                      ? `District mode is source-backed by official district-equivalent population feeds`
                      : `Local subnational detail needs explicit source-backed geometry and metrics`),
                currentMetric?.key === "structure_signal"
                  ? `Sector Focus · Region view can pivot toward automotive, chips, chemicals, energy, finance, or trade`
                  : `Sector Focus · Structure remains available as a separate derived metric`,
                granularityKey === "country"
                  ? `Current Source · ${this._escapeHtml([regionalRecords[0]?.source_name || "World Bank WDI", regionalRecords[0]?.latest_year || "latest", "Country"].filter(Boolean).join(" · "))}`
                  : `Current Source · ${this._escapeHtml(this._regionalEconomyMetricSourceSummary?.(region))}`,
              ], "No baseline summary yet")}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Coverage</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                sampleRecords.map(record => {
                  const latestYear = record.latest_year ? ` · ${record.latest_year}` : ""
                  return `${this._escapeHtml(record.country_name || "Unknown")} · GDP ${this._escapeHtml(formatCompactCurrency(metricValue(record, "gdp_nominal_usd")))}${latestYear}`
                }),
                "No coverage yet"
              )}
            </ul>
          </div>
        </div>
        <div class="local-profile-grid">
          ${sampleRecords.map(record => {
            const topSectors = Array.isArray(record.top_sectors) && record.top_sectors.length > 0
              ? record.top_sectors.slice(0, 3).map(sector => sector.sector_name).join(" · ")
              : ""
            const sourceLabel = [
              record.source_name || "Unknown source",
              record.latest_year || null,
            ].filter(Boolean).join(" · ")

            return `
              <div class="local-profile-section">
                <div class="local-profile-section-title">${this._escapeHtml(record.country_name || "Unknown")}</div>
                <ul class="local-profile-list local-profile-list--compact">
                  ${renderLocalProfileList([
                    `${this._escapeHtml(countryMetric?.label || "GDP")} · ${this._escapeHtml(formatRegionalMetric(countryMetric, this._regionalEconomyMetricValueForGranularity?.(record, region, "country")))}`,
                    `GDP · ${this._escapeHtml(formatCompactCurrency(metricValue(record, "gdp_nominal_usd")))}`,
                    `GDP / Capita · ${this._escapeHtml(formatCompactCurrency(metricValue(record, "gdp_per_capita_usd")))}`,
                    `Population · ${this._escapeHtml(formatCompactNumber(metricValue(record, "population_total")))}`,
                    `Manufacturing Share · ${this._escapeHtml(formatPercent(metricValue(record, "manufacturing_share_pct")))}`,
                    `Exports / GDP · ${this._escapeHtml(formatPercent(metricValue(record, "exports_goods_services_pct_gdp")))}`,
                  ], "No metrics yet")}
                </ul>
                ${topSectors ? `<div class="local-profile-empty-row">Top sectors: ${this._escapeHtml(topSectors)}</div>` : ""}
                <div class="local-profile-empty-row">Metric source: ${this._escapeHtml(sourceLabel)}</div>
              </div>
            `
          }).join("")}
        </div>
      `
    } catch (error) {
      console.error("Failed to render local regional economy baseline:", error)
      this._regionalIndicatorMapData = []
      this._clearRegionalEconomyMap?.()
      this._clearRegionalAdminEconomyMap?.()
      if (token !== this._localProfileRegionalIndicatorFetchToken || this._localProfileRegion?.()?.key !== region.key) return
      shell.innerHTML = `
        <div class="local-profile-section-title">Regional Economy Baseline</div>
        <div class="local-profile-empty-row">Regional economy baseline failed to load.</div>
      `
    }
  }

  GlobeController.prototype._renderLocalRegionalAdminPreview = async function(region) {
    const shell = this.localProfileContentTarget.querySelector("[data-local-profile-admin-preview]")
    if (!shell) return
    const regionMetricConfig = this._regionalEconomyMetricConfigForGranularity?.(region, "region")
    const sectionTitle = regionMetricConfig?.key === "structure_signal" ? "Regional Structure" : "Regional Metric"

    try {
      const records = await this._ensureRegionalAdminRecords(region)
      if (this._localProfileRegion?.()?.key !== region.key) return

      const previewRecords = Array.isArray(records) ? records : []
      if (previewRecords.length === 0) {
        shell.innerHTML = `
          <div class="local-profile-section-title">${this._escapeHtml(sectionTitle)}</div>
          <div class="local-profile-empty-row">No subnational regional data is available for this region yet.</div>
        `
        return
      }

      const regionMetricKey = regionMetricConfig?.key
      const regionMetricSource = this._regionalEconomyMetricSourceSummaryForGranularity?.(region, "region")
      if (regionMetricKey !== "structure_signal") {
        const topAreas = this._regionalAdminRankedRecords?.("all") || []
        const byCountry = previewRecords.reduce((acc, record) => {
          const key = record.country_name || record.country_code_alpha3 || "Unknown"
          acc[key] = (acc[key] || 0) + 1
          return acc
        }, {})
        const latestYear = previewRecords.map(record => Number(record.latest_year) || 0).reduce((max, value) => Math.max(max, value), 0)

        shell.innerHTML = `
          <div class="local-profile-section-title">Regional Metric</div>
          <div class="local-profile-chip-row">
            <span class="local-profile-chip">${previewRecords.length} Regions</span>
            <span class="local-profile-chip">${this._escapeHtml(regionMetricConfig?.label || "Metric")}</span>
            ${latestYear > 0 ? `<span class="local-profile-chip">Year ${this._escapeHtml(`${latestYear}`)}</span>` : ""}
            <span class="local-profile-chip">${this._escapeHtml(regionMetricSource)}</span>
          </div>
          <div class="local-profile-grid">
            <div class="local-profile-section">
              <div class="local-profile-section-title">Map Read</div>
              <ul class="local-profile-list local-profile-list--compact">
                ${renderLocalProfileList([
                  `Official region-equivalent overlay across DACH`,
                  `Metric · ${this._escapeHtml(regionMetricConfig?.label || "Metric")}`,
                  `Fill · Rank by ${this._escapeHtml(regionMetricConfig?.label || "metric")} across region-equivalent units`,
                  `Labels · Top 12 regions by ${this._escapeHtml(regionMetricConfig?.label || "metric")}`,
                  `Source · ${this._escapeHtml(regionMetricSource)}`,
                  `Caveat · Region-equivalent levels differ by country: Austrian Bundeslander, German Lander, Swiss cantons`,
                ], "No regional metric guidance yet")}
              </ul>
            </div>
            <div class="local-profile-section">
              <div class="local-profile-section-title">Coverage</div>
              <ul class="local-profile-list local-profile-list--compact">
                ${renderLocalProfileList(
                  Object.entries(byCountry)
                    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                    .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                  "No regional coverage yet"
                )}
              </ul>
            </div>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Top Regions</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                topAreas.slice(0, 10).map(record => {
                  const metricValueForRecord = this._regionalEconomyMetricValueForGranularity?.(record, region, "region")
                  const latest = record.latest_year ? ` · ${record.latest_year}` : ""
                  return `${this._escapeHtml(record.name || "Unknown")} · ${this._escapeHtml(record.country_name || "Unknown")} · ${this._escapeHtml(formatRegionalMetric(regionMetricConfig, metricValueForRecord))}${latest}`
                }),
                "No top regions yet"
              )}
            </ul>
          </div>
        `
        return
      }

      const sectorKey = this._regionalEconomySectorMode?.(region)
      const sectorLabel = this._regionalEconomySectorLabel?.(region)
      const topAreas = (this._regionalAdminRankedRecords?.(sectorKey) || []).filter(record =>
        sectorKey === "all" || (this._regionalAdminDisplayScore?.(record, sectorKey) || 0) > 0
      )
      const byCountry = previewRecords.reduce((acc, record) => {
        const key = record.country_name || record.country_code_alpha3 || "Unknown"
        acc[key] = (acc[key] || 0) + 1
        return acc
      }, {})
      const totalCities = sumMetric(previewRecords, "city_count")
      const totalSites = sumMetric(previewRecords, "strategic_site_count")
      const totalPowerMw = sumMetric(previewRecords, "curated_power_capacity_mw")
      const selectedSectorSignalTotal = sectorKey === "all"
        ? null
        : previewRecords.reduce((sum, record) => {
            const profile = this._regionalAdminSelectedSectorProfile?.(record, sectorKey)
            return sum + (numericMetricValue(profile?.signal_count) || 0)
          }, 0)
      const sectorMix = previewRecords.reduce((acc, record) => {
        Array.isArray(record.top_sectors) && record.top_sectors.forEach(profile => {
          const key = profile?.sector_name
          if (!key) return
          acc[key] = (acc[key] || 0) + (numericMetricValue(profile?.signal_count) || 0)
        })
        return acc
      }, {})

      shell.innerHTML = `
        <div class="local-profile-section-title">Regional Structure</div>
        <div class="local-profile-chip-row">
          <span class="local-profile-chip">${previewRecords.length} Regions</span>
          <span class="local-profile-chip">Cities ${this._escapeHtml(formatCompactNumber(totalCities))}</span>
          <span class="local-profile-chip">Sites ${this._escapeHtml(formatCompactNumber(totalSites))}</span>
          <span class="local-profile-chip">Power ${this._escapeHtml(`${DECIMAL_FORMAT.format((totalPowerMw || 0) / 1000)} GW`)}</span>
          ${sectorKey !== "all" ? `<span class="local-profile-chip">${this._escapeHtml(sectorLabel)} ${this._escapeHtml(formatCompactNumber(selectedSectorSignalTotal))} signals</span>` : ""}
        </div>
        <div class="local-profile-grid">
          <div class="local-profile-section">
            <div class="local-profile-section-title">Map Read</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList([
                `Local-only overlay · Admin-1 polygons for profiled DACH areas`,
                `Focus · ${this._escapeHtml(sectorKey === "all" ? "All sectors" : sectorLabel)}`,
                `Fill · ${this._escapeHtml(sectorKey === "all" ? "overall industrial signal" : `${sectorLabel} signal`)} from cities, strategic sites, and curated power`,
                `Labels · Top 12 regions for the current focus`,
                `Controls · Switch to District, Country, or Normal above for comparison`,
                `Interaction · Click a polygon or label for the connector anchor`,
                `Caveat · Derived industrial footprint, not official district GDP or employment yet`,
              ], "No preview guidance yet")}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Coverage</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                Object.entries(byCountry)
                  .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                  .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                "No admin coverage yet"
              )}
            </ul>
          </div>
        </div>
        <div class="local-profile-grid">
          <div class="local-profile-section">
            <div class="local-profile-section-title">Leading Sectors</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                Object.entries(sectorMix)
                  .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                  .slice(0, 6)
                  .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                "No sector structure yet"
              )}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Next Level</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList([
                "Current drilldown is region level plus city and site nodes",
                "District-level regional accounts and sector data still need official admin-2 sources",
                "Best next real step: official district geometry for Germany, Austria, and Switzerland",
              ], "No next step yet")}
            </ul>
          </div>
        </div>
        <div class="local-profile-section">
          <div class="local-profile-section-title">Top Regions</div>
          <ul class="local-profile-list local-profile-list--compact">
            ${renderLocalProfileList(
              topAreas.slice(0, 8).map(record => {
                const selectedSector = this._regionalAdminSelectedSectorProfile?.(record, sectorKey)
                const focusLabel = selectedSector?.sector_name || record?.top_sectors?.[0]?.sector_name || "Mixed structure"
                const nodes = Array.isArray(record.top_nodes)
                  ? record.top_nodes.slice(0, 2).map(node => node.name).join(" · ")
                  : ""
                const score = formatCompactNumber(this._regionalAdminDisplayScore?.(record, sectorKey))
                return `${this._escapeHtml(record.name || "Unknown")} · ${this._escapeHtml(record.country_name || "Unknown")} · ${this._escapeHtml(focusLabel)} · Signal ${this._escapeHtml(score)}${nodes ? ` · ${this._escapeHtml(nodes)}` : ""}`
              }),
              "No top areas yet"
            )}
          </ul>
        </div>
      `
    } catch (error) {
      console.error("Failed to render local regional structure:", error)
      if (this._localProfileRegion?.()?.key !== region.key) return
      shell.innerHTML = `
        <div class="local-profile-section-title">${this._escapeHtml(sectionTitle)}</div>
        <div class="local-profile-empty-row">${this._escapeHtml(sectionTitle)} failed to load.</div>
      `
    }
  }

  GlobeController.prototype._renderLocalRegionalDistrictPreview = async function(region) {
    const shell = this.localProfileContentTarget.querySelector("[data-local-profile-district-preview]")
    if (!shell) return

    const token = ++this._localProfileRegionalDistrictPreviewFetchToken

    try {
      const records = await this._ensureRegionalDistrictRecords(region)
      if (token !== this._localProfileRegionalDistrictPreviewFetchToken || this._localProfileRegion?.()?.key !== region.key) return

      const districtRecords = Array.isArray(records) ? records : []
      if (districtRecords.length === 0) {
        shell.innerHTML = `
          <div class="local-profile-section-title">District Metric</div>
          <div class="local-profile-empty-row">No district-equivalent data is available for this region yet.</div>
        `
        return
      }

      const metricConfig = this._regionalEconomyMetricConfigForGranularity?.(region, "district")
      const metricSource = this._regionalEconomyMetricSourceSummaryForGranularity?.(region, "district")
      const filtered = districtRecords
        .sort((left, right) =>
          (this._regionalEconomyMetricValueForGranularity?.(right, region, "district") || 0) - (this._regionalEconomyMetricValueForGranularity?.(left, region, "district") || 0) ||
          (left.country_name || "").localeCompare(right.country_name || "") ||
          (left.name || "").localeCompare(right.name || "")
        )

      const byCountry = filtered.reduce((acc, record) => {
        const key = record.country_name || record.country_code || "Unknown"
        acc[key] = (acc[key] || 0) + 1
        return acc
      }, {})
      const byRegion = filtered.reduce((acc, record) => {
        const key = record.region_name || "Unknown"
        acc[key] = (acc[key] || 0) + 1
        return acc
      }, {})
      const latestYear = filtered.map(record => Number(record.latest_year) || 0).reduce((max, value) => Math.max(max, value), 0)

      shell.innerHTML = `
        <div class="local-profile-section-title">District Metric</div>
        <div class="local-profile-chip-row">
          <span class="local-profile-chip">${filtered.length} District-equivalent units</span>
          <span class="local-profile-chip">${this._escapeHtml(metricConfig?.label || "Population")}</span>
          ${latestYear > 0 ? `<span class="local-profile-chip">Year ${this._escapeHtml(`${latestYear}`)}</span>` : ""}
        </div>
        <div class="local-profile-grid">
          <div class="local-profile-section">
            <div class="local-profile-section-title">Map Read</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList([
                `District-equivalent ${this._escapeHtml(metricConfig?.label || "population")} across DACH`,
                `Source · ${this._escapeHtml(metricSource)}`,
                "Map overlay stays off until official district geometry is wired",
                "Use this panel to compare districts inside and across states",
              ], "No district guidance yet")}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">By Country</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                Object.entries(byCountry)
                  .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                  .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                "No district coverage yet"
              )}
            </ul>
          </div>
        </div>
        <div class="local-profile-grid">
          <div class="local-profile-section">
            <div class="local-profile-section-title">By Region</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                Object.entries(byRegion)
                  .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                  .slice(0, 8)
                  .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                "No regional split yet"
              )}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Top Districts</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                filtered.slice(0, 12).map(record => {
                  const metricValue = this._regionalEconomyMetricValueForGranularity?.(record, region, "district")
                  const latest = record.latest_year ? ` · ${record.latest_year}` : ""
                  return `${this._escapeHtml(record.name || "Unknown")} · ${this._escapeHtml(record.region_name || record.country_name || "Unknown")} · ${this._escapeHtml(formatRegionalMetric(metricConfig, metricValue))}${latest}`
                }),
                "No district records yet"
              )}
            </ul>
          </div>
        </div>
      `
    } catch (error) {
      console.error("Failed to render local district metric:", error)
      if (token !== this._localProfileRegionalDistrictPreviewFetchToken || this._localProfileRegion?.()?.key !== region.key) return
      shell.innerHTML = `
        <div class="local-profile-section-title">District Metric</div>
        <div class="local-profile-empty-row">District data failed to load.</div>
      `
    }
  }

  GlobeController.prototype._renderLocalSourceCoverage = async function(region) {
    const shell = this.localProfileContentTarget.querySelector("[data-local-profile-data-sources]")
    if (!shell) return

    const token = ++this._localProfileDataSourceFetchToken

    try {
      let sources = this._localProfileDataSourceCatalog
      if (!Array.isArray(sources) || this._localProfileDataSourceRegionKey !== region.key) {
        const response = await fetch(`/api/data_sources?region_key=${encodeURIComponent(region.key)}`)
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        const payload = await response.json()
        this._localProfileDataSourceCatalog = Array.isArray(payload) ? payload : []
        this._localProfileDataSourceRegionKey = region.key
        sources = this._localProfileDataSourceCatalog
      }

      if (token !== this._localProfileDataSourceFetchToken || this._localProfileRegion?.()?.key !== region.key) return

      const regionalSources = (sources || []).filter(source =>
        Array.isArray(source.region_keys) ? source.region_keys.includes(region.key) : false
      )

      if (regionalSources.length === 0) {
        shell.innerHTML = `
          <div class="local-profile-section-title">Source Coverage</div>
          <div class="local-profile-empty-row">No registered data sources for this region yet.</div>
        `
        return
      }

      const byStatus = regionalSources.reduce((acc, source) => {
        const key = sourceStatusLabel(source.status)
        acc[key] = (acc[key] || 0) + 1
        return acc
      }, {})
      const byCountry = regionalSources.reduce((acc, source) => {
        const labels = Array.isArray(source.country_names) && source.country_names.length > 0
          ? source.country_names
          : Array.isArray(source.country_codes) ? source.country_codes : ["Unknown"]
        labels.forEach(label => {
          acc[label] = (acc[label] || 0) + 1
        })
        return acc
      }, {})
      const byModel = regionalSources.reduce((acc, source) => {
        const key = titleizeProfileKey(source.target_model)
        acc[key] = (acc[key] || 0) + 1
        return acc
      }, {})
      const sampleSources = regionalSources.slice(0, 8)

      shell.innerHTML = `
        <div class="local-profile-section-title">Source Coverage</div>
        <div class="local-profile-chip-row">
          <span class="local-profile-chip">${regionalSources.length} Sources</span>
          <span class="local-profile-chip">${Object.keys(byCountry).length} Countries</span>
          <span class="local-profile-chip">${Object.keys(byModel).length} Models</span>
        </div>
        <div class="local-profile-grid">
          <div class="local-profile-section">
            <div class="local-profile-section-title">By Status</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                Object.entries(byStatus)
                  .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                  .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                "No status coverage yet"
              )}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">By Country</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                Object.entries(byCountry)
                  .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                  .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                "No country coverage yet"
              )}
            </ul>
          </div>
        </div>
        <div class="local-profile-section">
          <div class="local-profile-section-title">Sample Sources</div>
          <ul class="local-profile-list local-profile-list--compact">
            ${renderLocalProfileList(
              sampleSources.map(source => {
                const label = [
                  sourceStatusLabel(source.status),
                  titleizeProfileKey(source.target_model),
                  Array.isArray(source.country_names) ? source.country_names.join(", ") : null,
                ].filter(Boolean).join(" · ")
                return `${this._escapeHtml(source.name || "Unknown")} · ${this._escapeHtml(label)}`
              }),
              "No sample sources yet"
            )}
          </ul>
        </div>
      `
    } catch (error) {
      console.error("Failed to render local source coverage:", error)
      if (token !== this._localProfileDataSourceFetchToken || this._localProfileRegion?.()?.key !== region.key) return
      shell.innerHTML = `
        <div class="local-profile-section-title">Source Coverage</div>
        <div class="local-profile-empty-row">Source coverage failed to load.</div>
      `
    }
  }

  GlobeController.prototype._renderLocalPowerPlantCoverage = async function(region) {
    const shell = this.localProfileContentTarget.querySelector("[data-local-profile-power-plants]")
    if (!shell) return

    const token = ++this._localProfilePowerPlantFetchToken
    const countryNames = new Set(region.countries || [])

    try {
      let profiles = this._localProfilePowerPlantCatalog
      if (!Array.isArray(profiles) || profiles.length === 0) {
        const response = await fetch("/api/power_plant_profiles")
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        const payload = await response.json()
        this._localProfilePowerPlantCatalog = Array.isArray(payload) ? payload : []
        profiles = this._localProfilePowerPlantCatalog
      }

      if (token !== this._localProfilePowerPlantFetchToken || this._localProfileRegion?.()?.key !== region.key) return

      const regionalProfiles = (profiles || []).filter(profile => countryNames.has(profile.country_name))
      if (regionalProfiles.length === 0) {
        shell.innerHTML = `
          <div class="local-profile-section-title">Curated Power Coverage</div>
          <div class="local-profile-empty-row">No curated power coverage loaded for this region yet.</div>
        `
        return
      }

      const byCountry = regionalProfiles.reduce((acc, profile) => {
        const key = profile.country_name || profile.country_code || "Unknown"
        acc[key] = (acc[key] || 0) + 1
        return acc
      }, {})
      const byFuel = regionalProfiles.reduce((acc, profile) => {
        const key = profile.primary_fuel || "Unknown"
        acc[key] = (acc[key] || 0) + 1
        return acc
      }, {})
      const samplePlants = regionalProfiles
        .slice()
        .sort((left, right) => (right.capacity_mw || 0) - (left.capacity_mw || 0) || (left.name || "").localeCompare(right.name || ""))
        .slice(0, 6)

      shell.innerHTML = `
        <div class="local-profile-section-title">Curated Power Coverage</div>
        <div class="local-profile-chip-row">
          <span class="local-profile-chip">${regionalProfiles.length} Plants</span>
          <span class="local-profile-chip">${Object.keys(byFuel).length} Fuels</span>
        </div>
        <div class="local-profile-grid">
          <div class="local-profile-section">
            <div class="local-profile-section-title">By Country</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                Object.entries(byCountry)
                  .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                  .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                "No country coverage yet"
              )}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Fuel Mix</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                Object.entries(byFuel)
                  .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                  .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                "No fuel mix yet"
              )}
            </ul>
          </div>
        </div>
        <div class="local-profile-section">
          <div class="local-profile-section-title">Sample Plants</div>
          <ul class="local-profile-list local-profile-list--compact">
            ${renderLocalProfileList(
              samplePlants.map(profile => `${this._escapeHtml(profile.name || "Unknown")} · ${this._escapeHtml(profile.country_name || profile.country_code || "Unknown")}`),
              "No sample plants yet"
            )}
          </ul>
        </div>
      `
    } catch (error) {
      console.error("Failed to render local power coverage:", error)
      if (token !== this._localProfilePowerPlantFetchToken || this._localProfileRegion?.()?.key !== region.key) return
      shell.innerHTML = `
        <div class="local-profile-section-title">Curated Power Coverage</div>
        <div class="local-profile-empty-row">Curated power coverage failed to load.</div>
      `
    }
  }

  GlobeController.prototype._renderLocalCityCoverage = async function(region) {
    const shell = this.localProfileContentTarget.querySelector("[data-local-profile-city-coverage]")
    if (!shell) return

    const token = ++this._localProfileCityFetchToken
    const countryNames = new Set(region.countries || [])

    try {
      let profiles = this._localProfileCityProfiles
      if (!Array.isArray(profiles) || profiles.length === 0) {
        const response = await fetch("/api/city_profiles")
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        const payload = await response.json()
        this._localProfileCityProfiles = Array.isArray(payload) ? payload : []
        profiles = this._localProfileCityProfiles
      }

      if (token !== this._localProfileCityFetchToken || this._localProfileRegion?.()?.key !== region.key) return

      const regionalProfiles = (profiles || []).filter(profile => countryNames.has(profile.country_name))
      if (regionalProfiles.length === 0) {
        shell.innerHTML = `
          <div class="local-profile-section-title">Economic City Coverage</div>
          <div class="local-profile-empty-row">No city coverage loaded for this region yet.</div>
        `
        return
      }

      const byCountry = regionalProfiles.reduce((acc, profile) => {
        const key = profile.country_name || profile.country_code || "Unknown"
        acc[key] = (acc[key] || 0) + 1
        return acc
      }, {})
      const byRole = regionalProfiles.reduce((acc, profile) => {
        ;(profile.role_tags || []).forEach(role => {
          const key = titleizeProfileKey(role)
          acc[key] = (acc[key] || 0) + 1
        })
        return acc
      }, {})
      const sampleCities = regionalProfiles
        .slice()
        .sort((left, right) =>
          (left.priority || 9999) - (right.priority || 9999) ||
          (left.country_name || "").localeCompare(right.country_name || "") ||
          (left.name || "").localeCompare(right.name || "")
        )
        .slice(0, 6)

      shell.innerHTML = `
        <div class="local-profile-section-title">Economic City Coverage</div>
        <div class="local-profile-chip-row">
          <span class="local-profile-chip">${regionalProfiles.length} Cities</span>
          <span class="local-profile-chip">${Object.keys(byRole).length} Role Tags</span>
        </div>
        <div class="local-profile-grid">
          <div class="local-profile-section">
            <div class="local-profile-section-title">By Country</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                Object.entries(byCountry)
                  .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                  .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                "No country coverage yet"
              )}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Top Roles</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(
                Object.entries(byRole)
                  .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
                  .slice(0, 6)
                  .map(([name, count]) => `${this._escapeHtml(name)} · ${count}`),
                "No role coverage yet"
              )}
            </ul>
          </div>
        </div>
        <div class="local-profile-section">
          <div class="local-profile-section-title">Sample Cities</div>
          <ul class="local-profile-list local-profile-list--compact">
            ${renderLocalProfileList(
              sampleCities.map(profile => {
                const sector = Array.isArray(profile.strategic_sectors) && profile.strategic_sectors.length > 0
                  ? ` · ${this._escapeHtml(profile.strategic_sectors[0])}`
                  : ""
                return `${this._escapeHtml(profile.name || "Unknown")} · ${this._escapeHtml(profile.country_name || profile.country_code || "Unknown")}${sector}`
              }),
              "No sample cities yet"
            )}
          </ul>
        </div>
      `
    } catch (error) {
      console.error("Failed to render local city coverage:", error)
      if (token !== this._localProfileCityFetchToken || this._localProfileRegion?.()?.key !== region.key) return
      shell.innerHTML = `
        <div class="local-profile-section-title">Economic City Coverage</div>
        <div class="local-profile-empty-row">City coverage failed to load.</div>
      `
    }
  }

  GlobeController.prototype._renderLocalStrategicSiteCoverage = async function(region) {
    const shell = this.localProfileContentTarget.querySelector("[data-local-profile-strategic-sites]")
    if (!shell) return

    const token = ++this._localProfileStrategicSiteFetchToken
    const countryNames = new Set(region.countries || [])
    const countryCodes = new Set(regionCountryCodes(region))

    try {
      let sites = this._commoditySiteAll
      if (!Array.isArray(sites) || sites.length === 0) {
        if (!Array.isArray(this._localProfileStrategicSiteCatalog) || this._localProfileStrategicSiteCatalog.length === 0) {
          const response = await fetch("/api/commodity_sites")
          if (!response.ok) throw new Error(`HTTP ${response.status}`)
          const payload = await response.json()
          this._localProfileStrategicSiteCatalog = Array.isArray(payload) ? payload : (payload.commodity_sites || [])
        }
        sites = this._localProfileStrategicSiteCatalog
      }

      if (token !== this._localProfileStrategicSiteFetchToken || this._localProfileRegion?.()?.key !== region.key) return

      const regionalSites = (sites || []).filter(site => {
        if (!site) return false
        if (countryCodes.size > 0 && countryCodes.has(site.country_code)) return true
        return countryNames.has(site.country_name)
      })

      if (regionalSites.length === 0) {
        shell.innerHTML = `
          <div class="local-profile-section-title">Strategic Site Coverage</div>
          <div class="local-profile-empty-row">No strategic sites loaded for this region yet.</div>
        `
        return
      }

      const categoryCounts = regionalSites.reduce((acc, site) => {
        const key = site.commodity_name || titleizeProfileKey(site.commodity_key)
        acc[key] = (acc[key] || 0) + 1
        return acc
      }, {})

      const countryCounts = regionalSites.reduce((acc, site) => {
        const key = site.country_name || site.country_code || "Unknown"
        acc[key] = (acc[key] || 0) + 1
        return acc
      }, {})

      const topCategories = Object.entries(categoryCounts)
        .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
        .slice(0, 5)
      const totalCategoryCount = Object.keys(categoryCounts).length
      const byCountry = Object.entries(countryCounts)
        .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
      const sampleSites = regionalSites
        .slice()
        .sort((left, right) => {
          const leftCountry = left.country_name || ""
          const rightCountry = right.country_name || ""
          if (leftCountry !== rightCountry) return leftCountry.localeCompare(rightCountry)
          return (left.name || "").localeCompare(right.name || "")
        })
        .slice(0, 6)

      shell.innerHTML = `
        <div class="local-profile-section-title">Strategic Site Coverage</div>
        <div class="local-profile-chip-row">
          <span class="local-profile-chip">${regionalSites.length} Sites</span>
          <span class="local-profile-chip">${totalCategoryCount} Sectors</span>
        </div>
        <div class="local-profile-grid">
          <div class="local-profile-section">
            <div class="local-profile-section-title">By Country</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(byCountry.map(([name, count]) => `${this._escapeHtml(name)} · ${count}`), "No country coverage yet")}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Top Sectors</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderLocalProfileList(topCategories.map(([name, count]) => `${this._escapeHtml(name)} · ${count}`), "No sector mix yet")}
            </ul>
          </div>
        </div>
        <div class="local-profile-section">
          <div class="local-profile-section-title">Sample Sites</div>
          <ul class="local-profile-list local-profile-list--compact">
            ${renderLocalProfileList(sampleSites.map(site => `${this._escapeHtml(site.name || "Unknown")} · ${this._escapeHtml(site.country_name || site.country_code || "Unknown")}`), "No sample sites yet")}
          </ul>
        </div>
      `
    } catch (error) {
      console.error("Failed to render local strategic site coverage:", error)
      if (token !== this._localProfileStrategicSiteFetchToken || this._localProfileRegion?.()?.key !== region.key) return
      shell.innerHTML = `
        <div class="local-profile-section-title">Strategic Site Coverage</div>
        <div class="local-profile-empty-row">Strategic-site coverage failed to load.</div>
      `
    }
  }
}
