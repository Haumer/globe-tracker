require "test_helper"

class Api::StrikesControllerTest < ActionDispatch::IntegrationTest
  setup do
    FireHotspot.create!(
      external_id: "fire-low-text-confidence",
      latitude: 35.7,
      longitude: 51.4,
      brightness: 355.0,
      confidence: "l",
      satellite: "Aqua",
      instrument: "MODIS",
      frp: 25.0,
      daynight: "N",
      acq_datetime: 2.hours.ago
    )

    FireHotspot.create!(
      external_id: "fire-numeric-confidence",
      latitude: 35.8,
      longitude: 51.5,
      brightness: 360.0,
      confidence: "60",
      satellite: "Aqua",
      instrument: "MODIS",
      frp: 30.0,
      daynight: "N",
      acq_datetime: 1.hour.ago
    )
  end

  test "GET /api/strikes handles mixed confidence formats" do
    get "/api/strikes"

    assert_response :success

    body = JSON.parse(response.body)
    firms_ids = body.fetch("firms").map { |entry| entry[0] }

    assert_includes firms_ids, "fire-numeric-confidence"
    assert_not_includes firms_ids, "fire-low-text-confidence"
    assert_equal [], body.fetch("geoconfirmed")
  end
end
