namespace :commodity_sites do
  desc "Rebuild commodity site snapshot from manifest-driven source files"
  task rebuild: :environment do
    result = CommoditySiteImportService.import!
    puts "Rebuilt #{result.fetch(:count)} commodity sites from #{result.fetch(:source_count)} sources"
    result.fetch(:commodity_counts).sort.each do |commodity_key, count|
      puts "  #{commodity_key}: #{count}"
    end
  end
end
