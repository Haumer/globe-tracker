require Rails.root.join("app/services/regional_district_boundary_importers/germany_vg250")
require Rails.root.join("app/services/regional_district_boundary_importers/austria_statistik")
require Rails.root.join("app/services/regional_district_boundary_importers/switzerland_geo_admin")

namespace :regional_district_boundaries do
  desc "Refresh official district-boundary snapshots for DACH"
  task refresh: :environment do
    RegionalDistrictBoundaryImporters::GermanyVg250.write!
    RegionalDistrictBoundaryImporters::AustriaStatistik.write!
    RegionalDistrictBoundaryImporters::SwitzerlandGeoAdmin.write!
  end
end
