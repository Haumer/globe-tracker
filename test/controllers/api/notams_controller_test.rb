require "test_helper"

class Api::NotamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @notam = Notam.create!(
      external_id: "NOTAM-CTRL-001",
      source: "FAA",
      latitude: 48.0,
      longitude: 11.0,
      radius_nm: 5,
      radius_m: 9260,
      reason: "Military",
      text: "Military exercise area",
      country: "DE",
      effective_start: 1.hour.ago,
      effective_end: 2.hours.from_now,
      fetched_at: Time.current,
    )
  end

  test "GET /api/notams returns JSON array" do
    get "/api/notams"
    assert_response :success

    data = JSON.parse(response.body)
    assert_kind_of Array, data
  end

  test "response includes static no-fly zones" do
    get "/api/notams"
    data = JSON.parse(response.body)
    ids = data.map { |z| z["id"] }

    assert ids.any? { |id| id&.start_with?("NFZ-") }
  end

  test "response includes dynamic notams from DB" do
    get "/api/notams", params: { lamin: 47.0, lamax: 49.0, lomin: 10.0, lomax: 12.0 }
    data = JSON.parse(response.body)
    ids = data.map { |z| z["id"] }

    assert_includes ids, "NOTAM-CTRL-001"
  end

  test "bounds filtering excludes out-of-range zones" do
    get "/api/notams", params: { lamin: -10.0, lamax: -5.0, lomin: -10.0, lomax: -5.0 }
    data = JSON.parse(response.body)
    ids = data.map { |z| z["id"] }

    assert_not_includes ids, "NOTAM-CTRL-001"
  end
end
