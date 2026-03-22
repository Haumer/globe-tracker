class RefreshPowerPlantsJob < ApplicationJob
  queue_as :default

  def perform
    return if PowerPlant.count > 0 # Static dataset — only import once
    PowerPlantImportService.import!
  end
end
