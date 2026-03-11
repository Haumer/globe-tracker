class CreateEarthquakes < ActiveRecord::Migration[7.1]
  def change
    create_table :earthquakes do |t|
      t.string :external_id
      t.string :title
      t.float :magnitude
      t.string :magnitude_type
      t.float :latitude
      t.float :longitude
      t.float :depth
      t.datetime :event_time
      t.string :url
      t.boolean :tsunami
      t.string :alert
      t.datetime :fetched_at

      t.timestamps
    end
    add_index :earthquakes, :external_id, unique: true
    add_index :earthquakes, :event_time
    add_index :earthquakes, :fetched_at
  end
end
