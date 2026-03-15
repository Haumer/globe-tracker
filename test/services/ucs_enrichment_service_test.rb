require "test_helper"

class UcsEnrichmentServiceTest < ActiveSupport::TestCase
  test "UCS_URL is defined" do
    assert_equal "https://www.ucs.org/media/11493", UcsEnrichmentService::UCS_URL
  end

  test "enrich is a class method" do
    assert UcsEnrichmentService.respond_to?(:enrich)
  end

  test "import returns 0 when file does not exist" do
    result = UcsEnrichmentService.send(:import, "/tmp/nonexistent_ucs_file_#{SecureRandom.hex}.txt")
    assert_equal 0, result
  end
end
