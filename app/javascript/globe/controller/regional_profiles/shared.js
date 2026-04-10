export const REGIONAL_ADMIN_BOUNDARY_URLS = [
  "/api/geography/boundaries?dataset=admin1",
  "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson",
]

export const DECIMAL_FORMAT = new Intl.NumberFormat("en-US", {
  maximumFractionDigits: 1,
})

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

function renderLegendSwatch(colorCss, label) {
  return `
    <span class="local-profile-legend-chip">
      <span class="local-profile-legend-swatch" style="background:${colorCss};"></span>
      <span>${label}</span>
    </span>
  `
}

function normalizeRegionalSectorValue(value) {
  return `${value || ""}`
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
}

export function regionCameraCenter(region) {
  const center = regionBoundsCenter(region.bounds)
  return {
    lat: region.camera?.lat ?? center.lat,
    lng: region.camera?.lng ?? center.lng,
  }
}

export function regionCameraHeight(region) {
  const bounds = region.bounds || {}
  const center = regionBoundsCenter(bounds)
  const latSpanKm = Math.abs((bounds.lamax || 0) - (bounds.lamin || 0)) * 111.0
  const lngSpanKm = Math.abs((bounds.lomax || 0) - (bounds.lomin || 0)) * 111.0 * Math.abs(Math.cos(center.lat * Math.PI / 180))
  const derivedHeight = Math.round((Math.max(latSpanKm, lngSpanKm) * 1250.0) / 10000) * 10000
  return Math.max(region.camera?.height || 0, derivedHeight, 300000)
}

export function regionDefaultLayers(region = {}) {
  return [...(region.defaultLayers || region.layers || [])]
}

export function regionAvailableLayers(region = {}) {
  return [...(region.availableLayers || region.defaultLayers || region.layers || [])]
}

export function regionCountryCodes(region = {}) {
  return [...(region.countryCodes || [])]
}

export function regionSectorModes(region = {}) {
  const modes = Array.isArray(region.sectorModes) ? region.sectorModes : []
  if (modes.length > 0) return modes
  return [{ key: "all", label: "All" }]
}

export function sectorModeKey(sectorMode) {
  return typeof sectorMode === "string" ? sectorMode : sectorMode?.key
}

export function sectorModeLabel(sectorMode) {
  return typeof sectorMode === "string"
    ? titleizeProfileKey(sectorMode)
    : (sectorMode?.label || titleizeProfileKey(sectorMode?.key))
}

export function titleizeProfileKey(value) {
  return `${value || ""}`
    .split(/[_-]+/)
    .filter(Boolean)
    .map(part => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ")
}

export function renderLocalProfileList(items = [], emptyLabel) {
  if (!items.length) return `<div class="local-profile-empty-row">${emptyLabel}</div>`
  return items.map(item => `<li>${item}</li>`).join("")
}

export function sourceStatusLabel(value) {
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

export function numericMetricValue(value) {
  const number = Number(value)
  return Number.isFinite(number) ? number : null
}

export function formatCompactCurrency(value) {
  const number = numericMetricValue(value)
  return number == null ? "—" : USD_COMPACT_FORMAT.format(number)
}

export function formatCompactNumber(value) {
  const number = numericMetricValue(value)
  return number == null ? "—" : NUMBER_COMPACT_FORMAT.format(number)
}

export function formatPercent(value) {
  const number = numericMetricValue(value)
  return number == null ? "—" : `${DECIMAL_FORMAT.format(number)}%`
}

export function metricValue(record, key) {
  return numericMetricValue(record?.metrics?.[key])
}

export function regionalMetricValue(record, metricKey) {
  if (metricKey === "trade_net_pct_gdp") {
    const exportsShare = metricValue(record, "exports_goods_services_pct_gdp")
    const importsShare = metricValue(record, "imports_goods_services_pct_gdp")
    if (exportsShare == null || importsShare == null) return null
    return exportsShare - importsShare
  }

  if (metricKey === "structure_signal") return metricValue(record, "preview_score")

  return metricValue(record, metricKey)
}

export function formatRegionalMetric(metricConfig, value) {
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

export function sumMetric(records = [], key) {
  const values = records
    .map(record => metricValue(record, key))
    .filter(value => value != null)
  if (values.length === 0) return null
  return values.reduce((sum, value) => sum + value, 0)
}

export function clampNumber(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

export function mixHexColors(leftHex, rightHex, ratio) {
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

export function regionalEconomyMetricLabel(record, metricConfig, value) {
  const label = metricConfig?.shortLabel || metricConfig?.label || "Metric"
  return `${record.country_name || record.country_code_alpha3 || "Regional economy"}\n${label} ${formatRegionalMetric(metricConfig, value)}`
}

export function regionalEconomyBorderStyles(records = [], metricKey = "gdp_nominal_usd") {
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

export function normalizeRegionalBoundaryLabel(value) {
  return `${value || ""}`
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/ß/g, "ss")
    .replace(/[^a-z0-9]+/gi, "")
    .toLowerCase()
}

export function regionalAdminPreviewStyles(records = [], scoreAccessor = null) {
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

export function regionalAdminPreviewLabel(record, options = {}) {
  const score = numericMetricValue(options.score)
  const rounded = score == null ? "—" : Math.round(score)
  const sectorLabel = options.sectorLabel && options.sectorLabel !== "All" ? options.sectorLabel : null
  return `${record.name || "Admin area"}\n${sectorLabel || "Signal"} ${rounded}`
}

export function regionalAreaMetricLabel(record, metricConfig, value) {
  const label = metricConfig?.shortLabel || metricConfig?.label || "Metric"
  return `${record.name || "Region"}\n${label} ${formatRegionalMetric(metricConfig, value)}`
}

export function municipalitySectorKeys(profile = {}) {
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

export function municipalitySectorNames(profile = {}) {
  return municipalitySectorKeys(profile).map(titleizeProfileKey)
}

export function regionalEconomyMapLegend(view, sectorLabel = "All sectors", metricLabel = "GDP", metricSource = "Source not wired yet", metricKey = null) {
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
      chips: [
        renderLegendSwatch("#255f85", "Lower value"),
        renderLegendSwatch(mixHexColors("#255f85", "#f59e0b", 0.52), "Mid value"),
        renderLegendSwatch("#f59e0b", "Higher value"),
      ],
      items: [
        `Fill = ${metricLabel} rank across official district-equivalent units`,
        `Labels = top 16 districts by ${metricLabel}`,
        `Source = ${metricSource}`,
        "Click any polygon or label to open the anchored connector card",
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

export async function fetchRegionalBoundaryDataset(urls) {
  for (const url of urls) {
    try {
      const response = await fetch(url, url.startsWith("/") ? { credentials: "same-origin" } : undefined)
      if (!response.ok) continue

      const payload = await response.json()
      if (payload?.type === "FeatureCollection" && Array.isArray(payload.features)) return payload
    } catch (error) {
      console.warn(`Regional boundary fetch failed for ${url}:`, error)
    }
  }

  return null
}
