class CreateGeoconfirmedEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :geoconfirmed_events do |t|
      t.string :external_id, null: false
      t.string :map_region, null: false
      t.string :folder_path
      t.string :title
      t.text :description
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.datetime :event_time
      t.string :icon_key
      t.text :source_urls, array: true, default: []
      t.text :geolocation_urls, array: true, default: []
      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :geoconfirmed_events, :external_id, unique: true
    add_index :geoconfirmed_events, [:latitude, :longitude]
    add_index :geoconfirmed_events, :map_region
    add_index :geoconfirmed_events, :event_time
    add_index :geoconfirmed_events, :fetched_at
  end
end
