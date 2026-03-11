class CreatePowerPlants < ActiveRecord::Migration[7.1]
  def change
    create_table :power_plants do |t|
      t.string :gppd_idnr, null: false
      t.string :name, null: false
      t.string :country_code
      t.string :country_name
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.float :capacity_mw
      t.string :primary_fuel
      t.string :other_fuel
      t.string :owner
      t.integer :commissioning_year
      t.string :source
      t.string :url
      t.timestamps
    end

    add_index :power_plants, :gppd_idnr, unique: true
    add_index :power_plants, :primary_fuel
    add_index :power_plants, [:latitude, :longitude]
  end
end
