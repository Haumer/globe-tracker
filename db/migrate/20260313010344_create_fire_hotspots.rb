class CreateFireHotspots < ActiveRecord::Migration[7.1]
  def change
    create_table :fire_hotspots do |t|
      t.string :external_id, null: false
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.float :brightness
      t.string :confidence
      t.string :satellite
      t.string :instrument
      t.float :frp
      t.float :bright_t31
      t.string :daynight
      t.datetime :acq_datetime
      t.datetime :fetched_at
      t.timestamps
    end

    add_index :fire_hotspots, :external_id, unique: true
    add_index :fire_hotspots, [:latitude, :longitude]
    add_index :fire_hotspots, :acq_datetime
  end
end
