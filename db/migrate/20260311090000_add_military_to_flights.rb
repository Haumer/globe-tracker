class AddMilitaryToFlights < ActiveRecord::Migration[7.1]
  def change
    add_column :flights, :military, :boolean, default: false, null: false
  end
end
