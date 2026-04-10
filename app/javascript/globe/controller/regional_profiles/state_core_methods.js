import { COUNTRY_CENTROIDS } from "globe/country_centroids"
import { defaultRegionalMetricKey, regionalMetricConfig, regionalMetricOptions, regionalMetricSourceSummary } from "globe/controller/regional_profiles/catalog"
import {
  clampNumber,
  formatCompactCurrency,
  formatCompactNumber,
  formatPercent,
  formatRegionalMetric,
  metricValue,
  municipalitySectorKeys,
  mixHexColors,
  numericMetricValue,
  regionalAdminPreviewStyles,
  regionalMetricValue,
  regionSectorModes,
  sectorModeKey,
  sectorModeLabel,
} from "globe/controller/regional_profiles/shared"

export function applyRegionalStateCoreMethods(GlobeController) {
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

  GlobeController.prototype._regionalDistrictEconomyEnabled = function(region = this._regionalEconomyRegion?.()) {
    return !!(
      region &&
      region.mode === "economic" &&
      this._hasActiveLocalProfile?.() &&
      this._localProfileRegion?.()?.key === region.key &&
      this._regionalEconomyMapView?.(region) === "district"
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

  GlobeController.prototype._regionalDistrictDisplayScore = function(record, region = this._regionalEconomyRegion?.()) {
    return this._regionalEconomyMetricValueForGranularity?.(record, region, "district")
  }

  GlobeController.prototype._regionalDistrictRankedRecords = function(region = this._regionalEconomyRegion?.()) {
    const records = Array.isArray(this._localProfileRegionalDistrictCatalog) ? this._localProfileRegionalDistrictCatalog : []
    return records
      .slice()
      .sort((left, right) =>
        (this._regionalDistrictDisplayScore?.(right, region) || 0) - (this._regionalDistrictDisplayScore?.(left, region) || 0) ||
        (left.country_name || "").localeCompare(right.country_name || "") ||
        (left.name || "").localeCompare(right.name || "")
      )
  }

  GlobeController.prototype._regionalDistrictRankForRecord = function(record, region = this._regionalEconomyRegion?.()) {
    if (!record?.id) return null
    const ranked = this._regionalDistrictRankedRecords?.(region)
    const index = ranked.findIndex(item => item?.id === record.id)
    if (index < 0) return null
    return { rank: index + 1, total: ranked.length }
  }

  GlobeController.prototype._regionalDistrictAccent = function(record, region = this._regionalEconomyRegion?.()) {
    const records = Array.isArray(this._localProfileRegionalDistrictCatalog) && this._localProfileRegionalDistrictCatalog.length > 0
      ? this._localProfileRegionalDistrictCatalog
      : [record]
    const styles = regionalAdminPreviewStyles(records, entry => this._regionalDistrictDisplayScore?.(entry, region))
    return styles[record?.id]?.accentCss || "#2f7ea7"
  }

  GlobeController.prototype._regionalAdminCoordinates = function(record) {
    const lat = numericMetricValue(record?.lat)
    const lng = numericMetricValue(record?.lng)
    if (lat == null || lng == null) return null

    return { lat, lng, height: 450000 }
  }

  GlobeController.prototype._regionalDistrictCoordinates = function(record) {
    const lat = numericMetricValue(record?.lat)
    const lng = numericMetricValue(record?.lng)
    if (lat == null || lng == null) return null

    return { lat, lng, height: 220000 }
  }

  GlobeController.prototype._regionalAdminRecordForEntityId = function(entityId) {
    if (!entityId || !(this._regionalAdminEconomyIndex instanceof Map)) return null
    return this._regionalAdminEconomyIndex.get(entityId) || null
  }

  GlobeController.prototype._regionalDistrictRecordForEntityId = function(entityId) {
    if (!entityId || !(this._regionalDistrictEconomyIndex instanceof Map)) return null
    return this._regionalDistrictEconomyIndex.get(entityId) || null
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
}
