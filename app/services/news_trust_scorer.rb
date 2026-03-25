class NewsTrustScorer
  SOURCE_RELIABILITY = {
    "wire" => 0.92,
    "publisher" => 0.74,
    "aggregator" => 0.48,
    "platform" => 0.35,
  }.freeze

  GEO_CONFIDENCE = {
    "point" => 0.82,
    "named_area" => 0.58,
    "country" => 0.42,
    "unknown" => 0.0,
  }.freeze

  class << self
    def claim_attributes(source_kind:, publisher_name:, publisher_domain:, origin_source_name:, origin_source_kind:, origin_source_domain:, location_name:, latitude:, longitude:, event_id:, event_title:, canonical_url:, extraction:, claim_text:, published_at:)
      event_confidence = extraction[:event_confidence].to_f
      actor_confidence = extraction[:actor_confidence].to_f
      extraction_confidence = extraction[:extraction_confidence].to_f
      source_reliability = source_reliability_for(source_kind, origin_source_kind)
      geo_precision = geo_precision_for(location_name: location_name, latitude: latitude, longitude: longitude)
      geo_confidence = GEO_CONFIDENCE.fetch(geo_precision, 0.0)

      {
        event_confidence: event_confidence.round(2),
        actor_confidence: actor_confidence.round(2),
        extraction_confidence: extraction_confidence.round(2),
        source_reliability: source_reliability.round(2),
        geo_precision: geo_precision,
        geo_confidence: geo_confidence.round(2),
        verification_status: verification_status_for(source_kind),
        confidence: overall_confidence(
          event_confidence: event_confidence,
          actor_confidence: actor_confidence,
          extraction_confidence: extraction_confidence,
          source_reliability: source_reliability,
          geo_confidence: geo_confidence
        ),
        provenance: {
          "publisher_name" => publisher_name,
          "publisher_domain" => publisher_domain,
          "source_kind" => source_kind,
          "origin_source_name" => origin_source_name,
          "origin_source_kind" => origin_source_kind,
          "origin_source_domain" => origin_source_domain,
          "canonical_url" => canonical_url,
          "event_id" => event_id,
          "event_title" => event_title,
          "event_location_name" => location_name,
          "event_coordinates" => latitude && longitude ? { "lat" => latitude, "lng" => longitude } : nil,
          "claim_text_excerpt" => claim_text.to_s.scrub("")[0...280],
          "published_at" => published_at&.iso8601,
          "matched_on" => extraction.dig(:metadata, "matched_on"),
          "matched_rule" => extraction.dig(:metadata, "matched_rule"),
          "summary_used" => extraction.dig(:metadata, "summary_used") == true,
        }.compact,
      }
    end

    def source_reliability_for(source_kind, origin_source_kind = nil)
      base = SOURCE_RELIABILITY.fetch(source_kind.to_s, 0.4)
      return base unless origin_source_kind.present?

      origin = SOURCE_RELIABILITY.fetch(origin_source_kind.to_s, base)
      ((base * 0.65) + (origin * 0.35)).round(2)
    end

    def verification_status_for(source_kind)
      source_kind.to_s == "aggregator" || source_kind.to_s == "platform" ? "unverified" : "single_source"
    end

    def geo_precision_for(location_name:, latitude:, longitude:)
      return "point" if latitude.present? && longitude.present?

      normalized_location = location_name.to_s.strip
      return "unknown" if normalized_location.blank?
      return "country" if country_name?(normalized_location)

      "named_area"
    end

    def overall_confidence(event_confidence:, actor_confidence:, extraction_confidence:, source_reliability:, geo_confidence:)
      score = (event_confidence * 0.3) +
        (actor_confidence * 0.2) +
        (extraction_confidence * 0.2) +
        (source_reliability * 0.2) +
        (geo_confidence * 0.1)

      [ score.round(2), 0.99 ].min
    end

    private

    def country_name?(value)
      normalized = value.to_s.downcase
      NewsGeocodable::COUNTRY_NAME_MAP.key?(normalized)
    end
  end
end
