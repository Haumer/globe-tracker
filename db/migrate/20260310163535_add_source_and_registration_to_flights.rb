class AddSourceAndRegistrationToFlights < ActiveRecord::Migration[7.1]
  def change
    add_column :flights, :source, :string
    add_column :flights, :registration, :string
    add_column :flights, :aircraft_type, :string
  end
end
