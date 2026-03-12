class AddUcsEnrichmentToSatellites < ActiveRecord::Migration[7.1]
  def change
    add_column :satellites, :country_owner, :string
    add_column :satellites, :users, :string
    add_column :satellites, :purpose, :string
    add_column :satellites, :detailed_purpose, :string
    add_column :satellites, :orbit_class, :string
    add_column :satellites, :launch_date, :string
    add_column :satellites, :launch_site, :string
    add_column :satellites, :launch_vehicle, :string
    add_column :satellites, :contractor, :string
    add_column :satellites, :expected_lifetime, :string
  end
end
