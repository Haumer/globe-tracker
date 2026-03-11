namespace :power_plants do
  desc "Import power plants from WRI Global Power Plant Database"
  task import: :environment do
    count = PowerPlantImportService.import!
    puts "Imported #{count} power plants"
  end
end
