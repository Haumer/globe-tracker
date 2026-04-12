require "test_helper"

class RefreshNewsGeocodeBackfillJobTest < ActiveSupport::TestCase
  test "tracks polling metadata" do
    assert_equal "background", RefreshNewsGeocodeBackfillJob.new.queue_name
    assert_equal "news-geocode-backfill", RefreshNewsGeocodeBackfillJob.polling_source_resolver
    assert_equal "repair", RefreshNewsGeocodeBackfillJob.polling_type_resolver
  end

  test "performs backfill" do
    event = NewsEvent.create!(
      url: "https://example.com/london-job",
      title: "London police arrest protesters",
      latitude: 43.0,
      longitude: -81.0,
      category: "unrest",
      published_at: 1.hour.ago,
      fetched_at: Time.current
    )

    RefreshNewsGeocodeBackfillJob.perform_now

    assert_equal "event", event.reload.geocode_kind
  end
end
