class AddNacpToFlights < ActiveRecord::Migration[7.1]
  def change
    add_column :flights, :nac_p, :integer
  end
end
