namespace :snapshots do
  desc "Purge position snapshots older than HOURS (default 24)"
  task purge: :environment do
    hours = (ENV["HOURS"] || 24).to_i
    count = PositionSnapshot.purge_older_than(hours.hours)
    puts "Purged #{count} snapshots older than #{hours} hours"
  end

  desc "Show snapshot stats"
  task stats: :environment do
    total = PositionSnapshot.count
    flights = PositionSnapshot.flights.count
    ships = PositionSnapshot.ships.count
    oldest = PositionSnapshot.minimum(:recorded_at)
    newest = PositionSnapshot.maximum(:recorded_at)

    puts "Position Snapshots:"
    puts "  Total:   #{total.to_s(:delimited)}"
    puts "  Flights: #{flights.to_s(:delimited)}"
    puts "  Ships:   #{ships.to_s(:delimited)}"
    puts "  Oldest:  #{oldest&.utc}"
    puts "  Newest:  #{newest&.utc}"
    if oldest && newest
      hours = ((newest - oldest) / 3600.0).round(1)
      puts "  Span:    #{hours} hours"
      puts "  Rate:    ~#{(total / [hours, 0.1].max).round(0)}/hour"
    end
  end
end
