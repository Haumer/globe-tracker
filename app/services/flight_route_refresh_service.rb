class FlightRouteRefreshService
  SUCCESS_TTL = 30.minutes
  FAILURE_TTL = 10.minutes
  ENQUEUE_TTL = 5.minutes

  class << self
    def enqueue_if_needed(callsign:, flight_icao24: nil)
      normalized_callsign = normalize_callsign(callsign)
      return false if normalized_callsign.blank?

      route = FlightRoute.find_or_initialize_by(callsign: normalized_callsign)
      return false if route.persisted? && route.fresh?

      now = Time.current
      route.assign_attributes(
        flight_icao24: flight_icao24.presence || route.flight_icao24,
        status: "pending",
        error_code: nil,
        expires_at: now + ENQUEUE_TTL,
      )
      route.fetched_at ||= now
      route.save!

      BackgroundRefreshScheduler.enqueue_once(
        RefreshFlightRouteJob,
        normalized_callsign,
        flight_icao24,
        key: "flight-route:#{normalized_callsign}",
        ttl: ENQUEUE_TTL,
      )
    end

    def refresh(callsign:, flight_icao24: nil, force: false)
      normalized_callsign = normalize_callsign(callsign)
      return nil if normalized_callsign.blank?

      route = FlightRoute.find_or_initialize_by(callsign: normalized_callsign)
      return route if route.persisted? && route.fresh? && !force

      result = OpenskyService.fetch_route(normalized_callsign)
      now = Time.current

      route.assign_attributes(
        flight_icao24: flight_icao24.presence || route.flight_icao24,
        fetched_at: now,
      )

      if result[:error].present?
        route.assign_attributes(
          status: "failed",
          error_code: result[:error].to_s.first(255),
          expires_at: now + FAILURE_TTL,
        )
      else
        route.assign_attributes(
          operator_iata: result[:operator_iata],
          flight_number: result[:flight_number],
          route: Array(result[:route]),
          raw_payload: result[:raw_payload].presence || result.except(:error),
          status: "fetched",
          error_code: nil,
          expires_at: now + SUCCESS_TTL,
        )
      end

      route.save!
      route
    end

    private

    def normalize_callsign(value)
      value.to_s.strip.upcase.presence
    end
  end
end
