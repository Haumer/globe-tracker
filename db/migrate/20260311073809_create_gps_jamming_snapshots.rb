class CreateGpsJammingSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :gps_jamming_snapshots do |t|
      t.float :cell_lat
      t.float :cell_lng
      t.integer :total
      t.integer :bad
      t.float :percentage
      t.string :level
      t.datetime :recorded_at

      t.timestamps
    end
    add_index :gps_jamming_snapshots, :recorded_at
    add_index :gps_jamming_snapshots, [:cell_lat, :cell_lng, :recorded_at], name: "idx_jamming_cell_time"
  end
end
