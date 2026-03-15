class AddPerformanceIndexes < ActiveRecord::Migration[7.1]
  def change
    # Flights: queried by (source, updated_at) every 10 seconds by GlobalPollerService
    add_index :flights, [:source, :updated_at], name: "idx_flights_source_updated"

    # Ships: filtered by updated_at every request
    add_index :ships, :updated_at, name: "idx_ships_updated_at"

    # News: priority query uses published_at + clustering uses story_cluster_id
    add_index :news_events, [:published_at, :story_cluster_id], name: "idx_news_published_cluster"

    # GPS jamming: DISTINCT ON (cell_lat, cell_lng) ORDER BY recorded_at DESC
    add_index :gps_jamming_snapshots, [:cell_lat, :cell_lng, :recorded_at],
              order: { recorded_at: :desc }, name: "idx_gps_jam_cell_time"
  end
end
