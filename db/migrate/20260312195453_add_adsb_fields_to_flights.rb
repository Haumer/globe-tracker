class AddAdsbFieldsToFlights < ActiveRecord::Migration[7.1]
  def change
    add_column :flights, :squawk, :string
    add_column :flights, :emergency, :string
    add_column :flights, :category, :string
    add_column :flights, :indicated_airspeed, :float
    add_column :flights, :true_airspeed, :float
    add_column :flights, :mach, :float
    add_column :flights, :mag_heading, :float
    add_column :flights, :true_heading, :float
    add_column :flights, :roll, :float
    add_column :flights, :track_rate, :float
    add_column :flights, :nav_qnh, :float
    add_column :flights, :nav_altitude_mcp, :integer
    add_column :flights, :nav_altitude_fms, :integer
    add_column :flights, :wind_direction, :integer
    add_column :flights, :wind_speed, :integer
    add_column :flights, :outside_air_temp, :integer
    add_column :flights, :signal_strength, :float
    add_column :flights, :message_type, :string
  end
end
