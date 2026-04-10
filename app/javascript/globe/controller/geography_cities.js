import { getDataSource, LABEL_DEFAULTS } from "globe/utils"

function normalizeCityIdentity(name = "", country = "") {
  const normalize = value => `${value || ""}`
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")

  const normalizedName = normalize(name)
  const normalizedCountry = normalize(country)
  if (!normalizedName || !normalizedCountry) return null
  return `${normalizedCountry}:${normalizedName}`
}

function buildCityProfileIndex(profiles = []) {
  const index = new Map()

  profiles.forEach(profile => {
    const names = [profile.name, ...(profile.aliases || [])]
    names.forEach(name => {
      const key = normalizeCityIdentity(name, profile.country_name)
      if (key) index.set(key, profile)
    })
  })

  return index
}

function applyCityProfile(city, profile) {
  const roleTags = Array.isArray(profile?.role_tags) ? profile.role_tags : (city.roleTags || [])
  const strategicSectors = Array.isArray(profile?.strategic_sectors) ? profile.strategic_sectors : (city.strategicSectors || [])
  const profilePriority = Number.isFinite(profile?.priority) ? profile.priority : (Number.isFinite(city.profilePriority) ? city.profilePriority : 9999)

  return {
    ...city,
    id: profile?.id || city.id || normalizeCityIdentity(city.name, profile?.country_name || city.country),
    country: profile?.country_name || city.country,
    lat: profile?.lat ?? city.lat,
    lng: profile?.lng ?? city.lng,
    capital: city.capital || roleTags.includes("capital"),
    adminArea: profile?.admin_area || city.adminArea || "",
    aliases: Array.isArray(profile?.aliases) ? profile.aliases : (city.aliases || []),
    roleTags,
    strategicSectors,
    summary: profile?.summary || city.summary || "",
    profilePriority,
    isProfiled: !!profile,
  }
}

function cityFromProfile(profile) {
  return applyCityProfile({
    id: profile.id,
    name: profile.name,
    country: profile.country_name || "",
    population: profile.population || 0,
    lat: profile.lat,
    lng: profile.lng,
    capital: false,
    rank: 0,
    aliases: profile.aliases || [],
    roleTags: [],
    strategicSectors: [],
    summary: "",
    adminArea: "",
    profilePriority: profile.priority,
  }, profile)
}

function sortCities(left, right) {
  return Number(Boolean(right.isProfiled)) - Number(Boolean(left.isProfiled)) ||
    (left.profilePriority || 9999) - (right.profilePriority || 9999) ||
    Number(Boolean(right.capital)) - Number(Boolean(left.capital)) ||
    (right.population || 0) - (left.population || 0) ||
    (left.name || "").localeCompare(right.name || "")
}

function cityPopulationLabel(population) {
  if (!population || population <= 0) return "—"
  if (population >= 1_000_000) return `${(population / 1_000_000).toFixed(1)}M`
  return `${Math.round(population / 1000)}k`
}

export function applyGeographyCityMethods(GlobeController) {
  GlobeController.prototype.toggleCities = function() {
    this.citiesVisible = this.hasCitiesToggleTarget && this.citiesToggleTarget.checked
    if (this.citiesVisible) {
      if (!this._citiesLoaded) this.loadCities()
      else this.renderCities()
    } else {
      this.clearCities()
    }
    this._savePrefs()
  }

  GlobeController.prototype.getCitiesDataSource = function() {
    return getDataSource(this.viewer, this._ds, "cities")
  }

  GlobeController.prototype.loadCities = async function() {
    try {
      const [placesRes, urbanRes] = await Promise.all([
        fetch("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places_simple.geojson"),
        fetch("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_urban_areas.geojson"),
      ])
      const cityProfilesRes = await fetch("/api/city_profiles").catch(() => null)

      const placesData = await placesRes.json()
      const urbanData = await urbanRes.json()
      const cityProfiles = cityProfilesRes?.ok ? await cityProfilesRes.json() : []
      const profileRecords = Array.isArray(cityProfiles) ? cityProfiles : []
      const cityProfileIndex = buildCityProfileIndex(profileRecords)
      const matchedProfileIds = new Set()

      const naturalEarthCities = placesData.features
        .filter(feature => feature.geometry && feature.properties)
        .map(feature => ({
          id: normalizeCityIdentity(
            feature.properties.name || feature.properties.nameascii || "",
            feature.properties.adm0name || feature.properties.sov0name || ""
          ),
          name: feature.properties.name || feature.properties.nameascii || "",
          country: feature.properties.adm0name || feature.properties.sov0name || "",
          population: feature.properties.pop_max || feature.properties.pop_min || 0,
          lat: feature.geometry.coordinates[1],
          lng: feature.geometry.coordinates[0],
          capital: feature.properties.adm0cap === 1,
          rank: feature.properties.rank_max || 0,
        }))
        .map(city => {
          const profile = cityProfileIndex.get(normalizeCityIdentity(city.name, city.country))
          if (profile?.id) matchedProfileIds.add(profile.id)
          return applyCityProfile(city, profile)
        })
        .filter(city => city.name && (city.population > 100000 || city.isProfiled))

      const supplementalProfileCities = profileRecords
        .filter(profile => !matchedProfileIds.has(profile.id))
        .map(cityFromProfile)

      this._localProfileCityProfiles = profileRecords
      this._citiesData = [...naturalEarthCities, ...supplementalProfileCities].sort(sortCities)

      this._urbanAreas = urbanData.features
        .filter(feature => feature.geometry)
        .map(feature => ({
          coords: feature.geometry.coordinates,
          type: feature.geometry.type,
          area: feature.properties.area_sqkm || 0,
        }))

      this._citiesLoaded = true
      this.renderCities()
    } catch (error) {
      console.error("Failed to load cities:", error, error.message, error.stack)
    }
  }

  GlobeController.prototype.clearCities = function() {
    const ds = this._ds["cities"]
    if (ds) this._cityEntities.forEach(entity => ds.entities.remove(entity))
    this._cityEntities = []
  }

  GlobeController.prototype.renderCities = async function() {
    const Cesium = window.Cesium
    this.clearCities()
    if (!this.citiesVisible || this._citiesData.length === 0) return

    const dataSource = this.getCitiesDataSource()
    dataSource.show = true
    let cities = filterCities.call(this)
    cities = cities.slice(0, 500)

    if (this.terrainEnabled && this.viewer.terrainProvider && !(this.viewer.terrainProvider instanceof Cesium.EllipsoidTerrainProvider)) {
      const positions = cities.map(city => Cesium.Cartographic.fromDegrees(city.lng, city.lat))
      try {
        await Cesium.sampleTerrainMostDetailed(this.viewer.terrainProvider, positions)
      } catch (error) {
        console.warn("Terrain sampling failed for cities:", error)
      }
    }

    if (!this.citiesVisible) return

    const maxPop = Math.max(1, ...cities.map(city => city.population || 0))
    cities.forEach(city => addCityEntity.call(this, Cesium, dataSource, city, maxPop))
    renderUrbanAreas.call(this, Cesium, dataSource)
  }

  GlobeController.prototype.showCityDetail = function(city) {
    const accent = city.capital ? "#ffd54f" : (city.isProfiled ? "#80cbc4" : "#e0e0e0")
    const roleTags = (city.roleTags || []).slice(0, 4).map(tag => titleizeCityField(tag)).join(" · ")
    const sectors = (city.strategicSectors || []).slice(0, 4).map(sector => titleizeCityField(sector)).join(" · ")
    const sourceLabel = city.isProfiled ? "Regional city profile catalog + Natural Earth" : "Natural Earth"

    this.detailContentTarget.innerHTML = `
      <div class="detail-callsign" style="color:${accent};">
        <i class="fa-solid fa-city" style="margin-right:6px;"></i>${this._escapeHtml(city.name)}
      </div>
      <div class="detail-country">${this._escapeHtml([city.adminArea, city.country].filter(Boolean).join(" · ") || "Unknown")}</div>
      <div class="detail-grid">
        <div class="detail-field">
          <span class="detail-label">Population</span>
          <span class="detail-value">${this._escapeHtml(cityPopulationLabel(city.population))}</span>
        </div>
        <div class="detail-field">
          <span class="detail-label">Profile</span>
          <span class="detail-value">${city.capital ? "Capital" : (city.isProfiled ? "Strategic city" : "Global city")}</span>
        </div>
        ${roleTags ? `
        <div class="detail-field">
          <span class="detail-label">Roles</span>
          <span class="detail-value">${this._escapeHtml(roleTags)}</span>
        </div>` : ""}
        ${sectors ? `
        <div class="detail-field">
          <span class="detail-label">Sectors</span>
          <span class="detail-value">${this._escapeHtml(sectors)}</span>
        </div>` : ""}
      </div>
      ${city.summary ? `
        <div style="margin-top:10px;padding:8px 10px;background:rgba(128,203,196,0.08);border:1px solid rgba(128,203,196,0.22);border-radius:6px;font:400 11px/1.5 var(--gt-sans);color:var(--gt-text);">
          ${this._escapeHtml(city.summary)}
        </div>
      ` : ""}
      <div style="margin-top:8px;font:400 9px var(--gt-mono);color:rgba(200,210,225,0.3);">Source: ${this._escapeHtml(sourceLabel)}</div>
    `

    this.detailPanelTarget.style.display = ""
  }
}

function filterCities() {
  if (this.selectedCountries.size > 0) {
    return this._citiesData.filter(city => this.selectedCountries.has(city.country))
  }
  if (this.hasActiveFilter() && this._activeCircle) {
    return this._citiesData.filter(city => this.pointPassesFilter(city.lat, city.lng))
  }
  return this._citiesData
}

function addCityEntity(Cesium, dataSource, city, maxPop) {
  try {
    const popRatio = city.population / maxPop
    const pixelSize = city.capital ? 7 : (city.isProfiled ? Math.max(5, Math.round(popRatio * 6 + 4)) : Math.max(3, Math.round(popRatio * 6 + 2)))
    const color = city.capital
      ? Cesium.Color.fromCssColorString("#ffd54f")
      : (city.isProfiled ? Cesium.Color.fromCssColorString("#80cbc4") : Cesium.Color.fromCssColorString("#e0e0e0"))

    const entity = dataSource.entities.add({
      id: `city-${city.id}`,
      properties: {
        cityId: city.id,
      },
      position: Cesium.Cartesian3.fromDegrees(city.lng, city.lat, 10),
      point: {
        pixelSize,
        color: color.withAlpha(0.9),
        outlineColor: color.withAlpha(0.5),
        outlineWidth: 1,
        heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
      label: {
        text: city.name,
        font: city.capital || city.isProfiled ? "bold 14px JetBrains Mono, monospace" : LABEL_DEFAULTS.font,
        fillColor: Cesium.Color.WHITE.withAlpha(0.95),
        outlineColor: LABEL_DEFAULTS.outlineColor(),
        outlineWidth: LABEL_DEFAULTS.outlineWidth,
        style: LABEL_DEFAULTS.style(),
        verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
        horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
        pixelOffset: LABEL_DEFAULTS.pixelOffsetAbove(),
        scaleByDistance: LABEL_DEFAULTS.scaleByDistance(),
        translucencyByDistance: LABEL_DEFAULTS.translucencyByDistance(),
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    })
    this._cityEntities.push(entity)
  } catch (error) {
    console.warn(`City entity failed: ${city.name}`, error.message)
  }
}

function titleizeCityField(value = "") {
  return `${value || ""}`
    .split(/[\s_-]+/)
    .filter(Boolean)
    .map(part => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ")
}

function renderUrbanAreas(Cesium, dataSource) {
  if (!this._urbanAreas?.length) return

  const urbanColor = Cesium.Color.fromCssColorString("#ffa726").withAlpha(0.35)
  const urbanOutline = Cesium.Color.fromCssColorString("#ffcc80").withAlpha(0.6)
  const filterBbox = this._selectedCountriesBbox
  const hasCircle = !!this._activeCircle

  this._urbanAreas.forEach(urban => {
    const rings = urban.type === "Polygon" ? [urban.coords] : urban.type === "MultiPolygon" ? urban.coords : []

    for (const polyCoords of rings) {
      const outerRing = polyCoords[0]
      if (!outerRing || outerRing.length < 3) continue

      let centroidLat = 0
      let centroidLng = 0
      for (const coord of outerRing) {
        centroidLng += coord[0]
        centroidLat += coord[1]
      }
      centroidLat /= outerRing.length
      centroidLng /= outerRing.length

      if (this.selectedCountries.size > 0) {
        if (filterBbox && (centroidLat < filterBbox.minLat || centroidLat > filterBbox.maxLat ||
            centroidLng < filterBbox.minLng || centroidLng > filterBbox.maxLng)) continue
        if (!this._pointInSelectedCountries(centroidLat, centroidLng)) continue
      } else if (hasCircle && !this.pointPassesFilter(centroidLat, centroidLng)) {
        continue
      }

      const positions = outerRing.map(coord => Cesium.Cartesian3.fromDegrees(coord[0], coord[1]))

      try {
        const entity = dataSource.entities.add({
          polygon: {
            hierarchy: positions,
            material: urbanColor,
            outline: true,
            outlineColor: urbanOutline,
            outlineWidth: 1,
            classificationType: Cesium.ClassificationType.BOTH,
          },
        })
        this._cityEntities.push(entity)
      } catch {
        // Skip failed urban polygons.
      }
    }
  })
}
