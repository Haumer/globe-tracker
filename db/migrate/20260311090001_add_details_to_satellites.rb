class AddDetailsToSatellites < ActiveRecord::Migration[7.1]
  def change
    add_column :satellites, :operator, :string
    add_column :satellites, :mission_type, :string
  end
end
