namespace :conflicts do
  desc "Import conflict events from UCDP (requires UCDP_API_TOKEN)"
  task import: :environment do
    token = ConflictEventService.api_token
    if token.blank?
      puts "Set UCDP_API_TOKEN env var or add ucdp.api_token to credentials."
      puts "Register free at: https://ucdpapi.pcr.uu.se"
      exit 1
    end

    year = ENV.fetch("YEAR", Date.current.year - 1).to_i
    puts "Importing UCDP conflict events for #{year}..."
    count = ConflictEventService.fetch_recent(year: year)
    puts "Imported #{count} conflict events"
  end
end
