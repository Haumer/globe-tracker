require "test_helper"

class FirmsRefreshServiceTest < ActiveSupport::TestCase
  setup do
    @service = FirmsRefreshService.new
  end

  test "normalize_satellite identifies Terra" do
    assert_equal "Terra", @service.send(:normalize_satellite, "Terra")
    assert_equal "Terra", @service.send(:normalize_satellite, " TERRA ")
  end

  test "normalize_satellite identifies Aqua" do
    assert_equal "Aqua", @service.send(:normalize_satellite, "Aqua")
  end

  test "normalize_satellite returns stripped name for unknown" do
    assert_equal "NOAA-20", @service.send(:normalize_satellite, " NOAA-20 ")
  end

  test "normalize_satellite handles nil" do
    assert_nil @service.send(:normalize_satellite, nil)
  end

  test "parse_acq_time parses date and time" do
    result = @service.send(:parse_acq_time, "2025-06-15", "1430")
    assert_kind_of Time, result
    assert_equal 14, result.hour
    assert_equal 30, result.min
  end

  test "parse_acq_time pads short time strings" do
    result = @service.send(:parse_acq_time, "2025-06-15", "30")
    assert_kind_of Time, result
    assert_equal 0, result.hour
    assert_equal 30, result.min
  end

  test "parse_acq_time returns nil for blank date" do
    assert_nil @service.send(:parse_acq_time, nil, "1430")
    assert_nil @service.send(:parse_acq_time, "", "1430")
  end

  test "SOURCES contains known FIRMS sources" do
    assert_kind_of Hash, FirmsRefreshService::SOURCES
    assert FirmsRefreshService::SOURCES.key?("VIIRS_SNPP_NRT")
    assert FirmsRefreshService::SOURCES.key?("MODIS_NRT")
  end

  test "after_upsert keeps seven days of hotspots and clears stale timeline rows" do
    stale = FireHotspot.create!(
      external_id: "stale-fire",
      latitude: 35.7,
      longitude: 51.4,
      acq_datetime: 8.days.ago,
      fetched_at: Time.current
    )
    stale_timeline = TimelineEvent.create!(
      event_type: "fire",
      eventable: stale,
      latitude: stale.latitude,
      longitude: stale.longitude,
      recorded_at: stale.acq_datetime
    )

    recent = FireHotspot.create!(
      external_id: "recent-fire",
      latitude: 35.8,
      longitude: 51.5,
      acq_datetime: 6.days.ago,
      fetched_at: Time.current
    )

    @service.send(:after_upsert, [])

    assert_not FireHotspot.exists?(stale.id)
    assert_not TimelineEvent.exists?(stale_timeline.id)
    assert FireHotspot.exists?(recent.id)
  end
end
