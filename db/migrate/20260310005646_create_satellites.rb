class CreateSatellites < ActiveRecord::Migration[7.1]
  def change
    create_table :satellites do |t|
      t.string :name
      t.string :tle_line1
      t.string :tle_line2
      t.string :category
      t.integer :norad_id

      t.timestamps
    end

    add_index :satellites, :norad_id, unique: true
  end
end
