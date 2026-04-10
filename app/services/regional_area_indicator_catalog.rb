require "json"
require "net/http"
require "uri"

class RegionalAreaIndicatorCatalog
  EUROSTAT_POPULATION_DATASET = "demo_r_pjanaggr3".freeze
  EUROSTAT_POPULATION_URL = "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/#{EUROSTAT_POPULATION_DATASET}".freeze
  SWISS_BFS_POPULATION_URL = "https://www.pxweb.bfs.admin.ch/api/v1/en/px-x-0103010000_102/px-x-0103010000_102.px".freeze
  CACHE_TTL = 12.hours

  DACH_REGION_DEFINITIONS = [
    { key: "region:aut:burgenland", country_code: "AT", country_code_alpha3: "AUT", country_name: "Austria", name: "Burgenland", native_level: "state", iso_3166_2: "AT-1", source_system: "eurostat", source_geo: "AT11" },
    { key: "region:aut:lower-austria", country_code: "AT", country_code_alpha3: "AUT", country_name: "Austria", name: "Lower Austria", native_level: "state", iso_3166_2: "AT-3", source_system: "eurostat", source_geo: "AT12" },
    { key: "region:aut:vienna", country_code: "AT", country_code_alpha3: "AUT", country_name: "Austria", name: "Vienna", native_level: "state", iso_3166_2: "AT-9", source_system: "eurostat", source_geo: "AT13" },
    { key: "region:aut:carinthia", country_code: "AT", country_code_alpha3: "AUT", country_name: "Austria", name: "Carinthia", native_level: "state", iso_3166_2: "AT-2", source_system: "eurostat", source_geo: "AT21" },
    { key: "region:aut:styria", country_code: "AT", country_code_alpha3: "AUT", country_name: "Austria", name: "Styria", native_level: "state", iso_3166_2: "AT-6", source_system: "eurostat", source_geo: "AT22" },
    { key: "region:aut:upper-austria", country_code: "AT", country_code_alpha3: "AUT", country_name: "Austria", name: "Upper Austria", native_level: "state", iso_3166_2: "AT-4", source_system: "eurostat", source_geo: "AT31" },
    { key: "region:aut:salzburg", country_code: "AT", country_code_alpha3: "AUT", country_name: "Austria", name: "Salzburg", native_level: "state", iso_3166_2: "AT-5", source_system: "eurostat", source_geo: "AT32" },
    { key: "region:aut:tyrol", country_code: "AT", country_code_alpha3: "AUT", country_name: "Austria", name: "Tyrol", native_level: "state", iso_3166_2: "AT-7", source_system: "eurostat", source_geo: "AT33" },
    { key: "region:aut:vorarlberg", country_code: "AT", country_code_alpha3: "AUT", country_name: "Austria", name: "Vorarlberg", native_level: "state", iso_3166_2: "AT-8", source_system: "eurostat", source_geo: "AT34" },
    { key: "region:deu:baden-wurttemberg", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Baden-Wurttemberg", native_level: "land", iso_3166_2: "DE-BW", source_system: "eurostat", source_geo: "DE1" },
    { key: "region:deu:bavaria", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Bavaria", native_level: "land", iso_3166_2: "DE-BY", source_system: "eurostat", source_geo: "DE2" },
    { key: "region:deu:berlin", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Berlin", native_level: "land", iso_3166_2: "DE-BE", source_system: "eurostat", source_geo: "DE3" },
    { key: "region:deu:brandenburg", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Brandenburg", native_level: "land", iso_3166_2: "DE-BB", source_system: "eurostat", source_geo: "DE4" },
    { key: "region:deu:bremen", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Bremen", native_level: "land", iso_3166_2: "DE-HB", source_system: "eurostat", source_geo: "DE5" },
    { key: "region:deu:hamburg", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Hamburg", native_level: "land", iso_3166_2: "DE-HH", source_system: "eurostat", source_geo: "DE6" },
    { key: "region:deu:hesse", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Hesse", native_level: "land", iso_3166_2: "DE-HE", source_system: "eurostat", source_geo: "DE7" },
    { key: "region:deu:mecklenburg-western-pomerania", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Mecklenburg-Vorpommern", native_level: "land", iso_3166_2: "DE-MV", source_system: "eurostat", source_geo: "DE8" },
    { key: "region:deu:lower-saxony", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Lower Saxony", native_level: "land", iso_3166_2: "DE-NI", source_system: "eurostat", source_geo: "DE9" },
    { key: "region:deu:north-rhine-westphalia", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "North Rhine-Westphalia", native_level: "land", iso_3166_2: "DE-NW", source_system: "eurostat", source_geo: "DEA" },
    { key: "region:deu:rhineland-palatinate", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Rhineland-Palatinate", native_level: "land", iso_3166_2: "DE-RP", source_system: "eurostat", source_geo: "DEB" },
    { key: "region:deu:saarland", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Saarland", native_level: "land", iso_3166_2: "DE-SL", source_system: "eurostat", source_geo: "DEC" },
    { key: "region:deu:saxony", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Saxony", native_level: "land", iso_3166_2: "DE-SN", source_system: "eurostat", source_geo: "DED" },
    { key: "region:deu:saxony-anhalt", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Saxony-Anhalt", native_level: "land", iso_3166_2: "DE-ST", source_system: "eurostat", source_geo: "DEE" },
    { key: "region:deu:schleswig-holstein", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Schleswig-Holstein", native_level: "land", iso_3166_2: "DE-SH", source_system: "eurostat", source_geo: "DEF" },
    { key: "region:deu:thuringia", country_code: "DE", country_code_alpha3: "DEU", country_name: "Germany", name: "Thuringia", native_level: "land", iso_3166_2: "DE-TH", source_system: "eurostat", source_geo: "DEG" },
    { key: "region:che:zurich", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Zurich", native_level: "canton", iso_3166_2: "CH-ZH", source_system: "bfs", source_geo: "ZH" },
    { key: "region:che:bern", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Bern", native_level: "canton", iso_3166_2: "CH-BE", source_system: "bfs", source_geo: "BE" },
    { key: "region:che:lucerne", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Lucerne", native_level: "canton", iso_3166_2: "CH-LU", source_system: "bfs", source_geo: "LU" },
    { key: "region:che:uri", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Uri", native_level: "canton", iso_3166_2: "CH-UR", source_system: "bfs", source_geo: "UR" },
    { key: "region:che:schwyz", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Schwyz", native_level: "canton", iso_3166_2: "CH-SZ", source_system: "bfs", source_geo: "SZ" },
    { key: "region:che:obwalden", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Obwalden", native_level: "canton", iso_3166_2: "CH-OW", source_system: "bfs", source_geo: "OW" },
    { key: "region:che:nidwalden", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Nidwalden", native_level: "canton", iso_3166_2: "CH-NW", source_system: "bfs", source_geo: "NW" },
    { key: "region:che:glarus", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Glarus", native_level: "canton", iso_3166_2: "CH-GL", source_system: "bfs", source_geo: "GL" },
    { key: "region:che:zug", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Zug", native_level: "canton", iso_3166_2: "CH-ZG", source_system: "bfs", source_geo: "ZG" },
    { key: "region:che:fribourg", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Fribourg", native_level: "canton", iso_3166_2: "CH-FR", source_system: "bfs", source_geo: "FR" },
    { key: "region:che:solothurn", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Solothurn", native_level: "canton", iso_3166_2: "CH-SO", source_system: "bfs", source_geo: "SO" },
    { key: "region:che:basel-stadt", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Basel-Stadt", native_level: "canton", iso_3166_2: "CH-BS", source_system: "bfs", source_geo: "BS" },
    { key: "region:che:basel-landschaft", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Basel-Landschaft", native_level: "canton", iso_3166_2: "CH-BL", source_system: "bfs", source_geo: "BL" },
    { key: "region:che:schaffhausen", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Schaffhausen", native_level: "canton", iso_3166_2: "CH-SH", source_system: "bfs", source_geo: "SH" },
    { key: "region:che:appenzell-ausserrhoden", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Appenzell Ausserrhoden", native_level: "canton", iso_3166_2: "CH-AR", source_system: "bfs", source_geo: "AR" },
    { key: "region:che:appenzell-innerrhoden", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Appenzell Innerrhoden", native_level: "canton", iso_3166_2: "CH-AI", source_system: "bfs", source_geo: "AI" },
    { key: "region:che:st-gallen", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "St. Gallen", native_level: "canton", iso_3166_2: "CH-SG", source_system: "bfs", source_geo: "SG" },
    { key: "region:che:graubunden", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Graubunden", native_level: "canton", iso_3166_2: "CH-GR", source_system: "bfs", source_geo: "GR" },
    { key: "region:che:aargau", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Aargau", native_level: "canton", iso_3166_2: "CH-AG", source_system: "bfs", source_geo: "AG" },
    { key: "region:che:thurgau", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Thurgau", native_level: "canton", iso_3166_2: "CH-TG", source_system: "bfs", source_geo: "TG" },
    { key: "region:che:ticino", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Ticino", native_level: "canton", iso_3166_2: "CH-TI", source_system: "bfs", source_geo: "TI" },
    { key: "region:che:vaud", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Vaud", native_level: "canton", iso_3166_2: "CH-VD", source_system: "bfs", source_geo: "VD" },
    { key: "region:che:valais", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Valais", native_level: "canton", iso_3166_2: "CH-VS", source_system: "bfs", source_geo: "VS" },
    { key: "region:che:neuchatel", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Neuchatel", native_level: "canton", iso_3166_2: "CH-NE", source_system: "bfs", source_geo: "NE" },
    { key: "region:che:geneva", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Geneva", native_level: "canton", iso_3166_2: "CH-GE", source_system: "bfs", source_geo: "GE" },
    { key: "region:che:jura", country_code: "CH", country_code_alpha3: "CHE", country_name: "Switzerland", name: "Jura", native_level: "canton", iso_3166_2: "CH-JU", source_system: "bfs", source_geo: "JU" },
  ].freeze

  class << self
    def filtered(region_key:, comparable_level: "region")
      return [] unless region_key.to_s == "dach"
      return [] unless comparable_level.to_s == "region"

      build_dach_region_population_records
    rescue StandardError => error
      Rails.logger.error("RegionalAreaIndicatorCatalog failed: #{error.message}")
      []
    end

    def etag(region_key: nil, comparable_level: "region")
      "regional-area-indicators:v1:#{region_key}:#{comparable_level}"
    end

    private

    def build_dach_region_population_records
      eurostat_definitions = DACH_REGION_DEFINITIONS.select { |definition| definition[:source_system] == "eurostat" }
      bfs_definitions = DACH_REGION_DEFINITIONS.select { |definition| definition[:source_system] == "bfs" }

      eurostat_records = build_eurostat_population_records(eurostat_definitions)
      bfs_records = build_bfs_population_records(bfs_definitions)

      (eurostat_records + bfs_records).sort_by do |record|
        [
          record["country_name"].to_s,
          -(record.dig("metrics", "population_total") || 0.0),
          record["name"].to_s,
        ]
      end
    end

    def build_eurostat_population_records(definitions)
      payload = Rails.cache.fetch("regional-area-indicators:eurostat:population:v2", expires_in: CACHE_TTL) do
        uri = URI(EUROSTAT_POPULATION_URL)
        uri.query = URI.encode_www_form(
          definitions.map { |definition| ["geo", definition[:source_geo]] } + [
            ["sex", "T"],
            ["age", "TOTAL"],
            ["unit", "NR"]
          ]
        )
        fetch_json(uri)
      end
      return [] unless payload.is_a?(Hash)

      definitions.filter_map do |definition|
        latest = latest_jsonstat_value(payload, definition[:source_geo])
        next unless latest

        build_region_record(
          definition,
          metric_key: "population_total",
          metric_value: latest[:value],
          latest_year: latest[:year],
          source_name: "Eurostat Regional Population",
          source_provider: "Eurostat",
          source_dataset: EUROSTAT_POPULATION_DATASET,
          source_url: EUROSTAT_POPULATION_URL,
          source_updated_at: payload["updated"]
        )
      end
    end

    def build_bfs_population_records(definitions)
      payload = Rails.cache.fetch("regional-area-indicators:bfs:population:v1", expires_in: CACHE_TTL) do
        uri = URI(SWISS_BFS_POPULATION_URL)
        body = {
          query: [
            { code: "Jahr", selection: { filter: "item", values: ["2024"] } },
            { code: "Kanton", selection: { filter: "item", values: definitions.map { |definition| definition[:source_geo] } } },
            { code: "Bevölkerungstyp", selection: { filter: "item", values: ["1"] } },
            { code: "Anwesenheitsbewilligung", selection: { filter: "item", values: ["-99999"] } },
            { code: "Geburtsort", selection: { filter: "item", values: ["-99999"] } },
            { code: "Geschlecht", selection: { filter: "item", values: ["-99999"] } },
            { code: "Alter", selection: { filter: "item", values: ["-99999"] } },
          ],
          response: { format: "json-stat2" }
        }
        fetch_json(uri, method: :post, body: JSON.generate(body), headers: { "Content-Type" => "application/json" })
      end
      return [] unless payload.is_a?(Hash)

      definitions.filter_map do |definition|
        value = bfs_value_for(payload, definition[:source_geo])
        next if value.nil?

        build_region_record(
          definition,
          metric_key: "population_total",
          metric_value: value,
          latest_year: 2024,
          source_name: "Swiss BFS Canton Population",
          source_provider: "Swiss Federal Statistical Office",
          source_dataset: "px-x-0103010000_102",
          source_url: SWISS_BFS_POPULATION_URL,
          source_updated_at: payload["updated"]
        )
      end
    end

    def build_region_record(definition, metric_key:, metric_value:, latest_year:, source_name:, source_provider:, source_dataset:, source_url:, source_updated_at:)
      {
        "id" => definition[:key].tr(":", "-"),
        "geography_kind" => "region",
        "geography_key" => definition[:key],
        "comparable_level" => "region",
        "native_level" => definition[:native_level],
        "name" => definition[:name],
        "country_code" => definition[:country_code],
        "country_code_alpha3" => definition[:country_code_alpha3],
        "country_name" => definition[:country_name],
        "iso_3166_2" => definition[:iso_3166_2],
        "source_geo" => definition[:source_geo],
        "latest_year" => latest_year,
        "source_name" => source_name,
        "source_provider" => source_provider,
        "source_dataset" => source_dataset,
        "source_url" => source_url,
        "source_updated_at" => source_updated_at,
        "metrics" => {
          metric_key => metric_value.to_f
        }
      }
    end

    def latest_jsonstat_value(payload, geo_code)
      geo_index = payload.dig("dimension", "geo", "category", "index", geo_code)
      time_index = payload.dig("dimension", "time", "category", "index") || {}
      size_time = Array(payload["size"]).last.to_i
      return nil if geo_index.nil? || size_time <= 0

      time_index.keys
        .sort_by { |value| value.to_i }
        .reverse_each do |year|
          flat_index = geo_index.to_i * size_time + time_index[year].to_i
          value = payload.fetch("value", {})[flat_index.to_s]
          value = payload.fetch("value", {})[flat_index] if value.nil?
          next if value.nil?

          return { year: year.to_i, value: value.to_f }
        end

      nil
    end

    def bfs_value_for(payload, canton_code)
      index = payload.dig("dimension", "Kanton", "category", "index", canton_code)
      return nil if index.nil?

      Array(payload["value"])[index]&.to_f
    end

    def fetch_json(uri, method: :get, body: nil, headers: {})
      request_class = method.to_s == "post" ? Net::HTTP::Post : Net::HTTP::Get
      request = request_class.new(uri)
      headers.each { |key, value| request[key] = value }
      request.body = body if body.present?

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 45) do |http|
        http.request(request)
      end

      raise "HTTP #{response.code} from #{uri.host}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
