class NewsEventGeocodeBackfillService
  DEFAULT_WINDOW = 14.days
  DEFAULT_LIMIT = 1_000
  TRUSTED_CONFIDENCE = NewsEvent::TRUSTED_EVENT_GEOCODE_CONFIDENCE

  class << self
    def backfill_recent(window: DEFAULT_WINDOW, limit: DEFAULT_LIMIT)
      new(window: window, limit: limit).backfill_recent
    end
  end

  def initialize(window:, limit:)
    @window = window
    @limit = limit
  end

  def backfill_recent
    ensure_place_gazetteer!
    events_to_repair.sum do |event|
      attrs = geocode_attributes_for(event)
      next 0 if attrs.blank?

      event.update_columns(attrs.merge(updated_at: Time.current))
      1
    end
  end

  private

  def ensure_place_gazetteer!
    PlaceGazetteerSyncService.refresh_if_stale if defined?(Place) && Place.count.zero?
  end

  def events_to_repair
    NewsEvent
      .where("published_at IS NULL OR published_at > ?", @window.ago)
      .where("geocode_basis IS NULL OR geocode_kind = 'unknown' OR geocode_confidence = 0")
      .order(Arel.sql("published_at DESC NULLS LAST"))
      .limit(@limit)
      .to_a
  end

  def geocode_attributes_for(event)
    location = LocationResolver.resolve_event(
      title: event.title,
      url: event.url
    )

    if trusted_event_location?(location)
      return LocationResolver.news_event_attributes(location).merge(
        geocode_metadata: location.metadata.merge("backfilled_from" => "title_or_gazetteer")
      )
    end

    return legacy_unverified_attrs(event) if event.latitude.present? && event.longitude.present?
    return LocationResolver.news_event_attributes(location) if location&.kind == "source_context"

    nil
  end

  def trusted_event_location?(location)
    location&.kind == "event" && location.confidence.to_f >= TRUSTED_CONFIDENCE
  end

  def legacy_unverified_attrs(event)
    {
      latitude: event.latitude,
      longitude: event.longitude,
      geocode_place_name: event.name.presence,
      geocode_country_code: nil,
      geocode_admin_area: nil,
      geocode_basis: "legacy_coordinates",
      geocode_precision: "unknown",
      geocode_kind: "legacy_unverified",
      geocode_confidence: 0.2,
      geocode_metadata: {
        "backfilled_from" => "existing_coordinates",
        "reason" => "No trusted event-location evidence found in title",
      },
    }
  end
end
