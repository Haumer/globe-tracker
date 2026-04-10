export const REGIONAL_METRIC_CATALOG = [
  {
    key: "gdp_nominal_usd",
    label: "GDP",
    shortLabel: "GDP",
    family: "economy",
    granularities: ["country"],
    valueType: "currency",
    sourceMode: "official",
  },
  {
    key: "population_total",
    label: "Population",
    shortLabel: "Pop",
    family: "demography",
    granularities: ["country"],
    valueType: "count",
    sourceMode: "official",
  },
  {
    key: "gdp_per_capita_usd",
    label: "GDP / Capita",
    shortLabel: "GDP/cap",
    family: "economy",
    granularities: ["country"],
    valueType: "currency",
    sourceMode: "official",
  },
  {
    key: "exports_goods_services_pct_gdp",
    label: "Exports / GDP",
    shortLabel: "Exports",
    family: "trade",
    granularities: ["country"],
    valueType: "percent",
    sourceMode: "official",
  },
  {
    key: "imports_goods_services_pct_gdp",
    label: "Imports / GDP",
    shortLabel: "Imports",
    family: "trade",
    granularities: ["country"],
    valueType: "percent",
    sourceMode: "official",
  },
  {
    key: "trade_net_pct_gdp",
    label: "Net Exports / GDP",
    shortLabel: "X-M",
    family: "trade",
    granularities: ["country"],
    valueType: "percent",
    sourceMode: "derived",
  },
  {
    key: "energy_imports_net_pct_energy_use",
    label: "Energy Dependence",
    shortLabel: "Energy dep",
    family: "energy",
    granularities: ["country"],
    valueType: "percent",
    sourceMode: "official",
  },
  {
    key: "structure_signal",
    label: "Structure",
    shortLabel: "Structure",
    family: "structure",
    granularities: ["region", "municipality"],
    valueType: "index",
    sourceMode: "derived",
  },
].freeze

export function regionalMetricConfig(metricKey) {
  return REGIONAL_METRIC_CATALOG.find(metric => metric.key === metricKey) || REGIONAL_METRIC_CATALOG[0]
}

export function regionalMetricOptions(region = {}, granularityKey) {
  const explicitKeys = region?.metricModes?.[granularityKey]
  if (Array.isArray(explicitKeys) && explicitKeys.length > 0) {
    return explicitKeys
      .map(metricKey => regionalMetricConfig(metricKey))
      .filter(Boolean)
  }

  return REGIONAL_METRIC_CATALOG.filter(metric => Array.isArray(metric.granularities) && metric.granularities.includes(granularityKey))
}

export function defaultRegionalMetricKey(region = {}, granularityKey) {
  return regionalMetricOptions(region, granularityKey)[0]?.key || null
}

export function regionalMetricSource(region = {}, granularityKey, metricKey) {
  const granularitySources = region?.metricSources?.[granularityKey]
  if (!granularitySources) return null

  return granularitySources?.metrics?.[metricKey] || granularitySources?.default || null
}

export function regionalMetricSourceSummary(region = {}, granularityKey, metricKey) {
  const source = regionalMetricSource(region, granularityKey, metricKey)
  if (!source) return "Source not wired yet"

  return [source.label, source.detail].filter(Boolean).join(" · ")
}
