class RegionalIndicatorCatalog
  INDICATOR_KEYS = %w[
    gdp_nominal_usd
    gdp_per_capita_usd
    population_total
    imports_goods_services_pct_gdp
    exports_goods_services_pct_gdp
    energy_imports_net_pct_energy_use
  ].freeze
  SECTOR_KEYS = %w[manufacturing industry services agriculture].freeze

  class << self
    def filtered(country_codes: nil, country_names: nil)
      indicator_rows = latest_indicator_rows(country_codes: country_codes, country_names: country_names)
      sector_rows = latest_sector_rows(country_codes: country_codes, country_names: country_names)

      build_records(indicator_rows: indicator_rows, sector_rows: sector_rows)
    rescue StandardError => error
      Rails.logger.error("RegionalIndicatorCatalog failed: #{error.message}")
      []
    end

    def etag
      indicator_max = CountryIndicatorSnapshot.where(indicator_key: INDICATOR_KEYS).maximum(:updated_at)&.to_i || 0
      sector_max = CountrySectorSnapshot.where(metric_key: "gdp_share_pct", sector_key: SECTOR_KEYS).maximum(:updated_at)&.to_i || 0

      "regional-indicators:#{indicator_max}:#{sector_max}"
    rescue StandardError
      "regional-indicators:error"
    end

    private

    def latest_indicator_rows(country_codes:, country_names:)
      rows = CountryIndicatorSnapshot
        .where(indicator_key: INDICATOR_KEYS)
        .order(country_code_alpha3: :asc, indicator_key: :asc, period_start: :desc, fetched_at: :desc)
        .to_a

      rows = filter_rows(rows, country_codes: country_codes, country_names: country_names)
      rows
        .group_by { |row| [row.country_code_alpha3.to_s.upcase, row.indicator_key.to_s] }
        .values
        .map(&:first)
    end

    def latest_sector_rows(country_codes:, country_names:)
      rows = CountrySectorSnapshot
        .where(metric_key: "gdp_share_pct", sector_key: SECTOR_KEYS)
        .order(country_code_alpha3: :asc, sector_key: :asc, period_year: :desc, fetched_at: :desc)
        .to_a

      rows = filter_rows(rows, country_codes: country_codes, country_names: country_names)
      rows
        .group_by { |row| [row.country_code_alpha3.to_s.upcase, row.sector_key.to_s] }
        .values
        .map(&:first)
    end

    def filter_rows(rows, country_codes:, country_names:)
      codes = normalize_codes(country_codes)
      names = normalize_names(country_names)
      return rows if codes.blank? && names.blank?

      rows.select do |row|
        code_match = codes.include?(row.country_code_alpha3.to_s.upcase) || codes.include?(row.country_code.to_s.upcase)
        name_match = names.include?(row.country_name.to_s.downcase)
        code_match || name_match
      end
    end

    def build_records(indicator_rows:, sector_rows:)
      indicators_by_country = indicator_rows.group_by(&:country_code_alpha3)
      sectors_by_country = sector_rows.group_by(&:country_code_alpha3)

      country_codes = (indicators_by_country.keys + sectors_by_country.keys).compact.uniq

      country_codes.filter_map do |country_alpha3|
        indicator_lookup = Array(indicators_by_country[country_alpha3]).index_by(&:indicator_key)
        sector_lookup = Array(sectors_by_country[country_alpha3]).index_by(&:sector_key)
        representative = indicator_lookup.values.first || sector_lookup.values.first
        next unless representative

        source_rows = indicator_lookup.values + sector_lookup.values
        latest_year = (
          indicator_lookup.values.map { |row| row.period_start&.year } +
          sector_lookup.values.map(&:period_year)
        ).compact.max

        {
          geography_kind: "country",
          geography_key: "country:#{country_alpha3.to_s.downcase}",
          geography_name: representative.country_name,
          country_code: representative.country_code,
          country_code_alpha3: representative.country_code_alpha3,
          country_name: representative.country_name,
          latest_year: latest_year,
          fetched_at: source_rows.filter_map(&:fetched_at).max&.utc&.iso8601,
          source_name: SupplyChainCatalog::WORLD_BANK_SOURCE[:display_name],
          source_url: SupplyChainCatalog::WORLD_BANK_SOURCE[:endpoint_url],
          source_provider: SupplyChainCatalog::WORLD_BANK_SOURCE[:provider],
          datasets: source_rows.map(&:dataset).compact.uniq.sort,
          release_versions: source_rows.map(&:release_version).compact.uniq.sort.reverse,
          metrics: {
            gdp_nominal_usd: numeric_value(indicator_lookup["gdp_nominal_usd"]&.value_numeric),
            gdp_per_capita_usd: numeric_value(indicator_lookup["gdp_per_capita_usd"]&.value_numeric),
            population_total: numeric_value(indicator_lookup["population_total"]&.value_numeric),
            imports_goods_services_pct_gdp: numeric_value(indicator_lookup["imports_goods_services_pct_gdp"]&.value_numeric),
            exports_goods_services_pct_gdp: numeric_value(indicator_lookup["exports_goods_services_pct_gdp"]&.value_numeric),
            energy_imports_net_pct_energy_use: numeric_value(indicator_lookup["energy_imports_net_pct_energy_use"]&.value_numeric),
            manufacturing_share_pct: numeric_value(sector_lookup["manufacturing"]&.value_numeric),
            industry_share_pct: numeric_value(sector_lookup["industry"]&.value_numeric),
            services_share_pct: numeric_value(sector_lookup["services"]&.value_numeric),
            agriculture_share_pct: numeric_value(sector_lookup["agriculture"]&.value_numeric),
          },
          top_sectors: Array(sectors_by_country[country_alpha3])
            .sort_by { |row| [-(numeric_value(row.value_numeric) || 0.0), row.sector_name.to_s] }
            .first(4)
            .map do |row|
              {
                sector_key: row.sector_key,
                sector_name: row.sector_name,
                share_pct: numeric_value(row.value_numeric),
                period_year: row.period_year,
              }
            end,
          metadata: {
            indicator_periods: indicator_lookup.transform_values { |row| row.period_start&.year },
            sector_periods: sector_lookup.transform_values(&:period_year),
          },
        }
      end.sort_by do |record|
        [
          -(record.dig(:metrics, :gdp_nominal_usd) || 0.0),
          record[:country_name].to_s,
        ]
      end
    end

    def numeric_value(value)
      return nil if value.blank?

      value.to_f
    end

    def normalize_codes(value)
      Array(value)
        .flat_map { |item| item.to_s.split(",") }
        .map { |item| item.to_s.strip.upcase }
        .reject(&:blank?)
        .uniq
    end

    def normalize_names(value)
      Array(value)
        .flat_map { |item| item.to_s.split(",") }
        .map { |item| item.to_s.strip.downcase }
        .reject(&:blank?)
        .uniq
    end
  end
end
