class CreateAirports < ActiveRecord::Migration[7.1]
  def change
    create_table :airports do |t|
      t.string :icao_code, null: false
      t.string :iata_code
      t.string :name, null: false
      t.string :airport_type, null: false
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.integer :elevation_ft
      t.string :country_code
      t.string :municipality
      t.boolean :is_military, default: false, null: false
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :airports, :icao_code, unique: true
    add_index :airports, :iata_code
    add_index :airports, [:latitude, :longitude]
    add_index :airports, :airport_type
    add_index :airports, :country_code
    add_index :airports, :is_military
  end
end
