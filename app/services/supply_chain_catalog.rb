class SupplyChainCatalog
  WORLD_BANK_SOURCE = {
    provider: "world_bank",
    display_name: "World Bank WDI",
    feed_kind: "country_economics",
    endpoint_url: "https://api.worldbank.org/v2",
  }.freeze

  WORLD_BANK_SERIES = {
    "NY.GDP.MKTP.CD" => {
      target: :indicator,
      indicator_key: "gdp_nominal_usd",
      indicator_name: "GDP (current US$)",
      unit: "USD",
    },
    "NY.GDP.PCAP.CD" => {
      target: :indicator,
      indicator_key: "gdp_per_capita_usd",
      indicator_name: "GDP per capita (current US$)",
      unit: "USD",
    },
    "SP.POP.TOTL" => {
      target: :indicator,
      indicator_key: "population_total",
      indicator_name: "Population, total",
      unit: "persons",
    },
    "NE.IMP.GNFS.ZS" => {
      target: :indicator,
      indicator_key: "imports_goods_services_pct_gdp",
      indicator_name: "Imports of goods and services (% of GDP)",
      unit: "%",
    },
    "NE.EXP.GNFS.ZS" => {
      target: :indicator,
      indicator_key: "exports_goods_services_pct_gdp",
      indicator_name: "Exports of goods and services (% of GDP)",
      unit: "%",
    },
    "EG.IMP.CONS.ZS" => {
      target: :indicator,
      indicator_key: "energy_imports_net_pct_energy_use",
      indicator_name: "Energy imports, net (% of energy use)",
      unit: "%",
    },
    "NV.AGR.TOTL.ZS" => {
      target: :sector,
      sector_key: "agriculture",
      sector_name: "Agriculture",
      metric_key: "gdp_share_pct",
      metric_name: "Share of GDP",
      unit: "%",
    },
    "NV.IND.TOTL.ZS" => {
      target: :sector,
      sector_key: "industry",
      sector_name: "Industry",
      metric_key: "gdp_share_pct",
      metric_name: "Share of GDP",
      unit: "%",
    },
    "NV.IND.MANF.ZS" => {
      target: :sector,
      sector_key: "manufacturing",
      sector_name: "Manufacturing",
      metric_key: "gdp_share_pct",
      metric_name: "Share of GDP",
      unit: "%",
    },
    "NV.SRV.TOTL.ZS" => {
      target: :sector,
      sector_key: "services",
      sector_name: "Services",
      metric_key: "gdp_share_pct",
      metric_name: "Share of GDP",
      unit: "%",
    },
  }.freeze

  STRATEGIC_COMMODITIES = {
    "oil_crude" => {
      name: "Crude Oil",
      hs_prefixes: %w[2709],
    },
    "oil_refined" => {
      name: "Refined Petroleum",
      hs_prefixes: %w[2710],
    },
    "lng" => {
      name: "Liquefied Natural Gas",
      hs_prefixes: %w[271111 271121],
    },
    "gas_nat" => {
      name: "Natural Gas",
      hs_prefixes: %w[2711],
    },
    "helium" => {
      name: "Helium",
      hs_prefixes: %w[280429],
    },
    "copper" => {
      name: "Copper",
      hs_prefixes: %w[2603 7402 7403 7404 7408],
    },
    "iron_ore" => {
      name: "Iron Ore",
      hs_prefixes: %w[2601],
    },
    "wheat" => {
      name: "Wheat",
      hs_prefixes: %w[1001],
    },
    "fertilizer" => {
      name: "Fertilizer",
      hs_prefixes: %w[3102 3103 3104 3105],
    },
    "semiconductors" => {
      name: "Semiconductors",
      hs_prefixes: %w[8541 8542],
    },
    "semiconductor_equipment" => {
      name: "Semiconductor Manufacturing Equipment",
      hs_prefixes: %w[8486],
    },
  }.freeze

  COMMODITY_FLOW_TYPES = {
    "oil_crude" => :oil,
    "oil_refined" => :oil,
    "lng" => :lng,
    "gas_nat" => :lng,
    "wheat" => :grain,
    "semiconductors" => :semiconductors,
    "semiconductor_equipment" => :semiconductors,
    "copper" => :trade,
    "iron_ore" => :trade,
    "fertilizer" => :trade,
    "helium" => :trade,
  }.freeze

  CHOKEPOINT_ROUTE_PRIORS = [
    {
      chokepoint_key: "malacca",
      commodity_keys: %w[oil_crude oil_refined lng gas_nat],
      destination_country_alpha3: %w[CHN JPN KOR PHL TWN AUS NZL],
      requires_any_source_chokepoint: %w[hormuz mozambique],
      multiplier: 0.65,
      shipping_priority: 80,
      note: "Middle East and Indian Ocean energy cargoes into East Asia commonly transit the Strait of Malacca.",
      route_waypoints: [
        { type: "chokepoint", key: "hormuz" },
        {
          type: "hub",
          kind: "port",
          role: "modeled_stopover",
          locode: "LKCMB",
          name: "Colombo",
          country_code: "LK",
          country_code_alpha3: "LKA",
          lat: 6.9553,
          lng: 79.8647,
        },
        { type: "chokepoint", key: "malacca" },
        {
          type: "hub",
          kind: "port",
          role: "modeled_stopover",
          locode: "SGSIN",
          name: "Singapore",
          country_code: "SG",
          country_code_alpha3: "SGP",
          lat: 1.2644,
          lng: 103.8405,
        },
      ],
    },
    {
      chokepoint_key: "suez",
      commodity_keys: %w[oil_crude oil_refined lng wheat fertilizer],
      destination_country_alpha3: %w[DEU ESP FRA GBR GRC ITA NLD POL],
      requires_any_source_chokepoint: %w[bab_el_mandeb],
      multiplier: 0.55,
      shipping_priority: 75,
      note: "Red Sea flows bound for Europe frequently depend on both Bab el-Mandeb and the Suez Canal.",
      route_waypoints: [
        { type: "chokepoint", key: "bab_el_mandeb" },
        { type: "chokepoint", key: "suez" },
        {
          type: "hub",
          kind: "port",
          role: "modeled_stopover",
          locode: "EGPSD",
          name: "Port Said",
          country_code: "EG",
          country_code_alpha3: "EGY",
          lat: 31.2565,
          lng: 32.2841,
        },
      ],
    },
    {
      chokepoint_key: "panama",
      commodity_keys: %w[oil_crude oil_refined lng gas_nat],
      destination_country_alpha3: %w[USA MEX PER CHL AUS NZL CHN JPN KOR PHL TWN],
      requires_any_source_chokepoint: [],
      multiplier: 0.52,
      shipping_priority: 85,
      note: "Atlantic-basin cargoes bound for Pacific America, East Asia, and Oceania often route through the Panama Canal.",
      route_waypoints: [
        { type: "chokepoint", key: "panama" },
        {
          type: "hub",
          kind: "port",
          role: "modeled_stopover",
          locode: "PABLB",
          name: "Balboa",
          country_code: "PA",
          country_code_alpha3: "PAN",
          lat: 8.949,
          lng: -79.566,
        },
      ],
    },
    {
      chokepoint_key: "hormuz",
      commodity_keys: %w[oil_crude oil_refined lng gas_nat],
      destination_country_alpha3: %w[USA CAN BRA],
      requires_any_source_chokepoint: [],
      multiplier: 0.5,
      shipping_priority: 72,
      note: "Middle East cargoes bound for Atlantic markets often run through Bab el-Mandeb, Suez, and Gibraltar.",
      route_waypoints: [
        { type: "chokepoint", key: "hormuz" },
        { type: "chokepoint", key: "bab_el_mandeb" },
        { type: "chokepoint", key: "suez" },
        {
          type: "hub",
          kind: "port",
          role: "modeled_stopover",
          locode: "EGPSD",
          name: "Port Said",
          country_code: "EG",
          country_code_alpha3: "EGY",
          lat: 31.2565,
          lng: 32.2841,
        },
        { type: "chokepoint", key: "gibraltar" },
      ],
    },
    {
      chokepoint_key: "cape",
      commodity_keys: %w[oil_crude oil_refined lng gas_nat],
      destination_country_alpha3: %w[BRA],
      requires_any_source_chokepoint: %w[hormuz],
      multiplier: 0.48,
      shipping_priority: 73,
      note: "South Atlantic energy cargoes can swing below Africa via the Mozambique Channel and Cape of Good Hope.",
      route_waypoints: [
        { type: "chokepoint", key: "hormuz" },
        { type: "chokepoint", key: "mozambique" },
        { type: "chokepoint", key: "cape" },
      ],
    },
    {
      chokepoint_key: "taiwan_strait",
      commodity_keys: %w[semiconductors semiconductor_equipment],
      destination_country_alpha3: %w[USA CAN MEX AUS NZL],
      requires_any_source_chokepoint: [],
      multiplier: 0.58,
      shipping_priority: 78,
      note: "Pacific-bound semiconductor cargoes from Taiwan commonly rely on the Taiwan Strait.",
      route_waypoints: [
        { type: "chokepoint", key: "taiwan_strait" },
      ],
    },
  ].freeze

  EXPORT_HUB_PRIORS = {
    ["hormuz", "lng"] => {
      kind: "port",
      locode: "QARLF",
      name: "Ras Laffan",
      country_code: "QA",
      country_code_alpha3: "QAT",
      lat: 25.9246,
      lng: 51.5361,
    },
    ["hormuz", "gas_nat"] => {
      kind: "port",
      locode: "QARLF",
      name: "Ras Laffan",
      country_code: "QA",
      country_code_alpha3: "QAT",
      lat: 25.9246,
      lng: 51.5361,
    },
    ["hormuz", "oil_crude"] => {
      kind: "port",
      locode: "SARAS",
      name: "Ras Tanura",
      country_code: "SA",
      country_code_alpha3: "SAU",
      lat: 26.646,
      lng: 50.164,
    },
    ["hormuz", "oil_refined"] => {
      kind: "port",
      locode: "AEFJR",
      name: "Fujairah",
      country_code: "AE",
      country_code_alpha3: "ARE",
      lat: 25.1312,
      lng: 56.3347,
    },
    ["panama", "lng"] => {
      kind: "port",
      locode: "USHOU",
      name: "Houston",
      country_code: "US",
      country_code_alpha3: "USA",
      lat: 29.7604,
      lng: -95.3698,
    },
    ["panama", "gas_nat"] => {
      kind: "port",
      locode: "USHOU",
      name: "Houston",
      country_code: "US",
      country_code_alpha3: "USA",
      lat: 29.7604,
      lng: -95.3698,
    },
    ["panama", "oil_crude"] => {
      kind: "port",
      locode: "USHOU",
      name: "Houston",
      country_code: "US",
      country_code_alpha3: "USA",
      lat: 29.7604,
      lng: -95.3698,
    },
    ["panama", "oil_refined"] => {
      kind: "port",
      locode: "USHOU",
      name: "Houston",
      country_code: "US",
      country_code_alpha3: "USA",
      lat: 29.7604,
      lng: -95.3698,
    },
    ["taiwan_strait", "semiconductors"] => {
      kind: "port",
      locode: "TWKHH",
      name: "Kaohsiung",
      country_code: "TW",
      country_code_alpha3: "TWN",
      lat: 22.6163,
      lng: 120.3004,
    },
  }.freeze

  SHIPPING_ROUTE_EXTENSIONS = {
    "ESP" => [
      { type: "chokepoint", key: "gibraltar" },
    ],
    "FRA" => [
      { type: "chokepoint", key: "gibraltar" },
      {
        type: "hub",
        kind: "port",
        role: "modeled_stopover",
        locode: "GBDVR",
        name: "Dover",
        country_code: "GB",
        country_code_alpha3: "GBR",
        lat: 51.129,
        lng: 1.308,
      },
    ],
    "GBR" => [
      { type: "chokepoint", key: "gibraltar" },
      {
        type: "hub",
        kind: "port",
        role: "modeled_stopover",
        locode: "GBDVR",
        name: "Dover",
        country_code: "GB",
        country_code_alpha3: "GBR",
        lat: 51.129,
        lng: 1.308,
      },
    ],
    "NLD" => [
      { type: "chokepoint", key: "gibraltar" },
      {
        type: "hub",
        kind: "port",
        role: "modeled_stopover",
        locode: "GBDVR",
        name: "Dover",
        country_code: "GB",
        country_code_alpha3: "GBR",
        lat: 51.129,
        lng: 1.308,
      },
    ],
    "DEU" => [
      { type: "chokepoint", key: "gibraltar" },
      {
        type: "hub",
        kind: "port",
        role: "modeled_stopover",
        locode: "GBDVR",
        name: "Dover",
        country_code: "GB",
        country_code_alpha3: "GBR",
        lat: 51.129,
        lng: 1.308,
      },
      {
        type: "hub",
        kind: "port",
        role: "modeled_stopover",
        locode: "DECUX",
        name: "Cuxhaven",
        country_code: "DE",
        country_code_alpha3: "DEU",
        lat: 53.8616,
        lng: 8.6942,
      },
    ],
    "POL" => [
      { type: "chokepoint", key: "gibraltar" },
      {
        type: "hub",
        kind: "port",
        role: "modeled_stopover",
        locode: "GBDVR",
        name: "Dover",
        country_code: "GB",
        country_code_alpha3: "GBR",
        lat: 51.129,
        lng: 1.308,
      },
      { type: "chokepoint", key: "danish_straits" },
    ],
    "ITA" => [
      {
        type: "hub",
        kind: "port",
        role: "modeled_stopover",
        locode: "MTMLA",
        name: "Valletta",
        country_code: "MT",
        country_code_alpha3: "MLT",
        lat: 35.8989,
        lng: 14.5146,
      },
    ],
  }.freeze

  COUNTRY_PORT_PRIORS = {
    "CN" => {
      import: {
        "default" => { kind: "port", locode: "CNSHA", name: "Shanghai", country_code: "CN", country_code_alpha3: "CHN", lat: 31.2304, lng: 121.4737 },
      },
    },
    "DE" => {
      import: {
        "default" => { kind: "port", locode: "DEHAM", name: "Hamburg", country_code: "DE", country_code_alpha3: "DEU", lat: 53.5511, lng: 9.9937 },
      },
    },
    "ES" => {
      import: {
        "default" => { kind: "port", locode: "ESALG", name: "Algeciras", country_code: "ES", country_code_alpha3: "ESP", lat: 36.1408, lng: -5.4562 },
      },
    },
    "FR" => {
      import: {
        "default" => { kind: "port", locode: "FRLEH", name: "Le Havre", country_code: "FR", country_code_alpha3: "FRA", lat: 49.4944, lng: 0.1079 },
      },
    },
    "GB" => {
      import: {
        "default" => { kind: "port", locode: "GBFXT", name: "Felixstowe", country_code: "GB", country_code_alpha3: "GBR", lat: 51.963, lng: 1.351 },
      },
    },
    "GR" => {
      import: {
        "default" => { kind: "port", locode: "GRPIR", name: "Piraeus", country_code: "GR", country_code_alpha3: "GRC", lat: 37.942, lng: 23.6465 },
      },
    },
    "IT" => {
      import: {
        "default" => { kind: "port", locode: "ITGOA", name: "Genoa", country_code: "IT", country_code_alpha3: "ITA", lat: 44.4056, lng: 8.9463 },
      },
    },
    "JP" => {
      import: {
        "lng" => { kind: "port", locode: "JPYOK", name: "Yokohama", country_code: "JP", country_code_alpha3: "JPN", lat: 35.4437, lng: 139.638 },
        "gas_nat" => { kind: "port", locode: "JPYOK", name: "Yokohama", country_code: "JP", country_code_alpha3: "JPN", lat: 35.4437, lng: 139.638 },
        "oil_crude" => { kind: "port", locode: "JPYOK", name: "Yokohama", country_code: "JP", country_code_alpha3: "JPN", lat: 35.4437, lng: 139.638 },
        "oil_refined" => { kind: "port", locode: "JPYOK", name: "Yokohama", country_code: "JP", country_code_alpha3: "JPN", lat: 35.4437, lng: 139.638 },
        "default" => { kind: "port", locode: "JPYOK", name: "Yokohama", country_code: "JP", country_code_alpha3: "JPN", lat: 35.4437, lng: 139.638 },
      },
    },
    "KR" => {
      import: {
        "lng" => { kind: "port", locode: "KRUSN", name: "Ulsan", country_code: "KR", country_code_alpha3: "KOR", lat: 35.5384, lng: 129.3114 },
        "gas_nat" => { kind: "port", locode: "KRUSN", name: "Ulsan", country_code: "KR", country_code_alpha3: "KOR", lat: 35.5384, lng: 129.3114 },
        "oil_crude" => { kind: "port", locode: "KRUSN", name: "Ulsan", country_code: "KR", country_code_alpha3: "KOR", lat: 35.5384, lng: 129.3114 },
        "oil_refined" => { kind: "port", locode: "KRUSN", name: "Ulsan", country_code: "KR", country_code_alpha3: "KOR", lat: 35.5384, lng: 129.3114 },
        "default" => { kind: "port", locode: "KRPUS", name: "Busan", country_code: "KR", country_code_alpha3: "KOR", lat: 35.1047, lng: 129.0403 },
      },
    },
    "NL" => {
      import: {
        "default" => { kind: "port", locode: "NLRTM", name: "Rotterdam", country_code: "NL", country_code_alpha3: "NLD", lat: 51.9244, lng: 4.4777 },
      },
    },
    "PH" => {
      import: {
        "default" => { kind: "port", locode: "PHMNL", name: "Manila", country_code: "PH", country_code_alpha3: "PHL", lat: 14.5995, lng: 120.9842 },
      },
    },
    "PL" => {
      import: {
        "default" => { kind: "port", locode: "PLGDN", name: "Gdansk", country_code: "PL", country_code_alpha3: "POL", lat: 54.352, lng: 18.6466 },
      },
    },
    "TW" => {
      import: {
        "default" => { kind: "port", locode: "TWKHH", name: "Kaohsiung", country_code: "TW", country_code_alpha3: "TWN", lat: 22.6163, lng: 120.3004 },
      },
    },
  }.freeze

  COUNTRY_PORT_CANDIDATES = {
    "US" => {
      import: {
        "default" => [
          { kind: "port", locode: "USNYC", name: "New York", country_code: "US", country_code_alpha3: "USA", lat: 40.7128, lng: -74.0060, importance: 0.88, flow_types: %w[trade container atlantic] },
          { kind: "port", locode: "USHOU", name: "Houston", country_code: "US", country_code_alpha3: "USA", lat: 29.7604, lng: -95.3698, importance: 0.92, flow_types: %w[oil lng gulf] },
          { kind: "port", locode: "USLGB", name: "Long Beach", country_code: "US", country_code_alpha3: "USA", lat: 33.7701, lng: -118.1937, importance: 0.94, flow_types: %w[trade container pacific] },
        ],
        "oil_crude" => [
          { kind: "port", locode: "USHOU", name: "Houston", country_code: "US", country_code_alpha3: "USA", lat: 29.7604, lng: -95.3698, importance: 0.95, flow_types: %w[oil gulf] },
          { kind: "port", locode: "USLGB", name: "Long Beach", country_code: "US", country_code_alpha3: "USA", lat: 33.7701, lng: -118.1937, importance: 0.72, flow_types: %w[oil pacific] },
          { kind: "port", locode: "USNYC", name: "New York", country_code: "US", country_code_alpha3: "USA", lat: 40.7128, lng: -74.0060, importance: 0.68, flow_types: %w[oil atlantic] },
        ],
        "oil_refined" => [
          { kind: "port", locode: "USHOU", name: "Houston", country_code: "US", country_code_alpha3: "USA", lat: 29.7604, lng: -95.3698, importance: 0.92, flow_types: %w[oil gulf] },
          { kind: "port", locode: "USLGB", name: "Long Beach", country_code: "US", country_code_alpha3: "USA", lat: 33.7701, lng: -118.1937, importance: 0.78, flow_types: %w[oil pacific] },
        ],
        "lng" => [
          { kind: "port", locode: "USHOU", name: "Houston", country_code: "US", country_code_alpha3: "USA", lat: 29.7604, lng: -95.3698, importance: 0.95, flow_types: %w[lng gulf] },
          { kind: "port", locode: "USLGB", name: "Long Beach", country_code: "US", country_code_alpha3: "USA", lat: 33.7701, lng: -118.1937, importance: 0.66, flow_types: %w[lng pacific] },
        ],
        "gas_nat" => [
          { kind: "port", locode: "USHOU", name: "Houston", country_code: "US", country_code_alpha3: "USA", lat: 29.7604, lng: -95.3698, importance: 0.95, flow_types: %w[lng gulf] },
          { kind: "port", locode: "USLGB", name: "Long Beach", country_code: "US", country_code_alpha3: "USA", lat: 33.7701, lng: -118.1937, importance: 0.66, flow_types: %w[lng pacific] },
        ],
      },
      export: {
        "default" => [
          { kind: "port", locode: "USHOU", name: "Houston", country_code: "US", country_code_alpha3: "USA", lat: 29.7604, lng: -95.3698, importance: 0.92, flow_types: %w[oil lng gulf] },
          { kind: "port", locode: "USNYC", name: "New York", country_code: "US", country_code_alpha3: "USA", lat: 40.7128, lng: -74.0060, importance: 0.86, flow_types: %w[trade atlantic] },
        ],
      },
    },
    "CA" => {
      import: {
        "default" => [
          { kind: "port", locode: "CAHAL", name: "Halifax", country_code: "CA", country_code_alpha3: "CAN", lat: 44.6488, lng: -63.5752, importance: 0.72, flow_types: %w[trade atlantic] },
          { kind: "port", locode: "CAVAN", name: "Vancouver", country_code: "CA", country_code_alpha3: "CAN", lat: 49.2827, lng: -123.1207, importance: 0.84, flow_types: %w[trade pacific] },
        ],
        "oil_crude" => [
          { kind: "port", locode: "CAHAL", name: "Halifax", country_code: "CA", country_code_alpha3: "CAN", lat: 44.6488, lng: -63.5752, importance: 0.74, flow_types: %w[oil atlantic] },
        ],
        "lng" => [
          { kind: "port", locode: "CAVAN", name: "Vancouver", country_code: "CA", country_code_alpha3: "CAN", lat: 49.2827, lng: -123.1207, importance: 0.78, flow_types: %w[lng pacific] },
        ],
      },
    },
    "MX" => {
      import: {
        "default" => [
          { kind: "port", locode: "MXZLO", name: "Manzanillo", country_code: "MX", country_code_alpha3: "MEX", lat: 19.0500, lng: -104.3167, importance: 0.76, flow_types: %w[trade pacific] },
          { kind: "port", locode: "MXVER", name: "Veracruz", country_code: "MX", country_code_alpha3: "MEX", lat: 19.1738, lng: -96.1342, importance: 0.72, flow_types: %w[trade atlantic] },
        ],
      },
    },
    "BR" => {
      import: {
        "default" => [
          { kind: "port", locode: "BRSNZ", name: "Santos", country_code: "BR", country_code_alpha3: "BRA", lat: -23.9608, lng: -46.3336, importance: 0.86, flow_types: %w[trade atlantic] },
        ],
      },
    },
    "PE" => {
      import: {
        "default" => [
          { kind: "port", locode: "PECLL", name: "Callao", country_code: "PE", country_code_alpha3: "PER", lat: -12.0597, lng: -77.1422, importance: 0.76, flow_types: %w[trade pacific] },
        ],
      },
    },
    "CL" => {
      import: {
        "default" => [
          { kind: "port", locode: "CLVAP", name: "Valparaiso", country_code: "CL", country_code_alpha3: "CHL", lat: -33.0472, lng: -71.6127, importance: 0.76, flow_types: %w[trade pacific] },
        ],
      },
    },
    "AU" => {
      import: {
        "default" => [
          { kind: "port", locode: "AUSYD", name: "Sydney", country_code: "AU", country_code_alpha3: "AUS", lat: -33.8688, lng: 151.2093, importance: 0.88, flow_types: %w[trade pacific] },
          { kind: "port", locode: "AUDRW", name: "Darwin", country_code: "AU", country_code_alpha3: "AUS", lat: -12.4634, lng: 130.8456, importance: 0.78, flow_types: %w[lng indian_ocean] },
        ],
        "lng" => [
          { kind: "port", locode: "AUDRW", name: "Darwin", country_code: "AU", country_code_alpha3: "AUS", lat: -12.4634, lng: 130.8456, importance: 0.84, flow_types: %w[lng indian_ocean] },
          { kind: "port", locode: "AUSYD", name: "Sydney", country_code: "AU", country_code_alpha3: "AUS", lat: -33.8688, lng: 151.2093, importance: 0.82, flow_types: %w[lng pacific] },
        ],
      },
    },
    "NZ" => {
      import: {
        "default" => [
          { kind: "port", locode: "NZAKL", name: "Auckland", country_code: "NZ", country_code_alpha3: "NZL", lat: -36.8509, lng: 174.7645, importance: 0.82, flow_types: %w[trade pacific] },
        ],
      },
    },
  }.freeze

  BASELINE_SECTOR_INPUT_PRIORS = {
    "manufacturing" => [
      {
        input_kind: "commodity",
        input_key: "oil_refined",
        input_name: "Refined Petroleum",
        coefficient: 0.32,
        note: "Fuel and petrochemical inputs support broad manufacturing output.",
      },
      {
        input_kind: "commodity",
        input_key: "lng",
        input_name: "Liquefied Natural Gas",
        coefficient: 0.26,
        note: "Industrial heat and power demand often rides on gas and LNG availability.",
      },
      {
        input_kind: "commodity",
        input_key: "helium",
        input_name: "Helium",
        coefficient: 0.18,
        note: "Precision, medical, and semiconductor-adjacent manufacturing depends on helium.",
      },
      {
        input_kind: "commodity",
        input_key: "semiconductor_equipment",
        input_name: "Semiconductor Manufacturing Equipment",
        coefficient: 0.14,
        note: "Advanced manufacturing output is sensitive to semiconductor tooling and maintenance cycles.",
      },
    ],
    "industry" => [
      {
        input_kind: "commodity",
        input_key: "oil_crude",
        input_name: "Crude Oil",
        coefficient: 0.28,
        note: "Heavy industry remains exposed to oil and petrochemical feedstocks.",
      },
      {
        input_kind: "commodity",
        input_key: "lng",
        input_name: "Liquefied Natural Gas",
        coefficient: 0.24,
        note: "Industrial power and heat are commonly gas-linked.",
      },
      {
        input_kind: "commodity",
        input_key: "copper",
        input_name: "Copper",
        coefficient: 0.18,
        note: "Electrical and industrial buildouts are copper-intensive.",
      },
      {
        input_kind: "commodity",
        input_key: "iron_ore",
        input_name: "Iron Ore",
        coefficient: 0.16,
        note: "Steelmaking and heavy industrial output remain tied to iron ore supply.",
      },
    ],
    "agriculture" => [
      {
        input_kind: "commodity",
        input_key: "fertilizer",
        input_name: "Fertilizer",
        coefficient: 0.34,
        note: "Crop yields and planted acreage are highly sensitive to fertilizer availability.",
      },
      {
        input_kind: "commodity",
        input_key: "oil_refined",
        input_name: "Refined Petroleum",
        coefficient: 0.16,
        note: "Farm equipment and rural logistics depend on diesel and refined fuels.",
      },
    ],
  }.freeze

  class << self
    def commodity_key_for_hs(hs_code)
      normalized = hs_code.to_s.gsub(/\D/, "")
      return if normalized.blank?

      STRATEGIC_COMMODITIES.find do |_commodity_key, config|
        Array(config[:hs_prefixes]).any? { |prefix| normalized.start_with?(prefix.to_s) }
      end&.first
    end

    def commodity_name_for(key)
      STRATEGIC_COMMODITIES.dig(key.to_s, :name)
    end

    def commodity_flow_type_for(key)
      COMMODITY_FLOW_TYPES[key.to_s]
    end

    def energy_commodity?(key)
      %w[oil_crude oil_refined lng gas_nat].include?(key.to_s)
    end

    def route_priors_for(country_code_alpha3:, commodity_key:)
      alpha3 = country_code_alpha3.to_s.upcase
      key = commodity_key.to_s

      CHOKEPOINT_ROUTE_PRIORS.select do |prior|
        Array(prior[:commodity_keys]).include?(key) &&
          Array(prior[:destination_country_alpha3]).include?(alpha3)
      end
    end

    def strategic_commodity_pairs
      STRATEGIC_COMMODITIES.map { |commodity_key, config| [commodity_key, config.fetch(:name)] }
        .sort_by { |commodity_key, commodity_name| [commodity_name, commodity_key] }
    end

    def shipping_route_prior_for(country_code_alpha3:, commodity_key:, exposures: [])
      priors = route_priors_for(country_code_alpha3: country_code_alpha3, commodity_key: commodity_key)
      rows_by_key = Array(exposures).index_by { |row| row.respond_to?(:chokepoint_key) ? row.chokepoint_key.to_s : row[:chokepoint_key].to_s }

      priors.max_by do |prior|
        chokepoint_support = rows_by_key[prior.fetch(:chokepoint_key).to_s]
        required_support = Array(prior[:requires_any_source_chokepoint]).sum do |key|
          exposure = rows_by_key[key.to_s]
          exposure.respond_to?(:exposure_score) ? exposure.exposure_score.to_f : exposure&.dig(:exposure_score).to_f
        end
        chokepoint_score = chokepoint_support.respond_to?(:exposure_score) ? chokepoint_support.exposure_score.to_f : chokepoint_support&.dig(:exposure_score).to_f

        [
          chokepoint_score + required_support,
          prior.fetch(:shipping_priority, 0).to_f,
          Array(prior[:requires_any_source_chokepoint]).size
        ]
      end&.deep_dup
    end

    def shipping_route_extensions_for(destination_anchor:, country_code_alpha3:)
      return [] if destination_anchor.blank? && country_code_alpha3.blank?

      extension_key = destination_anchor&.dig(:country_code_alpha3).presence || country_code_alpha3.to_s.upcase
      Array(SHIPPING_ROUTE_EXTENSIONS[extension_key]).map(&:dup)
    end

    def export_hub_for(chokepoint_key:, commodity_key:)
      key = [chokepoint_key.to_s, commodity_key.to_s]
      EXPORT_HUB_PRIORS[key]&.dup
    end

    def country_port_candidates_for(country_code:, country_code_alpha3:, commodity_key:, role:)
      code = country_code.to_s.upcase
      role_key = role.to_sym
      commodity = commodity_key.to_s

      candidates = Array(
        COUNTRY_PORT_CANDIDATES.dig(code, role_key, commodity) ||
        COUNTRY_PORT_CANDIDATES.dig(code, role_key, "default")
      ).map(&:dup)

      if candidates.blank?
        single = country_port_anchor_for(
          country_code: country_code,
          country_code_alpha3: country_code_alpha3,
          commodity_key: commodity_key,
          role: role
        )
        candidates = [single].compact
      end

      candidates
    end

    def all_country_port_candidates
      COUNTRY_PORT_CANDIDATES.flat_map do |country_code, role_map|
        role_map.flat_map do |role, commodity_map|
          commodity_map.flat_map do |commodity_key, candidates|
            Array(candidates).map do |candidate|
              candidate.deep_dup.merge(
                role: role.to_s,
                candidate_commodity_key: commodity_key.to_s == "default" ? nil : commodity_key.to_s,
                country_code: candidate[:country_code] || country_code.to_s.upcase
              )
            end
          end
        end
      end
    end

    def commodity_keys_for_flow_types(flow_types)
      Array(flow_types).flat_map do |flow_type|
        case flow_type.to_s
        when "oil" then %w[oil_crude oil_refined]
        when "lng" then %w[lng gas_nat]
        when "grain" then %w[wheat]
        when "semiconductors" then %w[semiconductors semiconductor_equipment]
        else []
        end
      end.uniq
    end

    def country_port_anchor_for(country_code:, country_code_alpha3:, commodity_key:, role:)
      config = COUNTRY_PORT_PRIORS[country_code.to_s.upcase]
      return if config.blank?

      role_config = config[role.to_sym]
      return if role_config.blank?

      role_config[commodity_key.to_s]&.dup || role_config["default"]&.dup
    end

    def baseline_sector_inputs_for(sector_key)
      Array(BASELINE_SECTOR_INPUT_PRIORS[sector_key.to_s]).map(&:dup)
    end
  end
end
