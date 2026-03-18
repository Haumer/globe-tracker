require "test_helper"

class EventsChannelTest < ActionCable::Channel::TestCase
  test "subscribes to global_events stream" do
    subscribe
    assert subscription.confirmed?
    assert_has_stream "global_events"
  end

  test "broadcasts earthquake event" do
    quake = OpenStruct.new(
      external_id: "us7000abc",
      title: "M5.2 - 10km S of Tokyo",
      magnitude: 5.2,
      latitude: 35.6,
      longitude: 139.7,
      depth: 12.0,
      event_time: Time.new(2026, 3, 17, 12, 0, 0)
    )

    assert_broadcasts("global_events", 1) do
      EventsChannel.earthquake(quake)
    end

    msg = last_broadcast("global_events")
    assert_equal "earthquake", msg[:type]
    assert_equal "us7000abc", msg[:data][:id]
    assert_equal 5.2, msg[:data][:mag]
    assert_equal 35.6, msg[:data][:lat]
    assert_equal 139.7, msg[:data][:lng]
    assert_equal 12.0, msg[:data][:depth]
    assert msg[:timestamp].present?
  end

  test "broadcasts conflict escalation event" do
    zone = {
      situation_name: "Ukraine War",
      theater: "Eastern Europe",
      pulse_score: 85,
      escalation_trend: "surging",
      lat: 48.3,
      lng: 35.0,
      top_headlines: ["Major offensive launched in Donetsk"],
    }

    assert_broadcasts("global_events", 1) do
      EventsChannel.conflict_escalation(zone)
    end

    msg = last_broadcast("global_events")
    assert_equal "conflict_escalation", msg[:type]
    assert_equal "Ukraine War", msg[:data][:situation]
    assert_equal 85, msg[:data][:pulse_score]
    assert_equal "surging", msg[:data][:trend]
    assert_equal "Major offensive launched in Donetsk", msg[:data][:headline]
    assert msg[:timestamp].present?
  end

  test "broadcasts gps jamming event" do
    snapshot = OpenStruct.new(
      cell_lat: 33.5,
      cell_lng: 44.3,
      percentage: 72,
      level: "severe"
    )

    assert_broadcasts("global_events", 1) do
      EventsChannel.gps_jamming(snapshot)
    end

    msg = last_broadcast("global_events")
    assert_equal "gps_jamming", msg[:type]
    assert_equal 33.5, msg[:data][:lat]
    assert_equal 44.3, msg[:data][:lng]
    assert_equal 72, msg[:data][:pct]
    assert_equal "severe", msg[:data][:level]
  end

  private

  def last_broadcast(stream)
    raw = broadcasts(stream).last
    raw.is_a?(String) ? JSON.parse(raw, symbolize_names: true) : raw.deep_symbolize_keys
  end
end
