// ── Region Definitions ──────────────────────────────────────
// Predefined region profiles for focused operating pictures.
// Each region defines a bounding box (for API scoping), camera position,
// and curated layer set relevant to that region's monitoring profile.

export const REGIONS = [
  // ── Indo-Pacific ──
  {
    key: "taiwan-strait",
    name: "Taiwan Strait",
    group: "Indo-Pacific",
    bounds: { lamin: 21, lamax: 28, lomin: 116, lomax: 124 },
    camera: { lat: 24.5, lng: 120, height: 900000, heading: 0, pitch: -0.85 },
    layers: ["flights", "ships", "ports", "shippingLanes", "cables", "gpsJamming", "conflicts", "news", "chokepoints"],
    satCategories: ["military"],
    description: "PLA/ROCAF activity, AIS shipping lanes, submarine cable exposure, GPS interference",
  },
  {
    key: "south-china-sea",
    name: "South China Sea",
    group: "Indo-Pacific",
    bounds: { lamin: 3, lamax: 23, lomin: 105, lomax: 122 },
    camera: { lat: 13, lng: 114, height: 3000000, heading: 0, pitch: -0.9 },
    layers: ["flights", "ships", "ports", "shippingLanes", "cables", "gpsJamming", "conflicts", "news"],
    satCategories: ["military"],
    description: "Island militarization, shipping lanes, naval patrols, fishing fleet activity",
  },
  {
    key: "korean-peninsula",
    name: "Korean Peninsula",
    group: "Indo-Pacific",
    bounds: { lamin: 33, lamax: 43, lomin: 124, lomax: 132 },
    camera: { lat: 38, lng: 127, height: 800000, heading: 0, pitch: -0.85 },
    layers: ["flights", "ships", "gpsJamming", "conflicts", "news", "notams"],
    satCategories: ["military"],
    description: "DMZ activity, DPRK missile tests, US/ROK exercises, GPS jamming",
  },

  // ── Middle East ──
  {
    key: "strait-of-hormuz",
    name: "Strait of Hormuz",
    group: "Middle East",
    bounds: { lamin: 23, lamax: 28, lomin: 54, lomax: 60 },
    camera: { lat: 26.2, lng: 56.5, height: 500000, heading: 0, pitch: -0.8 },
    layers: ["ships", "ports", "shippingLanes", "flights", "chokepoints", "conflicts", "news", "pipelines", "gpsJamming"],
    satCategories: ["military"],
    description: "Oil tanker flows, naval presence, GPS interference, pipeline infrastructure",
  },
  {
    key: "red-sea",
    name: "Red Sea / Bab el-Mandeb",
    group: "Middle East",
    bounds: { lamin: 11, lamax: 22, lomin: 37, lomax: 46 },
    camera: { lat: 15, lng: 42, height: 1500000, heading: 0, pitch: -0.85 },
    layers: ["ships", "ports", "shippingLanes", "flights", "chokepoints", "conflicts", "news", "cables", "gpsJamming"],
    satCategories: ["military"],
    description: "Houthi attacks, shipping diversions, naval escorts, submarine cables",
  },
  {
    key: "israel-palestine",
    name: "Israel-Palestine",
    group: "Middle East",
    bounds: { lamin: 29, lamax: 34, lomin: 33, lomax: 37 },
    camera: { lat: 31.5, lng: 35, height: 400000, heading: 0, pitch: -0.8 },
    layers: ["flights", "conflicts", "news", "gpsJamming", "notams"],
    satCategories: ["military"],
    description: "Gaza conflict, IDF operations, GPS jamming, airspace restrictions",
  },
  {
    key: "gulf-states",
    name: "Gulf States",
    group: "Middle East",
    bounds: { lamin: 21, lamax: 32, lomin: 44, lomax: 57 },
    camera: { lat: 27, lng: 50, height: 1500000, heading: 0, pitch: -0.85 },
    layers: ["flights", "ships", "ports", "shippingLanes", "pipelines", "conflicts", "news", "gpsJamming", "chokepoints"],
    satCategories: ["military"],
    description: "US/Iran tensions, oil infrastructure, military buildup, naval activity",
  },

  // ── Europe ──
  {
    key: "dach",
    name: "DACH",
    group: "Europe",
    mode: "economic",
    countries: ["Germany", "Austria", "Switzerland"],
    countryCodes: ["DE", "AT", "CH"],
    bounds: { lamin: 45.6, lamax: 55.2, lomin: 5.7, lomax: 17.6 },
    camera: { lat: 48.7, lng: 10.4, height: 1400000, heading: 0, pitch: -0.88 },
    defaultLayers: ["borders", "cities", "powerPlants", "commoditySites", "outages", "financial", "news"],
    availableLayers: ["borders", "cities", "powerPlants", "commoditySites", "outages", "financial", "news", "pipelines", "airports", "notams", "weather", "cameras"],
    sectorModes: [
      { key: "all", label: "All" },
      { key: "automotive", label: "Auto" },
      { key: "semiconductors", label: "Chips" },
      { key: "chemicals", label: "Chem" },
      { key: "energy", label: "Energy" },
      { key: "finance_services", label: "Finance" },
      { key: "logistics_trade", label: "Trade" },
    ],
    metricModes: {
      country: [
        "gdp_nominal_usd",
        "population_total",
        "gdp_per_capita_usd",
        "exports_goods_services_pct_gdp",
        "imports_goods_services_pct_gdp",
        "trade_net_pct_gdp",
        "energy_imports_net_pct_energy_use",
      ],
      region: ["structure_signal"],
      municipality: ["structure_signal"],
    },
    metricSources: {
      country: {
        default: {
          label: "World Bank WDI",
          detail: "Official country snapshot",
        },
        metrics: {
          trade_net_pct_gdp: {
            label: "World Bank WDI",
            detail: "Derived as exports minus imports",
          },
        },
      },
      region: {
        default: {
          label: "Structure preview",
          detail: "Derived from city, site, and curated power catalogs",
        },
      },
      municipality: {
        default: {
          label: "Municipality preview",
          detail: "Profiled municipalities from city source packs",
        },
      },
    },
    summaryModules: ["regional_economy", "industrial_sites", "power_and_grid", "political_signal"],
    dataPacks: ["economic_baseline", "industrial_sites", "power_and_grid", "political_signal"],
    description: "Economic and infrastructure watch across Germany, Austria, and Switzerland",
  },
  {
    key: "baltic-sea",
    name: "Baltic Sea",
    group: "Europe",
    bounds: { lamin: 53, lamax: 66, lomin: 9, lomax: 30 },
    camera: { lat: 59, lng: 20, height: 1500000, heading: 0, pitch: -0.85 },
    layers: ["ships", "ports", "shippingLanes", "flights", "cables", "pipelines", "gpsJamming", "news", "notams"],
    satCategories: ["military"],
    description: "NATO/Russia naval activity, submarine cables, Nord Stream, GPS jamming",
  },
  {
    key: "black-sea",
    name: "Black Sea",
    group: "Europe",
    bounds: { lamin: 40, lamax: 47, lomin: 27, lomax: 42 },
    camera: { lat: 43.5, lng: 35, height: 1000000, heading: 0, pitch: -0.85 },
    layers: ["ships", "ports", "shippingLanes", "flights", "conflicts", "news", "gpsJamming", "cables"],
    satCategories: ["military"],
    description: "Ukrainian naval operations, Russian fleet, grain corridor, drone warfare",
  },
  {
    key: "eastern-ukraine",
    name: "Eastern Ukraine",
    group: "Europe",
    bounds: { lamin: 46, lamax: 52, lomin: 32, lomax: 41 },
    camera: { lat: 49, lng: 37, height: 600000, heading: 0, pitch: -0.8 },
    layers: ["flights", "conflicts", "news", "gpsJamming", "notams"],
    satCategories: ["military"],
    description: "Frontline activity, drone warfare, GPS jamming, military flights",
  },

  // ── Africa ──
  {
    key: "sahel",
    name: "Sahel",
    group: "Africa",
    bounds: { lamin: 10, lamax: 25, lomin: -5, lomax: 16 },
    camera: { lat: 16, lng: 5, height: 2500000, heading: 0, pitch: -0.9 },
    layers: ["conflicts", "news", "flights", "fireHotspots"],
    description: "Wagner/RSF activity, jihadist insurgency, coups, humanitarian crises",
  },
  {
    key: "horn-of-africa",
    name: "Horn of Africa",
    group: "Africa",
    bounds: { lamin: -2, lamax: 18, lomin: 32, lomax: 52 },
    camera: { lat: 8, lng: 42, height: 2000000, heading: 0, pitch: -0.85 },
    layers: ["conflicts", "ships", "ports", "shippingLanes", "news", "flights", "chokepoints"],
    description: "Sudan civil war, Somalia, Ethiopian tensions, piracy, Bab el-Mandeb access",
  },

  // ── Maritime / Strategic ──
  {
    key: "suez-canal",
    name: "Suez Canal",
    group: "Maritime",
    bounds: { lamin: 29, lamax: 32, lomin: 31, lomax: 34 },
    camera: { lat: 30.5, lng: 32.3, height: 300000, heading: 0, pitch: -0.75 },
    layers: ["ships", "ports", "shippingLanes", "chokepoints", "cables", "news"],
    description: "Global trade bottleneck, vessel queue, transit disruptions",
  },
  {
    key: "arctic",
    name: "Arctic / Northern Sea Route",
    group: "Maritime",
    bounds: { lamin: 65, lamax: 85, lomin: 20, lomax: 180 },
    camera: { lat: 75, lng: 100, height: 4000000, heading: 0, pitch: -0.9 },
    layers: ["ships", "ports", "shippingLanes", "flights", "cables", "weather", "news"],
    satCategories: ["military"],
    description: "Northern Sea Route shipping, icebreaker activity, military posturing, cable routes",
  },

  // ── Americas ──
  {
    key: "caribbean",
    name: "Caribbean",
    group: "Americas",
    bounds: { lamin: 10, lamax: 27, lomin: -87, lomax: -59 },
    camera: { lat: 19, lng: -73, height: 2500000, heading: 0, pitch: -0.85 },
    layers: ["ships", "ports", "shippingLanes", "flights", "weather", "news", "cables"],
    description: "Drug interdiction, hurricane corridor, Venezuelan crisis, Cuban activity",
  },
]

export const REGION_MAP = Object.fromEntries(REGIONS.map(r => [r.key, r]))

// Group regions for dropdown rendering
export const REGION_GROUPS = [...new Set(REGIONS.map(r => r.group))]
