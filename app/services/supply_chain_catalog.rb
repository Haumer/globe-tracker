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
      destination_country_alpha3: %w[CHN JPN KOR PHL TWN],
      requires_any_source_chokepoint: %w[hormuz mozambique],
      multiplier: 0.65,
      note: "Middle East and Indian Ocean energy cargoes into East Asia commonly transit the Strait of Malacca.",
    },
    {
      chokepoint_key: "suez",
      commodity_keys: %w[oil_crude oil_refined lng wheat fertilizer],
      destination_country_alpha3: %w[DEU ESP FRA GBR GRC ITA NLD POL],
      requires_any_source_chokepoint: %w[bab_el_mandeb],
      multiplier: 0.55,
      note: "Red Sea flows bound for Europe frequently depend on both Bab el-Mandeb and the Suez Canal.",
    },
  ].freeze

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

    def baseline_sector_inputs_for(sector_key)
      Array(BASELINE_SECTOR_INPUT_PRIORS[sector_key.to_s]).map(&:dup)
    end
  end
end
