require "test_helper"

class PowerPlantImportServiceTest < ActiveSupport::TestCase
  test "CSV_URL points to WRI global power plant database" do
    assert PowerPlantImportService::CSV_URL.include?("global-power-plant-database")
    assert PowerPlantImportService::CSV_URL.end_with?(".csv")
  end

  test "import! is a class method" do
    assert PowerPlantImportService.respond_to?(:import!)
  end
end
