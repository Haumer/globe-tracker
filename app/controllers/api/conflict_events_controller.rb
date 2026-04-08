module Api
  class ConflictEventsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      # UCDP data is historical (annual releases) — default to all events, not just "recent"
      range = parse_time_range
      scope = range ? ConflictEvent.in_range(*range) : ConflictEvent.all
      bounds = parse_bounds
      scope = scope.within_bounds(bounds) if bounds.present?

      events = scope.order(date_start: :desc).limit(2000)
      if events.empty?
        return render json: [] if range
        return render json: fallback_conflict_pulse_events(bounds)
      end

      render json: events.map { |e|
        {
          id: e.id,
          lat: e.latitude,
          lng: e.longitude,
          conflict: e.conflict_name,
          side_a: e.side_a,
          side_b: e.side_b,
          country: e.country,
          region: e.region,
          location: e.where_description,
          date_start: e.date_start&.iso8601,
          date_end: e.date_end&.iso8601,
          deaths: e.best_estimate,
          deaths_civilians: e.deaths_civilians,
          type: e.type_of_violence,
          type_label: e.violence_label,
          headline: e.source_headline,
        }
      }
    end

    private

    def fallback_conflict_pulse_events(bounds)
      snapshot = ConflictPulseSnapshotService.fetch_or_enqueue
      payload = snapshot&.payload.presence || ConflictPulseSnapshotService.empty_payload
      zones = payload["zones"] || payload[:zones] || []

      if bounds.present?
        zones = zones.select do |zone|
          lat = zone["lat"] || zone[:lat]
          lng = zone["lng"] || zone[:lng]
          lat && lng &&
            lat >= bounds[:lamin] && lat <= bounds[:lamax] &&
            lng >= bounds[:lomin] && lng <= bounds[:lomax]
        end
      end

      zones.first(200).each_with_index.map do |zone, idx|
        lat = zone["lat"] || zone[:lat]
        lng = zone["lng"] || zone[:lng]
        title = zone["theater"] || zone[:theater] || zone["situation_name"] || zone[:situation_name] || "Conflict pulse"
        location = zone["situation_name"] || zone[:situation_name] || title
        headline = Array(zone["top_headlines"] || zone[:top_headlines]).first
        detected_at = zone["detected_at"] || zone[:detected_at]
        score = zone["pulse_score"] || zone[:pulse_score] || 0

        {
          id: "pulse-#{zone["cell_key"] || zone[:cell_key] || idx}",
          lat: lat,
          lng: lng,
          conflict: title,
          side_a: nil,
          side_b: nil,
          country: title,
          region: zone["theater"] || zone[:theater],
          location: location,
          date_start: detected_at,
          date_end: nil,
          deaths: score,
          deaths_civilians: nil,
          type: 2,
          type_label: "Current conflict pulse",
          headline: headline,
        }
      end
    end
  end
end
