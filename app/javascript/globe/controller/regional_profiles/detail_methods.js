import {
  DECIMAL_FORMAT,
  formatCompactNumber,
  formatRegionalMetric,
  metricValue,
  municipalitySectorNames,
  regionSectorModes,
  sectorModeKey,
  titleizeProfileKey,
} from "globe/controller/regional_profiles/shared"

export function applyRegionalDetailMethods(GlobeController) {
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

  GlobeController.prototype._buildRegionalAreaMetricContextForGranularity = function(record, granularityKey = "region") {
    if (!record) return null

    const region = this._regionalEconomyRegion?.()
    const metricConfig = this._regionalEconomyMetricConfigForGranularity?.(region, granularityKey)
    const metricValueForRecord = this._regionalEconomyMetricValueForGranularity?.(record, region, granularityKey)
    const metricSourceSummary = this._regionalEconomyMetricSourceSummaryForGranularity?.(region, granularityKey)
    const coordinates = granularityKey === "district"
      ? this._regionalDistrictCoordinates?.(record)
      : this._regionalAdminCoordinates?.(record)
    const rank = granularityKey === "district"
      ? this._regionalDistrictRankForRecord?.(record, region)
      : this._regionalAdminRankForRecord?.(record, "all")
    const accentColor = granularityKey === "district"
      ? this._regionalDistrictAccent?.(record, region)
      : this._regionalAdminEconomyAccent?.(record)
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
      statusLabel: granularityKey,
      icon: "fa-chart-area",
      accentColor,
      eyebrow: granularityKey === "district" ? "DISTRICT METRIC" : "REGIONAL METRIC",
      title: record.name || (granularityKey === "district" ? "District" : "Region"),
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

  GlobeController.prototype._buildRegionalAreaMetricContext = function(record) {
    return this._buildRegionalAreaMetricContextForGranularity?.(record, "region")
  }

  GlobeController.prototype.showRegionalAreaMetricDetail = function(record, options = {}) {
    if (!record) return

    const granularityKey = options.granularityKey || "region"
    const region = this._regionalEconomyRegion?.()
    const metricConfig = this._regionalEconomyMetricConfigForGranularity?.(region, granularityKey)
    const selectedMetricValue = this._regionalEconomyMetricValueForGranularity?.(record, region, granularityKey)
    const selectedMetricSource = this._regionalEconomyMetricSourceSummaryForGranularity?.(region, granularityKey)
    const coordinates = granularityKey === "district"
      ? this._regionalDistrictCoordinates?.(record)
      : this._regionalAdminCoordinates?.(record)
    const accentColor = granularityKey === "district"
      ? this._regionalDistrictAccent?.(record, region)
      : this._regionalAdminEconomyAccent?.(record)
    const rank = granularityKey === "district"
      ? this._regionalDistrictRankForRecord?.(record, region)
      : this._regionalAdminRankForRecord?.(record, "all")

    const anchoredRecord = {
      ...record,
      ...(coordinates ? { lat: coordinates.lat, lng: coordinates.lng } : {}),
      accent_color: accentColor,
      selected_rank: rank,
      selected_metric_key: metricConfig?.key,
      selected_metric_label: metricConfig?.label,
      selected_metric_short_label: metricConfig?.shortLabel,
      selected_metric_value: selectedMetricValue,
      selected_metric_source: selectedMetricSource,
    }

    if (!options.contextOnly && this._showCompactEntityDetail) {
      this._showCompactEntityDetail("regional_area_metric", anchoredRecord, {
        id: record.id || record.name,
        picked: options.picked,
      })
    }

    const context = this._buildRegionalAreaMetricContextForGranularity?.(record, granularityKey)
    if (context && this._setSelectedContext) {
      this._setSelectedContext(context, {
        openRightPanel: options.openRightPanel === true || this._currentRightPanelTab?.() === "context",
      })
    }

    if (this.hasDetailPanelTarget) this.detailPanelTarget.style.display = "none"
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
    if (!structureMetric) {
      this.showRegionalAreaMetricDetail?.(record, { ...options, granularityKey: "region" })
      return
    }

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

  GlobeController.prototype.showRegionalDistrictDetail = function(record, options = {}) {
    this.showRegionalAreaMetricDetail?.(record, { ...options, granularityKey: "district" })
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
}
