class CreateFlights < ActiveRecord::Migration[7.1]
  def change
    create_table :flights do |t|
      t.string :callsign
      t.float :latitude
      t.float :longitude
      t.float :altitude
      t.float :heading
      t.float :speed
      t.string :origin_country
      t.boolean :on_ground
      t.string :icao24

      t.timestamps
    end

    add_index :flights, :icao24, unique: true
  end
end
