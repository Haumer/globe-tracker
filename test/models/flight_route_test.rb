require "test_helper"

class FlightRouteTest < ActiveSupport::TestCase
  setup do
    @route = FlightRoute.create!(
      callsign: "DLH1A",
      status: "fetched",
      route: [{ icao: "EDDF" }, { icao: "KJFK" }],
      expires_at: 1.hour.from_now
    )
  end

  test "valid creation" do
    assert @route.persisted?
  end

  test "callsign is required" do
    r = FlightRoute.new(status: "pending")
    assert_not r.valid?
    assert_includes r.errors[:callsign], "can't be blank"
  end

  test "callsign is unique" do
    dup = FlightRoute.new(callsign: "DLH1A", status: "pending")
    assert_not dup.valid?
    assert dup.errors[:callsign].any?
  end

  test "status must be valid" do
    r = FlightRoute.new(callsign: "TEST1", status: "invalid")
    assert_not r.valid?
    assert r.errors[:status].any?
  end

  test "normalize_callsign strips and upcases" do
    r = FlightRoute.create!(callsign: "  abc123  ", status: "pending")
    assert_equal "ABC123", r.callsign
  end

  test "fresh? returns true when expires_at is future" do
    assert @route.fresh?
  end

  test "fresh? returns false when expired" do
    @route.update!(expires_at: 1.hour.ago)
    assert_not @route.fresh?
  end

  test "fresh? returns false when expires_at is nil" do
    @route.update!(expires_at: nil)
    assert_not @route.fresh?
  end

  test "available? returns true for fetched with route" do
    assert @route.available?
  end

  test "available? returns false for pending" do
    @route.status = "pending"
    assert_not @route.available?
  end

  test "pending? returns true when status is pending" do
    @route.status = "pending"
    assert @route.pending?
  end

  test "payload returns hash with route info" do
    p = @route.payload
    assert_equal "DLH1A", p[:callsign]
    assert_equal 2, p[:route].size
  end

  test "fresh scope returns non-expired routes" do
    expired = FlightRoute.create!(callsign: "OLD1", status: "fetched", expires_at: 1.hour.ago)
    results = FlightRoute.fresh
    assert_includes results, @route
    assert_not_includes results, expired
  end

  test "normalize_callsign class method" do
    assert_equal "ABC", FlightRoute.normalize_callsign("  abc  ")
    assert_nil FlightRoute.normalize_callsign("  ")
  end
end
