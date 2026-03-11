class CreatePositionSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :position_snapshots do |t|
      t.string :entity_type, null: false  # "flight" or "ship"
      t.string :entity_id, null: false    # icao24 for flights, mmsi for ships
      t.string :callsign
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.float :altitude
      t.float :heading
      t.float :speed
      t.float :vertical_rate
      t.boolean :on_ground
      t.string :extra                     # JSON string for source, registration, etc.
      t.datetime :recorded_at, null: false
    end

    add_index :position_snapshots, [:entity_type, :recorded_at]
    add_index :position_snapshots, [:entity_type, :entity_id, :recorded_at], name: "idx_snapshots_entity_time"
    add_index :position_snapshots, :recorded_at
  end
end
