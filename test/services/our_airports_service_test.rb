require "test_helper"

class OurAirportsServiceTest < ActiveSupport::TestCase
  test "CSV_URL is defined" do
    assert OurAirportsService::CSV_URL.include?("ourairports")
  end

  test "INCLUDED_TYPES contains large and medium airports" do
    assert_includes OurAirportsService::INCLUDED_TYPES, "large_airport"
    assert_includes OurAirportsService::INCLUDED_TYPES, "medium_airport"
    assert_not_includes OurAirportsService::INCLUDED_TYPES, "small_airport"
  end

  test "military_airport? detects military keywords" do
    assert OurAirportsService.send(:military_airport?, "Ramstein Air Base", "large_airport")
    assert OurAirportsService.send(:military_airport?, "RAF Lakenheath", "medium_airport")
    assert OurAirportsService.send(:military_airport?, "Naval Air Station", "small_airport")
    assert OurAirportsService.send(:military_airport?, "Any name", "military")
  end

  test "military_airport? returns false for civilian airports" do
    assert_not OurAirportsService.send(:military_airport?, "Vienna International Airport", "large_airport")
    assert_not OurAirportsService.send(:military_airport?, "Heathrow", "large_airport")
  end

  test "stale? returns true when no airports exist" do
    assert OurAirportsService.stale?
  end
end
