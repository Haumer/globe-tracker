require "test_helper"

class RefreshPowerPlantsJobTest < ActiveSupport::TestCase
  test "is assigned to the background queue" do
    assert_equal "background", RefreshPowerPlantsJob.new.queue_name
  end

  test "tracks polling with source power-plants and poll_type power_plants" do
    assert_equal "power-plants", RefreshPowerPlantsJob.polling_source_resolver
    assert_equal "power_plants", RefreshPowerPlantsJob.polling_type_resolver
  end

  test "calls PowerPlantImportService.import! when no power plants exist" do
    called = false
    CuratedPowerPlantSyncService.stub(:sync!, -> { { updated: 0, inserted: 0, total: 0 } }) do
      PowerPlant.stub(:count, 0) do
        PowerPlantImportService.stub(:import!, -> { called = true; 100 }) do
          RefreshPowerPlantsJob.perform_now
        end
      end
    end
    assert called
  end

  test "skips import when power plants already exist" do
    called = false
    CuratedPowerPlantSyncService.stub(:sync!, -> { { updated: 0, inserted: 0, total: 0 } }) do
      PowerPlant.stub(:count, 500) do
        PowerPlantImportService.stub(:import!, -> { called = true; 100 }) do
          RefreshPowerPlantsJob.perform_now
        end
      end
    end
    refute called, "Expected PowerPlantImportService.import! NOT to be called when data exists"
  end
end
