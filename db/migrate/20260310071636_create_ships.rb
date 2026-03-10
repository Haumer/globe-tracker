class CreateShips < ActiveRecord::Migration[7.1]
  def change
    create_table :ships do |t|
      t.string :mmsi
      t.string :name
      t.integer :ship_type
      t.float :latitude
      t.float :longitude
      t.float :speed
      t.float :heading
      t.float :course
      t.string :destination
      t.string :flag

      t.timestamps
    end

    add_index :ships, :mmsi, unique: true
  end
end
