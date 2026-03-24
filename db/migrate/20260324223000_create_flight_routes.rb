class CreateFlightRoutes < ActiveRecord::Migration[7.1]
  def change
    create_table :flight_routes do |t|
      t.string :callsign, null: false
      t.string :flight_icao24
      t.string :operator_iata
      t.string :flight_number
      t.jsonb :route, null: false, default: []
      t.jsonb :raw_payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.string :error_code
      t.datetime :fetched_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :flight_routes, :callsign, unique: true
    add_index :flight_routes, :flight_icao24
    add_index :flight_routes, :expires_at
    add_index :flight_routes, :status
  end
end
