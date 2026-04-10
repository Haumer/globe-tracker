namespace :power_plants do
  desc "Import power plants from WRI Global Power Plant Database"
  task import: :environment do
    count = PowerPlantImportService.import!
    puts "Imported #{count} power plants"
  end

  desc "Sync curated power-plant overrides into the shared power_plant table"
  task sync_curated: :environment do
    result = CuratedPowerPlantSyncService.sync!
    puts "Synced curated power plants: #{result.fetch(:updated)} updated, #{result.fetch(:inserted)} inserted"
  end
end
