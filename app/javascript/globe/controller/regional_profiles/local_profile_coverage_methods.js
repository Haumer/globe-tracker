import {
  regionCountryCodes,
  renderLocalProfileList,
  sourceStatusLabel,
  titleizeProfileKey,
} from "globe/controller/regional_profiles/shared"

function localProfileMatches(controller, region, token, tokenKey) {
  return token === controller[tokenKey] && controller._localProfileRegion?.()?.key === region.key
}

function renderLocalProfileMessage(shell, title, message) {
  shell.innerHTML = `
    <div class="local-profile-section-title">${title}</div>
    <div class="local-profile-empty-row">${message}</div>
  `
}

function sortedCountEntries(counts, limit = null) {
  const entries = Object.entries(counts).sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
  return Number.isFinite(limit) ? entries.slice(0, limit) : entries
}

function renderCountList(controller, counts, emptyLabel, limit = null) {
  return renderLocalProfileList(
    sortedCountEntries(counts, limit).map(([name, count]) => `${controller._escapeHtml(name)} · ${count}`),
    emptyLabel
  )
}

export function applyRegionalLocalProfileCoverageMethods(GlobeController) {
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

      if (!localProfileMatches(this, region, token, "_localProfileDataSourceFetchToken")) return

      const regionalSources = (sources || []).filter(source =>
        Array.isArray(source.region_keys) ? source.region_keys.includes(region.key) : false
      )

      if (regionalSources.length === 0) {
        renderLocalProfileMessage(shell, "Source Coverage", "No registered data sources for this region yet.")
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
              ${renderCountList(this, byStatus, "No status coverage yet")}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">By Country</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderCountList(this, byCountry, "No country coverage yet")}
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
      if (!localProfileMatches(this, region, token, "_localProfileDataSourceFetchToken")) return
      renderLocalProfileMessage(shell, "Source Coverage", "Source coverage failed to load.")
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

      if (!localProfileMatches(this, region, token, "_localProfilePowerPlantFetchToken")) return

      const regionalProfiles = (profiles || []).filter(profile => countryNames.has(profile.country_name))
      if (regionalProfiles.length === 0) {
        renderLocalProfileMessage(shell, "Curated Power Coverage", "No curated power coverage loaded for this region yet.")
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
              ${renderCountList(this, byCountry, "No country coverage yet")}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Fuel Mix</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderCountList(this, byFuel, "No fuel mix yet")}
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
      if (!localProfileMatches(this, region, token, "_localProfilePowerPlantFetchToken")) return
      renderLocalProfileMessage(shell, "Curated Power Coverage", "Curated power coverage failed to load.")
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

      if (!localProfileMatches(this, region, token, "_localProfileCityFetchToken")) return

      const regionalProfiles = (profiles || []).filter(profile => countryNames.has(profile.country_name))
      if (regionalProfiles.length === 0) {
        renderLocalProfileMessage(shell, "Economic City Coverage", "No city coverage loaded for this region yet.")
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
              ${renderCountList(this, byCountry, "No country coverage yet")}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Top Roles</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderCountList(this, byRole, "No role coverage yet", 6)}
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
      if (!localProfileMatches(this, region, token, "_localProfileCityFetchToken")) return
      renderLocalProfileMessage(shell, "Economic City Coverage", "City coverage failed to load.")
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

      if (!localProfileMatches(this, region, token, "_localProfileStrategicSiteFetchToken")) return

      const regionalSites = (sites || []).filter(site => {
        if (!site) return false
        if (countryCodes.size > 0 && countryCodes.has(site.country_code)) return true
        return countryNames.has(site.country_name)
      })

      if (regionalSites.length === 0) {
        renderLocalProfileMessage(shell, "Strategic Site Coverage", "No strategic sites loaded for this region yet.")
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

      const totalCategoryCount = Object.keys(categoryCounts).length
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
              ${renderCountList(this, countryCounts, "No country coverage yet")}
            </ul>
          </div>
          <div class="local-profile-section">
            <div class="local-profile-section-title">Top Sectors</div>
            <ul class="local-profile-list local-profile-list--compact">
              ${renderCountList(this, categoryCounts, "No sector mix yet", 5)}
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
      if (!localProfileMatches(this, region, token, "_localProfileStrategicSiteFetchToken")) return
      renderLocalProfileMessage(shell, "Strategic Site Coverage", "Strategic-site coverage failed to load.")
    }
  }
}
