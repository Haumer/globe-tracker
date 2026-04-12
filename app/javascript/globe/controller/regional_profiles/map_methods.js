// Regional map/data overlays for local economic profiles.

import { COUNTRY_CENTROIDS } from "globe/country_centroids"
import { getDataSource, LABEL_DEFAULTS } from "globe/utils"
import {
  fetchRegionalBoundaryDataset,
  normalizeRegionalBoundaryLabel,
  REGIONAL_ADMIN_BOUNDARY_URLS,
  regionalAdminPreviewLabel,
  regionalAdminPreviewStyles,
  regionalAreaMetricLabel,
  regionalEconomyBorderStyles,
  regionalEconomyMetricLabel,
  titleizeProfileKey,
} from "globe/controller/regional_profiles/shared"

function clearRegionalLayer(controller, sourceKey, entitiesKey, { indexKey = null, resetBorderStyles = false, refreshBorders = false } = {}) {
  const ds = controller._ds[sourceKey]
  const entities = Array.isArray(controller[entitiesKey]) ? controller[entitiesKey] : []

  if (ds) {
    ds.entities.suspendEvents()
    entities.forEach(entity => ds.entities.remove(entity))
    ds.entities.resumeEvents()
    ds.show = false
  }

  controller[entitiesKey] = []
  if (indexKey) controller[indexKey] = new Map()
  if (resetBorderStyles) controller._regionalEconomyBorderStyles = null
  if (refreshBorders && controller.selectedCountries?.size > 0) controller.updateBorderColors?.()
  controller._requestRender?.()
}

function clearRegionalMapsExcept(controller, keepKey = null) {
  const clearers = {
    country: controller._clearRegionalEconomyMap,
    admin: controller._clearRegionalAdminEconomyMap,
    district: controller._clearRegionalDistrictMap,
    municipality: controller._clearRegionalMunicipalityMap,
  }

  Object.entries(clearers).forEach(([key, clear]) => {
    if (key !== keepKey) clear?.call(controller)
  })
}

function boundaryFeatures(featureCollection) {
  if (Array.isArray(featureCollection?.features)) return featureCollection.features
  return Array.isArray(featureCollection) ? featureCollection : []
}

function outerRings(geometry) {
  if (!geometry) return []
  if (geometry.type === "Polygon") return [geometry.coordinates[0]]
  if (geometry.type === "MultiPolygon") return geometry.coordinates.map(polygon => polygon[0])
  return []
}

function topRecordIds(records, scoreForRecord, limit) {
  return new Set(
    records
      .slice()
      .sort((left, right) =>
        (scoreForRecord(right) || 0) - (scoreForRecord(left) || 0) ||
        (left.country_name || "").localeCompare(right.country_name || "") ||
        (left.name || "").localeCompare(right.name || "")
      )
      .slice(0, limit)
      .map(record => record.id)
  )
}

function prepareRegionalDataSource(controller, dataSource, entitiesKey, indexKey = null) {
  dataSource.show = true
  dataSource.entities.suspendEvents()
  ;(controller[entitiesKey] || []).forEach(entity => dataSource.entities.remove(entity))
  controller[entitiesKey] = []
  if (indexKey) controller[indexKey] = new Map()
}

function addBoundaryGeometryEntities({ Cesium, dataSource, entities, index, record, geometry, style, prefix }) {
  outerRings(geometry).forEach((ring, ringIndex) => {
    if (!Array.isArray(ring) || ring.length < 3) return

    const positions = ring.map(coord => Cesium.Cartesian3.fromDegrees(coord[0], coord[1]))
    const fillId = `${prefix}-fill-${record.id}-${ringIndex}`
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
    entities.push(fillEntity)
    index?.set(fillId, record)

    const lineId = `${prefix}-line-${record.id}-${ringIndex}`
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
    entities.push(lineEntity)
    index?.set(lineId, record)
  })
}

export function applyRegionalMapMethods(GlobeController) {
  GlobeController.prototype.getRegionalEconomyDataSource = function() {
    return getDataSource(this.viewer, this._ds, "regionalEconomy")
  }

  GlobeController.prototype.getRegionalAdminEconomyDataSource = function() {
    return getDataSource(this.viewer, this._ds, "regionalAdminEconomy")
  }

  GlobeController.prototype.getRegionalDistrictEconomyDataSource = function() {
    return getDataSource(this.viewer, this._ds, "regionalDistrictEconomy")
  }

  GlobeController.prototype.getRegionalMunicipalityDataSource = function() {
    return getDataSource(this.viewer, this._ds, "regionalMunicipalities")
  }

  GlobeController.prototype._clearRegionalEconomyMap = function() {
    clearRegionalLayer(this, "regionalEconomy", "_regionalEconomyMapEntities", {
      resetBorderStyles: true,
      refreshBorders: true,
    })
  }

  GlobeController.prototype._clearRegionalAdminEconomyMap = function() {
    clearRegionalLayer(this, "regionalAdminEconomy", "_regionalAdminEconomyEntities", {
      indexKey: "_regionalAdminEconomyIndex",
      refreshBorders: true,
    })
  }

  GlobeController.prototype._clearRegionalDistrictMap = function() {
    clearRegionalLayer(this, "regionalDistrictEconomy", "_regionalDistrictEconomyEntities", {
      indexKey: "_regionalDistrictEconomyIndex",
      refreshBorders: true,
    })
  }

  GlobeController.prototype._clearRegionalMunicipalityMap = function() {
    clearRegionalLayer(this, "regionalMunicipalities", "_regionalMunicipalityEntities", {
      indexKey: "_regionalMunicipalityIndex",
    })
  }

  GlobeController.prototype._syncRegionalEconomyMap = function() {
    const region = this._regionalEconomyRegion?.()
    const view = this._regionalEconomyMapView?.(region)
    const cityDataSource = this._ds["cities"]
    if (cityDataSource) cityDataSource.show = this.citiesVisible && !["admin", "district"].includes(view)

    if (!region || view === "off" || view === "district") {
      clearRegionalMapsExcept(this)
      return
    }

    if (this._regionalAdminEconomyEnabled?.(region)) {
      clearRegionalMapsExcept(this, "admin")
      this._loadRegionalAdminEconomyMap?.(region)
      return
    }

    if (this._regionalDistrictEconomyEnabled?.(region)) {
      clearRegionalMapsExcept(this, "district")
      this._loadRegionalDistrictMap?.(region)
      return
    }

    if (this._regionalMunicipalityEconomyEnabled?.(region)) {
      clearRegionalMapsExcept(this, "municipality")
      this._loadRegionalMunicipalityMap?.(region)
      return
    }

    clearRegionalMapsExcept(this, "country")
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

  GlobeController.prototype._ensureRegionalDistrictBoundaries = async function(region) {
    const countryCodes = Array.isArray(region?.countryCodes) ? region.countryCodes : []
    const cacheKey = countryCodes.join("|")

    let payload = this._localProfileRegionalDistrictBoundaryCache
    if (!Array.isArray(payload?.features) || this._localProfileRegionalDistrictBoundaryCountryKey !== cacheKey) {
      const response = await fetch(`/api/regional_district_boundaries?country_codes=${encodeURIComponent(countryCodes.join(","))}`)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      payload = await response.json()
      this._localProfileRegionalDistrictBoundaryCache = payload
      this._localProfileRegionalDistrictBoundaryCountryKey = cacheKey
    }

    return payload
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

    const region = this._localProfileRegion?.()
    const countryCodes = Array.isArray(region?.countryCodes) ? region.countryCodes : []
    const urls = REGIONAL_ADMIN_BOUNDARY_URLS.map(url => {
      if (!url.startsWith("/") || countryCodes.length === 0) return url

      const separator = url.includes("?") ? "&" : "?"
      return `${url}${separator}country_codes=${encodeURIComponent(countryCodes.join(","))}`
    })
    const payload = await fetchRegionalBoundaryDataset(urls)
    if (!Array.isArray(payload?.features) || payload.features.length === 0) {
      throw new Error("Admin boundary dataset unavailable")
    }
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

  GlobeController.prototype._findRegionalDistrictBoundaryFeature = function(record, featureCollection) {
    const features = Array.isArray(featureCollection?.features) ? featureCollection.features : Array.isArray(featureCollection) ? featureCollection : []
    if (!record || features.length === 0) return null

    const countryCodes = new Set([
      `${record.country_code || ""}`.toUpperCase(),
      `${record.country_code_alpha3 || ""}`.toUpperCase(),
    ].filter(Boolean))

    const countryFeatures = features.filter(feature => {
      const featureCodes = [
        `${feature?.properties?.country_code || ""}`.toUpperCase(),
        `${feature?.properties?.country_code_alpha3 || ""}`.toUpperCase(),
      ].filter(Boolean)
      return featureCodes.some(code => countryCodes.has(code))
    })

    const sourceGeo = `${record.source_geo || ""}`.trim().toUpperCase()
    if (sourceGeo) {
      const directMatch = countryFeatures.find(feature =>
        `${feature?.properties?.source_geo || ""}`.trim().toUpperCase() === sourceGeo
      )
      if (directMatch) return directMatch
    }

    const desiredNames = new Set(
      [record.name, ...(Array.isArray(record.boundary_names) ? record.boundary_names : [])]
        .map(normalizeRegionalBoundaryLabel)
        .filter(Boolean)
    )
    if (desiredNames.size === 0) return null

    const regionName = normalizeRegionalBoundaryLabel(record.region_name)
    const matching = countryFeatures.filter(feature => {
      const featureNames = [
        feature?.properties?.name,
        ...(Array.isArray(feature?.properties?.boundary_names) ? feature.properties.boundary_names : []),
      ]
        .map(normalizeRegionalBoundaryLabel)
        .filter(Boolean)

      return featureNames.some(name => desiredNames.has(name))
    })
    if (matching.length === 0) return null
    if (!regionName) return matching[0]

    return matching.find(feature =>
      normalizeRegionalBoundaryLabel(feature?.properties?.region_name) === regionName
    ) || matching[0]
  }

  GlobeController.prototype._loadRegionalEconomyMap = async function(region = this._regionalEconomyRegion?.()) {
    if (!region || region.mode !== "economic") {
      this._regionalIndicatorMapData = []
      clearRegionalMapsExcept(this)
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
      clearRegionalMapsExcept(this)
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

  GlobeController.prototype._loadRegionalDistrictMap = async function(region = this._localProfileRegion?.()) {
    if (!this._regionalDistrictEconomyEnabled?.(region)) {
      this._clearRegionalDistrictMap?.()
      return
    }

    const token = ++this._localProfileRegionalDistrictBoundaryFetchToken

    try {
      const [records, boundaryCollection] = await Promise.all([
        this._ensureRegionalDistrictRecords(region),
        this._ensureRegionalDistrictBoundaries(region),
      ])
      if (token !== this._localProfileRegionalDistrictBoundaryFetchToken || !this._regionalDistrictEconomyEnabled?.(region)) return

      this._renderRegionalDistrictMap?.(region, records, boundaryCollection)
    } catch (error) {
      console.error("Failed to load regional district map:", error)
      if (token !== this._localProfileRegionalDistrictBoundaryFetchToken) return
      this._clearRegionalDistrictMap?.()
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
    prepareRegionalDataSource(this, dataSource, "_regionalEconomyMapEntities")

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

    const features = boundaryFeatures(boundaryCollection)
    if (features.length === 0) {
      this._clearRegionalAdminEconomyMap?.()
      return
    }

    const dataSource = this.getRegionalAdminEconomyDataSource()
    prepareRegionalDataSource(this, dataSource, "_regionalAdminEconomyEntities", "_regionalAdminEconomyIndex")

    const sectorKey = this._regionalEconomySectorMode?.(region)
    const sectorLabel = this._regionalEconomySectorLabel?.(region)
    const metricConfig = this._regionalEconomyMetricConfigForGranularity?.(region, "region")
    const structureMetric = metricConfig?.key === "structure_signal"
    const scoreForRecord = (entry) => this._regionalAdminDisplayScore?.(entry, sectorKey)
    const styles = regionalAdminPreviewStyles(records, scoreForRecord)
    const labeledIds = topRecordIds(records, scoreForRecord, 12)

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
        addBoundaryGeometryEntities({
          Cesium,
          dataSource,
          entities: this._regionalAdminEconomyEntities,
          index: this._regionalAdminEconomyIndex,
          record: renderRecord,
          geometry: feature.geometry,
          style,
          prefix: "radmin",
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

  GlobeController.prototype._renderRegionalDistrictMap = function(region, records = [], boundaryCollection = null) {
    if (!this._regionalDistrictEconomyEnabled?.(region) || !Array.isArray(records) || records.length === 0) {
      this._clearRegionalDistrictMap?.()
      return
    }

    const Cesium = window.Cesium
    if (!Cesium) return

    const features = boundaryFeatures(boundaryCollection)
    if (features.length === 0) {
      this._clearRegionalDistrictMap?.()
      return
    }

    const dataSource = this.getRegionalDistrictEconomyDataSource()
    prepareRegionalDataSource(this, dataSource, "_regionalDistrictEconomyEntities", "_regionalDistrictEconomyIndex")

    const metricConfig = this._regionalEconomyMetricConfigForGranularity?.(region, "district")
    const scoreForRecord = (entry) => this._regionalDistrictDisplayScore?.(entry, region)
    const styles = regionalAdminPreviewStyles(records, scoreForRecord)
    const labeledIds = topRecordIds(records, scoreForRecord, 16)

    records.forEach(record => {
      const feature = this._findRegionalDistrictBoundaryFeature?.(record, features)
      if (!feature?.geometry) return

      const renderRecord = (record?.lat == null || record?.lng == null)
        ? {
            ...record,
            lat: feature.properties?.latitude,
            lng: feature.properties?.longitude,
            region_name: record.region_name || feature.properties?.region_name,
          }
        : record

      const baseStyle = styles[record.id] || {
        accentCss: "#2f7ea7",
        fillColor: Cesium.Color.fromCssColorString("#2f7ea7").withAlpha(0.12),
        lineColor: Cesium.Color.fromCssColorString("#2f7ea7").withAlpha(0.98),
        lineWidth: 2.6,
      }
      const style = {
        ...baseStyle,
        fillColor: Cesium.Color.fromCssColorString(baseStyle.accentCss || "#2f7ea7").withAlpha(0.1),
        lineColor: Cesium.Color.fromCssColorString(baseStyle.accentCss || "#2f7ea7").withAlpha(0.98),
        lineWidth: Math.max(baseStyle.lineWidth || 0, 2.4),
      }

      addBoundaryGeometryEntities({
        Cesium,
        dataSource,
        entities: this._regionalDistrictEconomyEntities,
        index: this._regionalDistrictEconomyIndex,
        record: renderRecord,
        geometry: feature.geometry,
        style,
        prefix: "rdist",
      })

      const coordinates = this._regionalDistrictCoordinates?.(renderRecord)
      if (!coordinates || !labeledIds.has(renderRecord.id)) return

      const labelId = `rdist-${renderRecord.id}`
      const labelEntity = dataSource.entities.add({
        id: labelId,
        position: Cesium.Cartesian3.fromDegrees(coordinates.lng, coordinates.lat, 3200),
        point: {
          pixelSize: 11,
          color: Cesium.Color.fromCssColorString(style.accentCss).withAlpha(0.96),
          outlineColor: Cesium.Color.BLACK.withAlpha(0.7),
          outlineWidth: 2,
          heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
        },
        label: {
          text: regionalAreaMetricLabel(renderRecord, metricConfig, scoreForRecord(renderRecord)),
          font: "bold 11px JetBrains Mono, monospace",
          fillColor: Cesium.Color.WHITE.withAlpha(0.96),
          outlineColor: LABEL_DEFAULTS.outlineColor(),
          outlineWidth: LABEL_DEFAULTS.outlineWidth,
          style: LABEL_DEFAULTS.style(),
          verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
          horizontalOrigin: Cesium.HorizontalOrigin.CENTER,
          pixelOffset: LABEL_DEFAULTS.pixelOffsetAbove(),
          scaleByDistance: new Cesium.NearFarScalar(4e4, 1, 1.2e6, 0.12),
          translucencyByDistance: new Cesium.NearFarScalar(4e4, 1, 1.2e6, 0),
          disableDepthTestDistance: Number.POSITIVE_INFINITY,
          showBackground: true,
          backgroundColor: Cesium.Color.fromCssColorString("#081019").withAlpha(0.78),
        },
      })
      this._regionalDistrictEconomyEntities.push(labelEntity)
      this._regionalDistrictEconomyIndex.set(labelId, renderRecord)
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
    prepareRegionalDataSource(this, dataSource, "_regionalMunicipalityEntities", "_regionalMunicipalityIndex")

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
}
