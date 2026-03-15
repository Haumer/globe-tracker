require "test_helper"

class PipelineRefreshServiceTest < ActiveSupport::TestCase
  test "MIN_LENGTH_KM is 50" do
    assert_equal 50, PipelineRefreshService::MIN_LENGTH_KM
  end

  test "color_for_type returns correct colors" do
    svc = PipelineRefreshService.new
    assert_equal "#ff6d00", svc.send(:color_for_type, "oil")
    assert_equal "#76ff03", svc.send(:color_for_type, "gas")
    assert_equal "#00b0ff", svc.send(:color_for_type, "hydrogen")
    assert_equal "#ffab00", svc.send(:color_for_type, "products")
    assert_equal "#ff6d00", svc.send(:color_for_type, "unknown")
  end

  test "map_status maps various states to standard statuses" do
    svc = PipelineRefreshService.new
    assert_equal "operational", svc.send(:map_status, "Operating")
    assert_equal "operational", svc.send(:map_status, "Active")
    assert_equal "under_construction", svc.send(:map_status, "Under Construction")
    assert_equal "proposed", svc.send(:map_status, "Proposed")
    assert_equal "inactive", svc.send(:map_status, "Shelved")
    assert_equal "inactive", svc.send(:map_status, "Cancelled")
    assert_equal "operational", svc.send(:map_status, nil)
    assert_equal "operational", svc.send(:map_status, "")
  end

  test "flatten_multilinestring converts coords to lat-lng pairs" do
    svc = PipelineRefreshService.new
    coords = [[[10.0, 50.0], [11.0, 51.0]], [[12.0, 52.0]]]
    result = svc.send(:flatten_multilinestring, coords)
    assert_equal [[50.0, 10.0], [51.0, 11.0], [52.0, 12.0]], result
  end

  test "count_points sums segment lengths" do
    svc = PipelineRefreshService.new
    coords = [[[1, 2], [3, 4]], [[5, 6]]]
    assert_equal 3, svc.send(:count_points, coords)
  end
end
