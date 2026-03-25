class RefreshPowerPlantsJob < ApplicationJob
  queue_as :background
  tracks_polling source: "power-plants", poll_type: "power_plants"

  def perform
    return if PowerPlant.count > 0 # Static dataset — only import once
    PowerPlantImportService.import!
  end
end
