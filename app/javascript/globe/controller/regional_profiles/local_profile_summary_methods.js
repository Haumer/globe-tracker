import {
  DECIMAL_FORMAT,
  formatCompactCurrency,
  formatCompactNumber,
  formatPercent,
  formatRegionalMetric,
  metricValue,
  numericMetricValue,
  renderLocalProfileList,
  sumMetric,
} from "globe/controller/regional_profiles/shared"

export function applyRegionalLocalProfileSummaryMethods(GlobeController) {
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
                  ? "Country mode is source-backed by World Bank WDI"
                  : (granularityKey === "region" && currentMetric?.key !== "structure_signal"
                    ? "Region mode is source-backed by official DACH population feeds"
                    : granularityKey === "district"
                      ? "District mode is source-backed by official district-equivalent population feeds"
                      : "Local subnational detail needs explicit source-backed geometry and metrics"),
                currentMetric?.key === "structure_signal"
                  ? "Sector Focus · Region view can pivot toward automotive, chips, chemicals, energy, finance, or trade"
                  : "Sector Focus · Structure remains available as a separate derived metric",
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
                  "Official region-equivalent overlay across DACH",
                  `Metric · ${this._escapeHtml(regionMetricConfig?.label || "Metric")}`,
                  `Fill · Rank by ${this._escapeHtml(regionMetricConfig?.label || "metric")} across region-equivalent units`,
                  `Labels · Top 12 regions by ${this._escapeHtml(regionMetricConfig?.label || "metric")}`,
                  `Source · ${this._escapeHtml(regionMetricSource)}`,
                  "Caveat · Region-equivalent levels differ by country: Austrian Bundeslander, German Lander, Swiss cantons",
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
                "Local-only overlay · Admin-1 polygons for profiled DACH areas",
                `Focus · ${this._escapeHtml(sectorKey === "all" ? "All sectors" : sectorLabel)}`,
                `Fill · ${this._escapeHtml(sectorKey === "all" ? "overall industrial signal" : `${sectorLabel} signal`)} from cities, strategic sites, and curated power`,
                "Labels · Top 12 regions for the current focus",
                "Controls · Switch to District, Country, or Normal above for comparison",
                "Interaction · Click a polygon or label for the connector anchor",
                "Caveat · Derived industrial footprint, not official district GDP or employment yet",
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
                "Best next real step: add district-level economy and sector metrics on top of the new boundary overlay",
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
                "Map overlay uses official district-equivalent boundary snapshots",
                "Click a district polygon or label to open the anchored connector card",
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

}
