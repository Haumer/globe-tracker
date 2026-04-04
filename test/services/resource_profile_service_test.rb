require "test_helper"

class ResourceProfileServiceTest < ActiveSupport::TestCase
  test "builds pipeline resource profiles from pipeline records" do
    Pipeline.create!(
      pipeline_id: "pipe-001",
      name: "Nord Stream 1",
      pipeline_type: "gas",
      status: "operational",
      length_km: 1224,
      country: "Germany"
    )

    profile = ResourceProfileService.call(
      primary_object: InvestigationCaseObject.new(
        object_kind: "pipeline",
        object_identifier: "pipe-001",
        title: "Nord Stream 1",
        object_type: "gas"
      )
    )

    assert profile.present?
    assert_equal "Resource Context", profile[:title]
    assert_equal "Resource carrier", profile[:subtitle]
    assert_equal "Gas", profile[:metrics].first[:value]
    assert_equal "1,224 km", profile[:metrics].third[:value]
  end

  test "builds power plant resource profiles from plant records" do
    plant = PowerPlant.create!(
      gppd_idnr: "gppd-001",
      name: "Test Gas Plant",
      country_code: "QA",
      country_name: "Qatar",
      latitude: 25.3,
      longitude: 51.5,
      capacity_mw: 1450,
      primary_fuel: "Gas"
    )

    profile = ResourceProfileService.call(
      primary_object: InvestigationCaseObject.new(
        object_kind: "power_plant",
        object_identifier: plant.id.to_s,
        title: plant.name,
        object_type: "Gas"
      )
    )

    assert profile.present?
    assert_equal "Resource transformation", profile[:subtitle]
    assert_equal "Gas", profile[:metrics].first[:value]
    assert_equal "Electricity", profile[:metrics].second[:value]
    assert_equal "1,450 MW", profile[:metrics].third[:value]
  end
end
