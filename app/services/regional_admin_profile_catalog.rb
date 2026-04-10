require "set"

class RegionalAdminProfileCatalog
  REGION_COUNTRY_CODES = {
    "dach" => %w[AUT DEU CHE]
  }.freeze

  COUNTRY_CODE_ALIASES = {
    "AT" => "AUT",
    "AUT" => "AUT",
    "DE" => "DEU",
    "DEU" => "DEU",
    "CH" => "CHE",
    "CHE" => "CHE"
  }.freeze

  COUNTRY_NAME_TO_CODE = {
    "Austria" => "AUT",
    "Germany" => "DEU",
    "Switzerland" => "CHE"
  }.freeze

  BOUNDARY_NAME_ALIASES = {
    "AUT" => {
      "Carinthia" => ["Karnten", "Kärnten"],
      "Lower Austria" => ["Niederosterreich", "Niederösterreich"],
      "Upper Austria" => ["Oberosterreich", "Oberösterreich"],
      "Styria" => ["Steiermark"],
      "Tyrol" => ["Tirol"],
      "Vienna" => ["Wien"]
    },
    "DEU" => {
      "Baden-Wurttemberg" => ["Baden-Wurttemberg", "Baden-Württemberg"],
      "Bavaria" => ["Bayern"],
      "Brandenburg" => ["Brandenburg"],
      "Bremen" => ["Free Hanseatic Bremen"],
      "Hesse" => ["Hessen"],
      "Lower Saxony" => ["Niedersachsen"],
      "Mecklenburg-Vorpommern" => ["Mecklenburg-Western Pomerania"],
      "North Rhine-Westphalia" => ["Nordrhein-Westfalen"],
      "Rhineland-Palatinate" => ["Rheinland-Pfalz"],
      "Saxony" => ["Sachsen"],
      "Saxony-Anhalt" => ["Sachsen-Anhalt"],
      "Thuringia" => ["Thuringen", "Thüringen"]
    },
    "CHE" => {
      "Geneva" => ["Geneve", "Genève"],
      "Graubunden" => ["Graubunden", "Graubünden", "Grisons"],
      "Neuchatel" => ["Neuchatel", "Neuchâtel"],
      "St. Gallen" => ["Sankt Gallen", "St. Gallen"],
      "Zurich" => ["Zurich", "Zürich"]
    }
  }.freeze

  SECTOR_DEFINITIONS = [
    { key: "automotive", name: "Automotive", terms: ["automotive", "vehicle", "vehicles", "truck", "mobility", "driveline"] },
    { key: "semiconductors", name: "Semiconductors", terms: ["semiconductor", "chip", "chips", "electronics", "microtechnology", "microelectronics"] },
    { key: "chemicals", name: "Chemicals", terms: ["chemical", "chemicals", "refining", "refinery", "fuel", "silicones", "materials", "battery materials"] },
    { key: "energy", name: "Energy", terms: ["energy", "power", "hydropower", "electricity", "utilities", "green hydrogen"] },
    { key: "finance_services", name: "Finance & Services", terms: ["finance", "banking", "insurance", "private banking", "professional services", "commodity trading"] },
    { key: "logistics_trade", name: "Logistics & Trade", terms: ["logistics", "port", "trade", "distribution", "warehousing", "air cargo", "danube logistics", "rail logistics", "cross-border trade", "wholesale"] },
    { key: "government_policy", name: "Government & Policy", terms: ["government", "public administration", "federal administration", "policy", "administration", "public services", "institutions"] },
    { key: "life_sciences", name: "Life Sciences", terms: ["pharma", "pharmaceuticals", "biopharma", "life sciences", "medical technology", "health services"] },
    { key: "machinery_engineering", name: "Machinery & Engineering", terms: ["machinery", "engineering", "industrial automation", "industrial technology", "metals", "steel", "forgings", "precision manufacturing"] },
    { key: "knowledge_tech", name: "Knowledge & Tech", terms: ["software", "digital", "research", "ai", "education", "technology", "telecom"] },
    { key: "tourism", name: "Tourism", terms: ["tourism", "hospitality", "winter sports"] }
  ].freeze

  COMMODITY_SECTOR_MAP = {
    "automotive" => "automotive",
    "semiconductors" => "semiconductors",
    "chemicals" => "chemicals",
    "steel" => "machinery_engineering",
    "oil_refined" => "energy",
    "pharmaceuticals" => "life_sciences",
    "battery_materials" => "energy"
  }.freeze

  class << self
    def all
      groups = {}

      RegionalCityProfileCatalog.all.each do |record|
        admin_area = record["admin_area"].to_s.strip
        next if admin_area.blank?

        group = groups[group_key_for(record["country_code"], record["country_name"], admin_area)] ||= base_group(record["country_code"], record["country_name"], admin_area)

        group[:city_count] += 1
        group[:capital_count] += 1 if Array(record["role_tags"]).any? { |tag| %w[capital state_capital].include?(tag.to_s) }
        Array(record["role_tags"]).each { |tag| group[:role_tags] << tag.to_s }
        Array(record["strategic_sectors"]).each { |sector| group[:sectors] << sector.to_s }
        group[:points] << [record["lat"].to_f, record["lng"].to_f] if record["lat"].present? && record["lng"].present?
        sector_keys = infer_sector_keys(
          Array(record["strategic_sectors"]) + Array(record["role_tags"]) + [record["summary"]]
        )
        register_sector_signals!(group, sector_keys, source_model: "city_profiles")
        register_node!(
          group,
          node_key: "city:#{record["id"]}",
          node_name: record["name"],
          node_kind: "city",
          sector_keys: sector_keys,
          weight: 1.2
        )
        group[:source_models] << "city_profiles"
        group[:source_packs] << (record["source_pack"].presence || "city_profiles")
      end

      CuratedPowerPlantCatalog.all.each do |record|
        admin_area = record["admin_area"].to_s.strip
        next if admin_area.blank?

        group = groups[group_key_for(record["country_code"], record["country_name"], admin_area)] ||= base_group(record["country_code"], record["country_name"], admin_area)

        group[:curated_power_plant_count] += 1
        group[:curated_power_capacity_mw] += record["capacity_mw"].to_f if record["capacity_mw"].present?
        group[:sectors] << record["primary_fuel"].to_s if record["primary_fuel"].present?
        register_sector_signals!(group, %w[energy], source_model: "power_plants")
        register_node!(
          group,
          node_key: "power:#{record["id"]}",
          node_name: record["name"],
          node_kind: "power_plant",
          sector_keys: %w[energy],
          weight: 1.6
        )
        group[:source_models] << "power_plants"
        group[:source_packs] << "dach_curated_power_plant_overrides"
      end

      CommoditySiteCatalog.all.each do |record|
        admin_area = record["admin_area"].to_s.strip
        next if admin_area.blank?

        group = groups[group_key_for(record["country_code"], record["country_name"], admin_area)] ||= base_group(record["country_code"], record["country_name"], admin_area)

        group[:strategic_site_count] += 1
        group[:site_commodities] << record["commodity_name"].to_s if record["commodity_name"].present?
        group[:sectors] << record["commodity_name"].to_s if record["commodity_name"].present?
        group[:points] << [record["lat"].to_f, record["lng"].to_f] if record["lat"].present? && record["lng"].present?
        sector_keys = infer_sector_keys(
          [record["commodity_key"], record["commodity_name"], record["site_kind"], record["summary"], *Array(record["products"])],
          commodity_key: record["commodity_key"]
        )
        register_sector_signals!(group, sector_keys, source_model: "strategic_sites")
        register_node!(
          group,
          node_key: "site:#{record["id"]}",
          node_name: record["name"],
          node_kind: "strategic_site",
          sector_keys: sector_keys,
          weight: 2.1
        )
        group[:source_models] << "strategic_sites"
        group[:source_packs] << (record["source_dataset"].presence || "dach_strategic_sites")
      end

      finalize(groups.values)
    end

    def filtered(region_key: nil, country_codes: nil)
      records = all
      codes = normalized_country_codes(region_key: region_key, country_codes: country_codes)
      return records if codes.blank?

      records.select { |record| codes.include?(record["country_code_alpha3"]) }
    end

    def etag
      [
        "regional-admin-profiles",
        RegionalCityProfileCatalog.etag,
        CuratedPowerPlantCatalog.etag,
        CommoditySiteCatalog.etag
      ].join(":")
    end

    private

    def base_group(country_code, country_name, admin_area)
      alpha3 = normalize_country_code(country_code, country_name)

      {
        country_code_alpha3: alpha3,
        country_name: country_name.to_s.strip.presence || country_name_for(alpha3),
        admin_area: admin_area,
        city_count: 0,
        capital_count: 0,
        strategic_site_count: 0,
        curated_power_plant_count: 0,
        curated_power_capacity_mw: 0.0,
        role_tags: Set.new,
        sectors: Set.new,
        site_commodities: Set.new,
        sector_profiles: {},
        nodes: {},
        points: [],
        source_models: Set.new,
        source_packs: Set.new
      }
    end

    def group_key_for(country_code, country_name, admin_area)
      "#{normalize_country_code(country_code, country_name)}:#{admin_area}"
    end

    def finalize(groups)
      prepared = groups.map do |group|
        raw_score = compute_raw_score(group)
        lat, lng = averaged_point(group[:points])

        {
          "id" => "admin-#{group[:country_code_alpha3].downcase}-#{slugify(group[:admin_area])}",
          "country_code_alpha3" => group[:country_code_alpha3],
          "country_name" => group[:country_name],
          "admin_level" => "admin_1",
          "name" => group[:admin_area],
          "boundary_names" => boundary_names_for(group[:country_code_alpha3], group[:admin_area]),
          "lat" => lat,
          "lng" => lng,
          "metrics" => {
            "city_count" => group[:city_count],
            "capital_count" => group[:capital_count],
            "strategic_site_count" => group[:strategic_site_count],
            "curated_power_plant_count" => group[:curated_power_plant_count],
            "curated_power_capacity_mw" => group[:curated_power_capacity_mw].round(1),
            "role_diversity_count" => group[:role_tags].size,
            "sector_diversity_count" => group[:sectors].size,
            "raw_preview_score" => raw_score.round(2)
          },
          "sector_profiles" => build_sector_profiles(group),
          "top_nodes" => build_top_nodes(group),
          "source_models" => group[:source_models].to_a.sort,
          "source_packs" => group[:source_packs].to_a.sort
        }
      end

      max_sector_scores = prepared.each_with_object({}) do |record, memo|
        Array(record["sector_profiles"]).each do |profile|
          key = profile["sector_key"]
          next if key.blank?

          memo[key] = [memo[key].to_f, profile["raw_score"].to_f].max
        end
      end

      max_score = prepared.map { |record| record.dig("metrics", "raw_preview_score").to_f }.max.to_f
      scale = max_score.positive? ? max_score : 1.0

      prepared.each do |record|
        metrics = record.fetch("metrics")
        preview_score = ((metrics["raw_preview_score"].to_f / scale) * 100.0).round(1)
        metrics["preview_score"] = preview_score
        Array(record["sector_profiles"]).each do |profile|
          sector_scale = max_sector_scores[profile["sector_key"]].to_f
          normalized = sector_scale.positive? ? (profile["raw_score"].to_f / sector_scale) * 100.0 : 0.0
          profile["score"] = normalized.round(1)
        end
        record["sector_profiles"] = Array(record["sector_profiles"])
          .sort_by { |profile| [ -profile["score"].to_f, -profile["signal_count"].to_i, profile["sector_name"].to_s ] }
        record["top_sectors"] = record["sector_profiles"].first(4)
        record["summary"] = summary_for(metrics, record["top_sectors"])
      end

      prepared.sort_by { |record| [record["country_name"], record["name"]] }
    end

    def summary_for(metrics, top_sectors = [])
      parts = []
      parts << "#{metrics["city_count"]} profiled cities" if metrics["city_count"].to_i.positive?
      parts << "#{metrics["strategic_site_count"]} strategic sites" if metrics["strategic_site_count"].to_i.positive?
      if metrics["curated_power_capacity_mw"].to_f.positive?
        gw = (metrics["curated_power_capacity_mw"].to_f / 1000.0).round(1)
        parts << "#{gw} GW curated power"
      end
      top_labels = Array(top_sectors).first(2).map { |profile| profile["sector_name"] }.compact
      parts << top_labels.join(" + ") if top_labels.any?
      parts.join(" · ").presence || "No profiled enrichment yet"
    end

    def compute_raw_score(group)
      city_score = group[:city_count] * 18.0
      capital_score = group[:capital_count] * 10.0
      site_score = group[:strategic_site_count] * 22.0
      role_score = group[:role_tags].size * 3.5
      sector_score = [group[:sectors].size, 12].min * 2.5
      power_score = [group[:curated_power_capacity_mw] / 120.0, 18.0].min

      city_score + capital_score + site_score + role_score + sector_score + power_score
    end

    def averaged_point(points)
      clean = Array(points).select { |lat, lng| lat.present? && lng.present? }
      return [nil, nil] if clean.empty?

      lat = clean.sum { |pair| pair[0].to_f } / clean.size
      lng = clean.sum { |pair| pair[1].to_f } / clean.size
      [lat.round(4), lng.round(4)]
    end

    def boundary_names_for(country_code_alpha3, admin_area)
      names = [admin_area, *Array(BOUNDARY_NAME_ALIASES.dig(country_code_alpha3, admin_area))]
      names.compact.map(&:to_s).map(&:strip).reject(&:blank?).uniq
    end

    def normalized_country_codes(region_key:, country_codes:)
      region_codes = Array(REGION_COUNTRY_CODES[region_key.to_s])
      explicit_codes = Array(country_codes)
        .flat_map { |value| value.to_s.split(",") }
        .map { |code| normalize_country_code(code, nil) }
        .compact

      values = region_codes + explicit_codes
      values.compact.uniq
    end

    def normalize_country_code(country_code, country_name)
      COUNTRY_CODE_ALIASES[country_code.to_s.strip.upcase] || COUNTRY_NAME_TO_CODE[country_name.to_s.strip] || country_code.to_s.strip.upcase.presence
    end

    def country_name_for(alpha3)
      COUNTRY_NAME_TO_CODE.key(alpha3) || alpha3
    end

    def build_sector_profiles(group)
      group[:sector_profiles].values.map do |profile|
        signal_count = profile[:city_signal_count] + profile[:strategic_site_count] + profile[:power_signal_count]
        raw_score =
          (profile[:city_signal_count] * 14.0) +
          (profile[:strategic_site_count] * 24.0) +
          (profile[:power_signal_count] * 18.0) +
          ([profile[:node_keys].size, 6].min * 2.5)

        {
          "sector_key" => profile[:sector_key],
          "sector_name" => profile[:sector_name],
          "signal_count" => signal_count,
          "city_signal_count" => profile[:city_signal_count],
          "strategic_site_count" => profile[:strategic_site_count],
          "power_signal_count" => profile[:power_signal_count],
          "node_count" => profile[:node_keys].size,
          "raw_score" => raw_score.round(2)
        }
      end
    end

    def build_top_nodes(group)
      group[:nodes].values
        .sort_by { |node| [ -node[:weight].to_f, node[:node_kind].to_s, node[:name].to_s ] }
        .first(8)
        .map do |node|
          {
            "name" => node[:name],
            "node_kind" => node[:node_kind],
            "sector_keys" => node[:sector_keys].to_a.sort,
            "sector_names" => node[:sector_keys].map { |key| sector_name_for(key) }.compact.sort
          }
        end
    end

    def register_sector_signals!(group, sector_keys, source_model:)
      Array(sector_keys).compact.uniq.each do |sector_key|
        definition = sector_definition_for(sector_key)
        next unless definition

        profile = group[:sector_profiles][sector_key] ||= {
          sector_key: definition[:key],
          sector_name: definition[:name],
          city_signal_count: 0,
          strategic_site_count: 0,
          power_signal_count: 0,
          node_keys: Set.new
        }

        case source_model
        when "city_profiles"
          profile[:city_signal_count] += 1
        when "strategic_sites"
          profile[:strategic_site_count] += 1
        when "power_plants"
          profile[:power_signal_count] += 1
        end
      end
    end

    def register_node!(group, node_key:, node_name:, node_kind:, sector_keys:, weight:)
      return if node_key.blank? || node_name.blank?

      node = group[:nodes][node_key] ||= {
        key: node_key,
        name: node_name,
        node_kind: node_kind,
        sector_keys: Set.new,
        weight: 0.0
      }

      Array(sector_keys).each do |sector_key|
        node[:sector_keys] << sector_key
        profile = group[:sector_profiles][sector_key]
        profile[:node_keys] << node_key if profile
      end
      node[:weight] += weight.to_f
    end

    def infer_sector_keys(values, commodity_key: nil)
      matched = Set.new
      direct = COMMODITY_SECTOR_MAP[commodity_key.to_s]
      matched << direct if direct.present?

      Array(values).each do |value|
        normalized = normalize_sector_value(value)
        next if normalized.blank?

        SECTOR_DEFINITIONS.each do |definition|
          if Array(definition[:terms]).any? { |term| normalized.include?(normalize_sector_value(term)) }
            matched << definition[:key]
          end
        end
      end

      matched.to_a
    end

    def normalize_sector_value(value)
      ActiveSupport::Inflector.transliterate(value.to_s).downcase
    end

    def sector_definition_for(sector_key)
      SECTOR_DEFINITIONS.find { |definition| definition[:key] == sector_key.to_s }
    end

    def sector_name_for(sector_key)
      sector_definition_for(sector_key)&.dig(:name)
    end

    def slugify(value)
      ActiveSupport::Inflector.transliterate(value.to_s)
        .downcase
        .gsub(/[^a-z0-9]+/, "-")
        .gsub(/\A-+|-+\z/, "")
    end
  end
end
