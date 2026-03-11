class CreateSatelliteTleSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :satellite_tle_snapshots do |t|
      t.integer :norad_id, null: false
      t.string :name
      t.string :tle_line1, null: false
      t.string :tle_line2, null: false
      t.string :category
      t.datetime :recorded_at, null: false

      t.index [:norad_id, :recorded_at], order: { recorded_at: :desc },
              name: "idx_tle_snapshots_lookup"
      t.index :recorded_at, name: "idx_tle_snapshots_recorded_at"
    end
  end
end
