require "test_helper"

class InternetOutageRefreshServiceTest < ActiveSupport::TestCase
  test "IODA_BASE is correct" do
    assert_equal "https://api.ioda.inetintel.cc.gatech.edu/v2", InternetOutageRefreshService::IODA_BASE
  end

  test "outage_level classifies scores correctly" do
    svc = InternetOutageRefreshService.new
    assert_equal "critical", svc.send(:outage_level, 150_000)
    assert_equal "severe", svc.send(:outage_level, 50_000)
    assert_equal "moderate", svc.send(:outage_level, 5_000)
    assert_equal "minor", svc.send(:outage_level, 500)
  end

  test "summary_cache_path returns tmp path" do
    path = InternetOutageRefreshService.summary_cache_path
    assert path.to_s.include?("tmp/internet_outage_summary.json")
  end

  test "cached_summary returns array" do
    result = InternetOutageRefreshService.cached_summary
    assert_instance_of Array, result
  end
end
