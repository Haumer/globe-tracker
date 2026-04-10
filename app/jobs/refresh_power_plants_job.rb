class RefreshPowerPlantsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "power-plants", poll_type: "power_plants"

  def perform
    PowerPlantImportService.import! if PowerPlant.count == 0
    CuratedPowerPlantSyncService.sync!
  end
end
