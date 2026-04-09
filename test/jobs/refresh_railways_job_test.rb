require "test_helper"

class RefreshRailwaysJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshRailwaysJob.new.queue_name
  end

  test "tracks polling with source natural-earth and poll_type railways" do
    assert_equal "natural-earth", RefreshRailwaysJob.polling_source_resolver
    assert_equal "railways", RefreshRailwaysJob.polling_type_resolver
  end

  test "calls RailwayImportService.import! when layer enabled and no railways exist" do
    called = false
    LayerAvailability.stub(:enabled?, ->(_key) { true }) do
      Railway.stub(:count, 0) do
        RailwayImportService.stub(:import!, -> { called = true; 50 }) do
          RefreshRailwaysJob.perform_now
        end
      end
    end
    assert called
  end

  test "skips when railways layer is disabled" do
    called = false
    LayerAvailability.stub(:enabled?, ->(key) { key.to_s == "railways" ? false : true }) do
      Railway.stub(:count, 0) do
        RailwayImportService.stub(:import!, -> { called = true; 50 }) do
          RefreshRailwaysJob.perform_now
        end
      end
    end
    refute called
  end

  test "skips when railways already exist" do
    called = false
    LayerAvailability.stub(:enabled?, ->(_key) { true }) do
      Railway.stub(:count, 100) do
        RailwayImportService.stub(:import!, -> { called = true; 50 }) do
          RefreshRailwaysJob.perform_now
        end
      end
    end
    refute called
  end
end
