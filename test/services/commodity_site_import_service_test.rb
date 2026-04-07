require "test_helper"
require "tempfile"

class CommoditySiteImportServiceTest < ActiveSupport::TestCase
  test "import rebuilds output from multiple normalized sources" do
    Dir.mktmpdir("commodity-sites-import") do |dir|
      manifest_path = File.join(dir, "manifest.json")
      output_path = File.join(dir, "commodity_sites.json")
      json_path = File.join(dir, "energy.json")
      csv_path = File.join(dir, "specialty.csv")

      File.write(json_path, JSON.pretty_generate([
        {
          id: "lng-test-terminal",
          name: "Test LNG Terminal",
          commodity_key: "lng",
          commodity_name: "Liquefied Natural Gas",
          site_kind: "liquefaction_terminal",
          stage: "processing",
          country_code: "US",
          country_name: "United States",
          location_label: "Gulf Coast",
          lat: 29.1,
          lng: -94.9,
          operator: "Test LNG Co",
          products: ["LNG"],
          summary: "Large LNG test record",
          source_name: "Operator File",
          source_url: "https://example.com/lng",
          source_kind: "official"
        }
      ]))

      File.write(csv_path, <<~CSV)
        id,name,commodity_key,commodity_name,site_kind,stage,country_code,country_name,location_label,location_precision,lat,lng,operator,products,summary,source_name,source_url,source_kind
        helium-test,Test Helium Plant,helium,Helium,helium_processing,processing,QA,Qatar,Ras Laffan,site area,25.9,51.5,Example Operator,helium|gas products,Strategic helium processing site,Example Authority,https://example.com/helium,official
      CSV

      File.write(manifest_path, JSON.pretty_generate({
        sources: [
          { key: "energy", type: "normalized_json", path: "energy.json", priority: 100 },
          { key: "specialty", type: "normalized_csv", path: "specialty.csv", priority: 90 }
        ]
      }))

      result = CommoditySiteImportService.import!(manifest_path:, output_path:)
      data = JSON.parse(File.read(output_path))

      assert_equal 2, result.fetch(:count)
      assert_equal 2, data.size
      assert_equal 1, result.fetch(:commodity_counts).fetch("lng")
      assert_equal 1, result.fetch(:commodity_counts).fetch("helium")
      assert_equal %w[lng-test-terminal helium-test].sort, data.map { |row| row.fetch("id") }.sort

      helium = data.find { |row| row.fetch("id") == "helium-test" }
      assert_equal ["helium", "gas products"], helium.fetch("products")
      assert_equal "specialty", helium.fetch("source_dataset")
    end
  end

  test "higher priority sources win duplicate ids" do
    Dir.mktmpdir("commodity-sites-priority") do |dir|
      manifest_path = File.join(dir, "manifest.json")
      output_path = File.join(dir, "commodity_sites.json")
      low_path = File.join(dir, "low.json")
      high_path = File.join(dir, "high.json")

      base_record = {
        id: "shared-site",
        name: "Shared Site",
        commodity_key: "gas_nat",
        commodity_name: "Natural Gas",
        site_kind: "gas_processing_plant",
        stage: "processing",
        country_code: "AE",
        country_name: "United Arab Emirates",
        location_label: "Abu Dhabi",
        lat: 24.0,
        lng: 54.0,
        operator: "Low Priority Operator",
        summary: "Low priority summary",
        source_name: "Low Source",
        source_url: "https://example.com/low",
        source_kind: "official"
      }

      File.write(low_path, JSON.pretty_generate([base_record]))
      File.write(high_path, JSON.pretty_generate([base_record.merge(
        operator: "High Priority Operator",
        summary: "High priority summary",
        source_name: "High Source",
        source_url: "https://example.com/high"
      )]))

      File.write(manifest_path, JSON.pretty_generate({
        sources: [
          { key: "low", type: "normalized_json", path: "low.json", priority: 10 },
          { key: "high", type: "normalized_json", path: "high.json", priority: 100 }
        ]
      }))

      CommoditySiteImportService.import!(manifest_path:, output_path:)
      data = JSON.parse(File.read(output_path))
      record = data.fetch(0)

      assert_equal 1, data.size
      assert_equal "High Priority Operator", record.fetch("operator")
      assert_equal "high", record.fetch("source_dataset")
    end
  end
end
