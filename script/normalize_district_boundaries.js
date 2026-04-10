#!/usr/bin/env node

const fs = require("fs")

const [sourceKey, outputPath] = process.argv.slice(2)
if (!sourceKey || !outputPath) {
  console.error("usage: normalize_district_boundaries.js <source_key> <output_path>")
  process.exit(1)
}

const input = fs.readFileSync(0, "utf8")
const payload = JSON.parse(input)

const GERMANY_STATE_NAMES = {
  BW: "Baden-Wuerttemberg",
  BY: "Bavaria",
  BE: "Berlin",
  BB: "Brandenburg",
  HB: "Bremen",
  HH: "Hamburg",
  HE: "Hesse",
  MV: "Mecklenburg-Vorpommern",
  NI: "Lower Saxony",
  NW: "North Rhine-Westphalia",
  RP: "Rhineland-Palatinate",
  SL: "Saarland",
  SN: "Saxony",
  ST: "Saxony-Anhalt",
  SH: "Schleswig-Holstein",
  TH: "Thuringia",
}

const AUSTRIA_STATE_NAMES = {
  "1": "Burgenland",
  "2": "Carinthia",
  "3": "Lower Austria",
  "4": "Upper Austria",
  "5": "Salzburg",
  "6": "Styria",
  "7": "Tyrol",
  "8": "Vorarlberg",
  "9": "Vienna",
}

const SWITZERLAND_SINGLE_DISTRICT_EQUIVALENTS = {
  "Appenzell Innerrhoden": "001600",
  "Basel-Stadt": "001200",
  "Geneve": "002500",
  "Genf": "002500",
  "Genève": "002500",
  Glarus: "000800",
  Neuchatel: "002400",
  "Neuchâtel": "002400",
  Nidwalden: "000700",
  Obwalden: "000600",
  Uri: "000400",
  Zug: "000900",
}

function compactPoint(point) {
  return [Number(point[0].toFixed(5)), Number(point[1].toFixed(5))]
}

function compactGeometry(geometry) {
  if (!geometry) return null
  if (geometry.type === "Polygon") {
    return {
      type: "Polygon",
      coordinates: geometry.coordinates.map(ring => ring.map(compactPoint)),
    }
  }
  if (geometry.type === "MultiPolygon") {
    return {
      type: "MultiPolygon",
      coordinates: geometry.coordinates.map(polygon => polygon.map(ring => ring.map(compactPoint))),
    }
  }
  return geometry
}

function geometryPoints(geometry) {
  if (!geometry) return []
  if (geometry.type === "Polygon") return geometry.coordinates.flat()
  if (geometry.type === "MultiPolygon") return geometry.coordinates.flat(2)
  return []
}

function centroid(geometry) {
  const points = geometryPoints(geometry)
  if (points.length === 0) return { longitude: null, latitude: null }

  const lng = points.reduce((sum, point) => sum + point[0], 0) / points.length
  const lat = points.reduce((sum, point) => sum + point[1], 0) / points.length
  return {
    longitude: Number(lng.toFixed(5)),
    latitude: Number(lat.toFixed(5)),
  }
}

function writeFeatureCollection(collection) {
  fs.mkdirSync(require("path").dirname(outputPath), { recursive: true })
  fs.writeFileSync(outputPath, JSON.stringify(collection))
  console.log(`${sourceKey} ${collection.metadata.feature_count}`)
}

function normalizeGermany() {
  const features = (payload.features || []).map(feature => {
    const props = feature.properties || {}
    const districtCode = String(props.ags || "").trim()
    const name = String(props.gen || "").trim()
    if (!districtCode || !name) return null

    const geometry = compactGeometry(feature.geometry)
    const center = centroid(geometry)
    const stateCode = String(props.lkz || "").trim()
    return {
      type: "Feature",
      id: `district-deu-${districtCode}`,
      geometry,
      properties: {
        id: `district-deu-${districtCode}`,
        geography_key: `district:deu:${districtCode}`,
        source_geo: districtCode,
        native_level: "kreis",
        name,
        boundary_names: Array.from(new Set([name, `${props.bez || ""} ${name}`.trim()].filter(Boolean))),
        region_name: GERMANY_STATE_NAMES[stateCode] || stateCode,
        country_code: "DE",
        country_code_alpha3: "DEU",
        country_name: "Germany",
        state_code: stateCode,
        state_iso: stateCode ? `DE-${stateCode}` : null,
        official_type: props.bez || null,
        source_key: "de_vg250_districts",
        source_name: "BKG VG250 Kreise",
        source_url: "https://sgx.geodatenzentrum.de/wfs_vg250?service=WFS&version=2.0.0&request=GetFeature&typeNames=vg250:vg250_krs&outputFormat=application/json&srsName=EPSG:4326",
        source_page_url: "https://gdz.bkg.bund.de/index.php/default/open-data/wfs-verwaltungsgebiete-1-250-000-stand-01-01-wfs-vg250.html",
        latitude: center.latitude,
        longitude: center.longitude,
      },
    }
  }).filter(Boolean)

  writeFeatureCollection({
    type: "FeatureCollection",
    metadata: {
      source_key: "de_vg250_districts",
      source_name: "BKG VG250 Kreise",
      source_url: "https://sgx.geodatenzentrum.de/wfs_vg250?service=WFS&version=2.0.0&request=GetFeature&typeNames=vg250:vg250_krs&outputFormat=application/json&srsName=EPSG:4326",
      source_page_url: "https://gdz.bkg.bund.de/index.php/default/open-data/wfs-verwaltungsgebiete-1-250-000-stand-01-01-wfs-vg250.html",
      country_codes: ["DE", "DEU"],
      generated_at: new Date().toISOString(),
      feature_count: features.length,
    },
    features,
  })
}

function normalizeAustria() {
  const features = (payload.features || []).map(feature => {
    const props = feature.properties || {}
    const districtCode = String(props.g_id || "").trim()
    const name = String(props.g_name || "").trim()
    if (!districtCode || !name) return null

    const geometry = compactGeometry(feature.geometry)
    const center = centroid(geometry)
    return {
      type: "Feature",
      id: `district-aut-${districtCode}`,
      geometry,
      properties: {
        id: `district-aut-${districtCode}`,
        geography_key: `district:aut:${districtCode}`,
        source_geo: districtCode,
        native_level: "bezirk",
        name,
        boundary_names: [name],
        region_name: AUSTRIA_STATE_NAMES[districtCode[0]] || null,
        country_code: "AT",
        country_code_alpha3: "AUT",
        country_name: "Austria",
        source_key: "at_statistik_districts",
        source_name: "Statistik Austria Political Districts",
        source_url: "https://www.statistik.at/gs-open/GEODATA/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=GEODATA:STATISTIK_AUSTRIA_POLBEZ_20250101&outputFormat=application/json&srsName=EPSG:4326",
        source_page_url: "https://data.statistik.gv.at/web/meta.jsp?dataset=OGDEXT_POLBEZ_1",
        latitude: center.latitude,
        longitude: center.longitude,
      },
    }
  }).filter(Boolean)

  writeFeatureCollection({
    type: "FeatureCollection",
    metadata: {
      source_key: "at_statistik_districts",
      source_name: "Statistik Austria Political Districts",
      source_url: "https://www.statistik.at/gs-open/GEODATA/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=GEODATA:STATISTIK_AUSTRIA_POLBEZ_20250101&outputFormat=application/json&srsName=EPSG:4326",
      source_page_url: "https://data.statistik.gv.at/web/meta.jsp?dataset=OGDEXT_POLBEZ_1",
      country_codes: ["AT", "AUT"],
      generated_at: new Date().toISOString(),
      feature_count: features.length,
    },
    features,
  })
}

function normalizeSwitzerland() {
  const districtFeatures = (payload.district_results || payload.results || []).map(feature => {
    const props = feature.properties || {}
    const name = String(props.name || "").trim()
    if (!name) return null

    const geometry = compactGeometry(feature.geometry)
    const center = centroid(geometry)
    const sourceGeo = String(feature.id || "").trim().padStart(6, "0")
    return {
      type: "Feature",
      id: `district-che-${sourceGeo}`,
      geometry,
      properties: {
        id: `district-che-${sourceGeo}`,
        geography_key: `district:che:${sourceGeo}`,
        source_geo: sourceGeo,
        feature_id: feature.id,
        native_level: "district",
        name,
        boundary_names: Array.from(new Set([name, props.label].filter(Boolean))),
        region_name: null,
        country_code: "CH",
        country_code_alpha3: "CHE",
        country_name: "Switzerland",
        source_key: "ch_geo_admin_districts",
        source_name: "swissBOUNDARIES3D District Boundaries",
        source_url: "https://api3.geo.admin.ch/rest/services/ech/MapServer/identify",
        source_page_url: "https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d",
        source_catalog_url: "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissboundaries3d",
        latitude: center.latitude,
        longitude: center.longitude,
      },
    }
  }).filter(Boolean)

  const cantonFeatures = (payload.canton_results || []).map(feature => {
    const props = feature.properties || {}
    const name = String(props.name || "").trim()
    const sourceGeo = SWITZERLAND_SINGLE_DISTRICT_EQUIVALENTS[name]
    if (!name || !sourceGeo) return null

    const geometry = compactGeometry(feature.geometry)
    const center = centroid(geometry)
    return {
      type: "Feature",
      id: `district-che-${sourceGeo}`,
      geometry,
      properties: {
        id: `district-che-${sourceGeo}`,
        geography_key: `district:che:${sourceGeo}`,
        source_geo: sourceGeo,
        feature_id: feature.id,
        native_level: "district",
        name,
        boundary_names: Array.from(new Set([
          name,
          props.label,
          `Kanton ${name}`,
          `Canton de ${name}`,
        ].filter(Boolean))),
        region_name: name,
        country_code: "CH",
        country_code_alpha3: "CHE",
        country_name: "Switzerland",
        source_key: "ch_geo_admin_districts",
        source_name: "swissBOUNDARIES3D District Boundaries",
        source_url: "https://api3.geo.admin.ch/rest/services/ech/MapServer/identify",
        source_page_url: "https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d",
        source_catalog_url: "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissboundaries3d",
        latitude: center.latitude,
        longitude: center.longitude,
        district_equivalent: true,
      },
    }
  }).filter(Boolean)

  const featureIndex = new Map()
  ;[...districtFeatures, ...cantonFeatures].forEach(feature => {
    featureIndex.set(feature.properties.source_geo || feature.id, feature)
  })
  const features = Array.from(featureIndex.values())

  writeFeatureCollection({
    type: "FeatureCollection",
    metadata: {
      source_key: "ch_geo_admin_districts",
      source_name: "swissBOUNDARIES3D District Boundaries",
      source_url: "https://api3.geo.admin.ch/rest/services/ech/MapServer/identify",
      source_page_url: "https://www.swisstopo.admin.ch/en/landscape-model-swissboundaries3d",
      source_catalog_url: "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swissboundaries3d",
      source_note: "District boundaries plus canton-equivalent polygons for single-district cantons",
      country_codes: ["CH", "CHE"],
      generated_at: new Date().toISOString(),
      feature_count: features.length,
    },
    features,
  })
}

switch (sourceKey) {
  case "de_vg250_districts":
    normalizeGermany()
    break
  case "at_statistik_districts":
    normalizeAustria()
    break
  case "ch_geo_admin_districts":
    normalizeSwitzerland()
    break
  default:
    console.error(`unknown source key: ${sourceKey}`)
    process.exit(1)
}
