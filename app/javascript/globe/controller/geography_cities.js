import { getDataSource, LABEL_DEFAULTS } from "globe/utils"

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

      const placesData = await placesRes.json()
      const urbanData = await urbanRes.json()

      this._citiesData = placesData.features
        .filter(feature => feature.geometry && feature.properties)
        .map(feature => ({
          name: feature.properties.name || feature.properties.nameascii || "",
          country: feature.properties.adm0name || feature.properties.sov0name || "",
          population: feature.properties.pop_max || feature.properties.pop_min || 0,
          lat: feature.geometry.coordinates[1],
          lng: feature.geometry.coordinates[0],
          capital: feature.properties.adm0cap === 1,
          rank: feature.properties.rank_max || 0,
        }))
        .filter(city => city.name && city.population > 100000)
        .sort((a, b) => b.population - a.population)

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

    const maxPop = cities.length > 0 ? cities[0].population : 1
    cities.forEach(city => addCityEntity.call(this, Cesium, dataSource, city, maxPop))
    renderUrbanAreas.call(this, Cesium, dataSource)
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
    const pixelSize = city.capital ? 7 : Math.max(3, Math.round(popRatio * 6 + 2))
    const color = city.capital
      ? Cesium.Color.fromCssColorString("#ffd54f")
      : Cesium.Color.fromCssColorString("#e0e0e0")

    const entity = dataSource.entities.add({
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
        font: city.capital ? "bold 15px JetBrains Mono, monospace" : LABEL_DEFAULTS.font,
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
