class AddVerticalRateAndTimePositionToFlights < ActiveRecord::Migration[7.1]
  def change
    add_column :flights, :vertical_rate, :float
    add_column :flights, :time_position, :integer
  end
end
