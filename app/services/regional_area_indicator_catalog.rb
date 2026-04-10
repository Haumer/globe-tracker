require "json"
require "net/http"
require "uri"
require "csv"
require "open3"
require "rexml/document"
require "stringio"
require "zip"

class RegionalAreaIndicatorCatalog
  EUROSTAT_POPULATION_DATASET = "demo_r_pjanaggr3".freeze
  EUROSTAT_POPULATION_URL = "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/#{EUROSTAT_POPULATION_DATASET}".freeze
  SWISS_BFS_POPULATION_URL = "https://www.pxweb.bfs.admin.ch/api/v1/en/px-x-0103010000_102/px-x-0103010000_102.px".freeze
  SWISS_BFS_DISTRICT_POPULATION_URL = "https://www.pxweb.bfs.admin.ch/api/v1/en/px-x-0102010000_104/px-x-0102010000_104.px".freeze
  DESTATIS_DISTRICT_POPULATION_URL = "https://www.destatis.de/DE/Themen/Laender-Regionen/Regionales/Gemeindeverzeichnis/Administrativ/04-kreise.xlsx?__blob=publicationFile&v=14".freeze
  AUSTRIA_POPULATION_2024_URL = "https://data.statistik.gv.at/data/OGD_bevstandjbab2002_BevStand_2024.csv".freeze
  AUSTRIA_DISTRICT_HEADER_URL = "https://data.statistik.gv.at/data/OGD_f0743_VZ_HIS_GEM_2_C-GRGEM17-0.csv".freeze
  GERMANY_DISTRICT_SNAPSHOT_PATH = Rails.root.join("db", "data", "regional_area_indicator_sources", "dach_germany_district_population.json").freeze
  CACHE_TTL = 12.hours

  AUSTRIA_STATE_NAMES = {
    "1" => "Burgenland",
    "2" => "Carinthia",
    "3" => "Lower Austria",
    "4" => "Upper Austria",
    "5" => "Salzburg",
    "6" => "Styria",
    "7" => "Tyrol",
    "8" => "Vorarlberg",
    "9" => "Vienna"
  }.freeze

  GERMANY_STATE_NAMES = {
    "01" => "Schleswig-Holstein",
    "02" => "Hamburg",
    "03" => "Lower Saxony",
    "04" => "Bremen",
    "05" => "North Rhine-Westphalia",
    "06" => "Hesse",
    "07" => "Rhineland-Palatinate",
    "08" => "Baden-Wurttemberg",
    "09" => "Bavaria",
    "10" => "Saarland",
    "11" => "Berlin",
    "12" => "Brandenburg",
    "13" => "Mecklenburg-Vorpommern",
    "14" => "Saxony",
    "15" => "Saxony-Anhalt",
    "16" => "Thuringia"
  }.freeze

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
      case comparable_level.to_s
      when "region"
        build_dach_region_population_records
      when "district"
        build_dach_district_population_records
      else
        []
      end
    rescue StandardError => error
      Rails.logger.error("RegionalAreaIndicatorCatalog failed: #{error.message}")
      []
    end

    def etag(region_key: nil, comparable_level: "region")
      "regional-area-indicators:v2:#{region_key}:#{comparable_level}"
    end

    private

    def build_dach_district_population_records
      records = []
      records.concat(safe_source_records("destatis_district_population") { build_destatis_district_population_records })
      records.concat(safe_source_records("statistik_austria_district_population") { build_austria_district_population_records })
      records.concat(safe_source_records("bfs_district_population") { build_bfs_district_population_records })

      records.sort_by do |record|
        [
          record["country_name"].to_s,
          record["region_name"].to_s,
          -(record.dig("metrics", "population_total") || 0.0),
          record["name"].to_s
        ]
      end
    end

    def build_destatis_district_population_records
      payload = Rails.cache.fetch("regional-area-indicators:destatis:district-population:v1", expires_in: CACHE_TTL) do
        fetch_body(URI(DESTATIS_DISTRICT_POPULATION_URL))
      end
      body = payload[:body].to_s
      return load_snapshot_records(GERMANY_DISTRICT_SNAPSHOT_PATH) if body.blank?

      parse_destatis_district_population_xlsx(body)
    rescue StandardError
      load_snapshot_records(GERMANY_DISTRICT_SNAPSHOT_PATH)
    end

    def build_austria_district_population_records
      population_payload = Rails.cache.fetch("regional-area-indicators:austria:district-population:v1", expires_in: CACHE_TTL) do
        {
          population_csv: fetch_body(URI(AUSTRIA_POPULATION_2024_URL))[:body],
          header_csv: fetch_body(URI(AUSTRIA_DISTRICT_HEADER_URL))[:body]
        }
      end

      population_csv = population_payload[:population_csv].to_s
      header_csv = population_payload[:header_csv].to_s
      return [] if population_csv.blank? || header_csv.blank?

      district_names = {}
      CSV.parse(header_csv, headers: true, col_sep: ";").each do |row|
        raw_code = row["code"].to_s
        next unless raw_code.start_with?("GRBEZ17-")

        district_code = raw_code.delete_prefix("GRBEZ17-")
        district_names[district_code] = row["name"].to_s.sub(/\s*<\d+>\s*\z/, "").strip
      end

      totals = Hash.new(0)
      CSV.parse(population_csv, headers: true, col_sep: ";").each do |row|
        geo = row["C-GRGEMAKT-0"].to_s
        value = row["F-ISIS-1"].to_i
        next if geo.blank? || value.zero?

        district_code = geo[9, 3]
        next if district_code.blank?

        totals[district_code] += value
      end

      totals.map do |district_code, total|
        name = district_names[district_code] || district_code
        state_name = AUSTRIA_STATE_NAMES[district_code[0]]
        {
          "id" => "district-aut-#{district_code}",
          "geography_kind" => "district",
          "geography_key" => "district:aut:#{district_code}",
          "comparable_level" => "district",
          "native_level" => "bezirk",
          "name" => name,
          "region_name" => state_name,
          "country_code" => "AT",
          "country_code_alpha3" => "AUT",
          "country_name" => "Austria",
          "source_geo" => district_code,
          "latest_year" => 2024,
          "source_name" => "Statistik Austria Population at Start of 2024",
          "source_provider" => "Statistik Austria",
          "source_dataset" => "OGD_bevstandjbab2002_BevStand_2024",
          "source_url" => AUSTRIA_POPULATION_2024_URL,
          "metrics" => {
            "population_total" => total.to_f
          }
        }
      end
    end

    def build_bfs_district_population_records
      payload = Rails.cache.fetch("regional-area-indicators:bfs:district-population:v1", expires_in: CACHE_TTL) do
        metadata = fetch_json(URI(SWISS_BFS_DISTRICT_POPULATION_URL))
        geo_variable = metadata.fetch("variables").find { |variable| variable["code"] == "Kanton (-) / Bezirk (>>) / Gemeinde (......)" }
        values = Array(geo_variable["values"])
        labels = Array(geo_variable["valueTexts"])

        canton = nil
        district_entries = values.zip(labels).filter_map do |code, label|
          if label.to_s.start_with?("- ")
            canton = label.to_s.delete_prefix("- ").strip
            next
          end

          next unless label.to_s.start_with?(">> ")

          {
            code: code,
            name: label.to_s.delete_prefix(">> ").strip,
            region_name: canton
          }
        end

        body = {
          query: [
            { code: "Jahr", selection: { filter: "item", values: ["2024"] } },
            { code: "Kanton (-) / Bezirk (>>) / Gemeinde (......)", selection: { filter: "item", values: district_entries.map { |entry| entry[:code] } } },
            { code: "Bevölkerungstyp", selection: { filter: "item", values: ["1"] } },
            { code: "Geburtsort", selection: { filter: "item", values: ["-99999"] } },
            { code: "Staatsangehörigkeit", selection: { filter: "item", values: ["-99999"] } }
          ],
          response: { format: "json-stat2" }
        }

        data = fetch_json(
          URI(SWISS_BFS_DISTRICT_POPULATION_URL),
          method: :post,
          body: JSON.generate(body),
          headers: { "Content-Type" => "application/json" }
        )

        { entries: district_entries, data: data }
      end

      entries = Array(payload[:entries])
      data = payload[:data]
      return [] unless data.is_a?(Hash)

      values = Array(data["value"])
      entries.each_with_index.filter_map do |entry, index|
        value = values[index]
        next if value.nil?

        {
          "id" => "district-che-#{entry[:code].to_s.downcase}",
          "geography_kind" => "district",
          "geography_key" => "district:che:#{entry[:code]}",
          "comparable_level" => "district",
          "native_level" => "district",
          "name" => entry[:name],
          "region_name" => entry[:region_name],
          "country_code" => "CH",
          "country_code_alpha3" => "CHE",
          "country_name" => "Switzerland",
          "source_geo" => entry[:code],
          "latest_year" => 2024,
          "source_name" => "Swiss BFS District Population",
          "source_provider" => "Swiss Federal Statistical Office",
          "source_dataset" => "px-x-0102010000_104",
          "source_url" => SWISS_BFS_DISTRICT_POPULATION_URL,
          "metrics" => {
            "population_total" => value.to_f
          }
        }
      end
    end

    def parse_destatis_district_population_xlsx(binary)
      rows = xlsx_rows(binary, sheet_name: "Kreisfreie Städte u. Landkreise")
      header_row_index = rows.find_index do |row|
        row.values.any? { |value| value.to_s.include?("Amtlicher Regionalschlüssel") }
      end
      return [] unless header_row_index

      header_row = rows[header_row_index]
      code_column = xlsx_column_for_header(header_row, "Amtlicher Regionalschlüssel")
      type_column = xlsx_column_for_header(header_row, "Regionale Bezeichnung")
      name_column = xlsx_column_for_header(header_row, "Kreisfreie Städte und Landkreise")
      population_column = xlsx_column_for_matching_header(header_row, /Bevölkerung/i)
      return [] unless code_column && type_column && name_column && population_column

      rows.drop(header_row_index + 1).filter_map do |row|
        district_code = row[code_column].to_s.strip
        next unless district_code.match?(/\A\d{5}\z/)

        name = row[name_column].to_s.strip
        next if name.blank?

        native_type = row[type_column].to_s.strip
        population_total = parse_localized_number(row[population_column])
        next if population_total.nil?

        {
          "id" => "district-deu-#{district_code}",
          "geography_kind" => "district",
          "geography_key" => "district:deu:#{district_code}",
          "comparable_level" => "district",
          "native_level" => native_type.downcase.include?("kreisfreie") ? "kreisfreie_stadt" : "landkreis",
          "name" => name,
          "region_name" => GERMANY_STATE_NAMES[district_code[0, 2]],
          "country_code" => "DE",
          "country_code_alpha3" => "DEU",
          "country_name" => "Germany",
          "source_geo" => district_code,
          "latest_year" => 2024,
          "source_name" => "Destatis Kreisfreie Stadte und Landkreise",
          "source_provider" => "Destatis",
          "source_dataset" => "04-kreise",
          "source_url" => DESTATIS_DISTRICT_POPULATION_URL,
          "metrics" => {
            "population_total" => population_total.to_f
          }
        }
      end
    end

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

    def fetch_body(uri, method: :get, body: nil, headers: {})
      response = fetch_response(uri, method: method, body: body, headers: headers)

      {
        body: response.body,
        etag: response["ETag"],
        last_modified: response["Last-Modified"],
        content_type: response["Content-Type"]
      }
    rescue SocketError, Socket::ResolutionError
      fetch_body_via_curl(uri, method: method, body: body, headers: headers)
    end

    def fetch_json(uri, method: :get, body: nil, headers: {})
      JSON.parse(fetch_body(uri, method: method, body: body, headers: headers)[:body])
    end

    def fetch_response(uri, method: :get, body: nil, headers: {})
      request_class = method.to_s == "post" ? Net::HTTP::Post : Net::HTTP::Get
      request = request_class.new(uri)
      headers.each { |key, value| request[key] = value }
      request.body = body if body.present?

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 45) do |http|
        http.request(request)
      end

      raise "HTTP #{response.code} from #{uri.host}" unless response.is_a?(Net::HTTPSuccess)

      response
    end

    def xlsx_rows(binary, sheet_name:)
      Zip::File.open_buffer(binary) do |zip|
        shared_strings = xlsx_shared_strings(zip)
        sheet_path = xlsx_sheet_path(zip, sheet_name) || "xl/worksheets/sheet1.xml"
        entry = zip.find_entry(sheet_path)
        return [] unless entry

        document = REXML::Document.new(entry.get_input_stream.read)
        REXML::XPath.match(document, "//xmlns:sheetData/xmlns:row").map do |row|
          cells = {}
          REXML::XPath.each(row, "xmlns:c") do |cell|
            column = cell.attributes["r"].to_s.gsub(/\d+/, "")
            next if column.blank?

            cells[column] = xlsx_cell_value(cell, shared_strings)
          end
          cells
        end
      end
    end

    def xlsx_sheet_path(zip, sheet_name)
      workbook_entry = zip.find_entry("xl/workbook.xml")
      rels_entry = zip.find_entry("xl/_rels/workbook.xml.rels")
      return nil unless workbook_entry && rels_entry

      workbook = REXML::Document.new(workbook_entry.get_input_stream.read)
      rels = REXML::Document.new(rels_entry.get_input_stream.read)
      relationship_targets = REXML::XPath.match(rels, "//xmlns:Relationship").each_with_object({}) do |node, acc|
        acc[node.attributes["Id"]] = node.attributes["Target"]
      end

      sheet = REXML::XPath.match(workbook, "//xmlns:sheets/xmlns:sheet").find do |node|
        node.attributes["name"].to_s == sheet_name
      end
      return nil unless sheet

      target = relationship_targets[sheet.attributes["r:id"]]
      return nil if target.blank?

      target.start_with?("xl/") ? target : File.join("xl", target)
    end

    def xlsx_shared_strings(zip)
      entry = zip.find_entry("xl/sharedStrings.xml")
      return [] unless entry

      document = REXML::Document.new(entry.get_input_stream.read)
      REXML::XPath.match(document, "//xmlns:si").map do |node|
        REXML::XPath.match(node, ".//xmlns:t").map(&:text).join
      end
    end

    def xlsx_cell_value(cell, shared_strings)
      type = cell.attributes["t"].to_s
      if type == "inlineStr"
        return REXML::XPath.match(cell, ".//xmlns:t").map(&:text).join
      end

      raw_value = cell.elements["v"]&.text.to_s
      return shared_strings[raw_value.to_i].to_s if type == "s"

      raw_value
    end

    def xlsx_column_for_header(row, header_name)
      row.find { |_column, value| value.to_s.strip == header_name }&.first
    end

    def xlsx_column_for_matching_header(row, matcher)
      row.find { |_column, value| matcher.match?(value.to_s) }&.first
    end

    def parse_localized_number(value)
      text = value.to_s.strip
      return nil if text.blank?

      normalized = text.delete(".").tr(",", ".")
      Float(normalized)
    rescue ArgumentError
      nil
    end

    def fetch_body_via_curl(uri, method: :get, body: nil, headers: {})
      command = ["curl", "-fsSL", "-X", method.to_s.upcase]
      headers.each do |key, value|
        command.push("-H", "#{key}: #{value}")
      end
      command.push("--data", body.to_s) if body.present?
      command << uri.to_s

      stdout, stderr, status = Open3.capture3(*command)
      raise "curl failed for #{uri.host}: #{stderr.presence || stdout.presence || 'unknown error'}" unless status.success?

      {
        body: stdout,
        etag: nil,
        last_modified: nil,
        content_type: nil
      }
    end

    def load_snapshot_records(path)
      return [] unless File.exist?(path)

      JSON.parse(File.read(path.to_s))
    rescue JSON::ParserError
      []
    end

    def safe_source_records(label)
      Array(yield)
    rescue StandardError => error
      Rails.logger.warn("RegionalAreaIndicatorCatalog source failed: #{label} #{error.class}: #{error.message}")
      []
    end
  end
end
