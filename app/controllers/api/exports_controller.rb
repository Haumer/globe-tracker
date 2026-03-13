module Api
  class ExportsController < ApplicationController
    before_action :authenticate_user!

    # GET /api/exports/geojson?layers=flights,earthquakes&from=ISO&to=ISO
    def geojson
      features = []
      layers = (params[:layers] || "flights").split(",").map(&:strip)
      from = parse_time(params[:from]) || 1.hour.ago
      to = parse_time(params[:to]) || Time.current
      from = [from, to - 7.days].max

      bounds = parse_bounds

      layers.each do |layer|
        case layer
        when "flights"
          scope = PositionSnapshot.flights.in_range(from, to)
          scope = scope.within_bounds(bounds) if bounds.size == 4
          scope.select(:entity_id).distinct.limit(500).pluck(:entity_id).each do |eid|
            snaps = PositionSnapshot.flights.where(entity_id: eid).in_range(from, to).order(:recorded_at)
            coords = snaps.map { |s| [s.longitude, s.latitude, s.altitude || 0] }
            next if coords.size < 2
            props = { type: "flight", callsign: snaps.first.callsign, entity_id: eid }
            features << { type: "Feature", geometry: { type: "LineString", coordinates: coords }, properties: props }
          end
        when "ships"
          scope = PositionSnapshot.ships.in_range(from, to)
          scope = scope.within_bounds(bounds) if bounds.size == 4
          scope.select(:entity_id).distinct.limit(500).pluck(:entity_id).each do |eid|
            snaps = PositionSnapshot.ships.where(entity_id: eid).in_range(from, to).order(:recorded_at)
            coords = snaps.map { |s| [s.longitude, s.latitude] }
            next if coords.size < 2
            features << { type: "Feature", geometry: { type: "LineString", coordinates: coords }, properties: { type: "ship", entity_id: eid } }
          end
        when "earthquakes"
          eq_scope = Earthquake.where(event_time: from..to)
          eq_scope = eq_scope.within_bounds(bounds) if bounds.size == 4
          eq_scope.limit(1000).each do |eq|
            features << {
              type: "Feature",
              geometry: { type: "Point", coordinates: [eq.longitude, eq.latitude] },
              properties: { type: "earthquake", title: eq.title, magnitude: eq.magnitude, depth: eq.depth, time: eq.event_time&.iso8601 },
            }
          end
        when "conflicts"
          cf_scope = ConflictEvent.where("date_start <= ? AND (date_end IS NULL OR date_end >= ?)", to, from)
          cf_scope = cf_scope.within_bounds(bounds) if bounds.size == 4
          cf_scope.limit(1000).each do |cf|
            features << {
              type: "Feature",
              geometry: { type: "Point", coordinates: [cf.longitude, cf.latitude] },
              properties: { type: "conflict", name: cf.conflict_name, event_type: cf.event_type, fatalities: cf.fatalities },
            }
          end
        end
      end

      geojson = { type: "FeatureCollection", features: features, metadata: { exported_at: Time.current.iso8601, from: from.iso8601, to: to.iso8601, layers: layers } }

      respond_to do |format|
        format.json { render json: geojson }
        format.any { send_data geojson.to_json, filename: "globe-tracker-export-#{Time.current.strftime('%Y%m%d-%H%M%S')}.geojson", type: "application/geo+json" }
      end
    end

    # GET /api/exports/csv?layer=flights&from=ISO&to=ISO
    def csv
      layer = params[:layer] || "flights"
      from = parse_time(params[:from]) || 1.hour.ago
      to = parse_time(params[:to]) || Time.current
      from = [from, to - 7.days].max
      bounds = parse_bounds

      csv_data = CSV.generate(headers: true) do |csv|
        case layer
        when "flights"
          csv << %w[entity_id callsign latitude longitude altitude heading speed recorded_at]
          scope = PositionSnapshot.flights.in_range(from, to)
          scope = scope.within_bounds(bounds) if bounds.size == 4
          scope.order(:recorded_at).limit(50_000).find_each do |s|
            csv << [s.entity_id, s.callsign, s.latitude, s.longitude, s.altitude, s.heading, s.speed, s.recorded_at&.iso8601]
          end
        when "ships"
          csv << %w[entity_id latitude longitude heading speed recorded_at]
          scope = PositionSnapshot.ships.in_range(from, to)
          scope = scope.within_bounds(bounds) if bounds.size == 4
          scope.order(:recorded_at).limit(50_000).find_each do |s|
            csv << [s.entity_id, s.latitude, s.longitude, s.heading, s.speed, s.recorded_at&.iso8601]
          end
        when "earthquakes"
          csv << %w[external_id title magnitude depth latitude longitude event_time]
          Earthquake.where(event_time: from..to).order(:event_time).limit(10_000).each do |eq|
            csv << [eq.external_id, eq.title, eq.magnitude, eq.depth, eq.latitude, eq.longitude, eq.event_time&.iso8601]
          end
        end
      end

      send_data csv_data, filename: "globe-tracker-#{layer}-#{Time.current.strftime('%Y%m%d-%H%M%S')}.csv", type: "text/csv"
    end

    # GET /api/exports/flight_history/:id — full route for a specific flight
    def flight_history
      entity_id = params[:id]
      from = parse_time(params[:from]) || 24.hours.ago
      to = parse_time(params[:to]) || Time.current

      snaps = PositionSnapshot.flights
        .where(entity_id: entity_id)
        .in_range(from, to)
        .order(:recorded_at)
        .limit(5000)

      render json: {
        entity_id: entity_id,
        callsign: snaps.first&.callsign,
        point_count: snaps.size,
        from: from.iso8601,
        to: to.iso8601,
        route: snaps.map { |s|
          { lat: s.latitude, lng: s.longitude, alt: s.altitude, hdg: s.heading, spd: s.speed, t: s.recorded_at.to_i }
        },
      }
    end

    private

    def parse_time(str)
      return nil if str.blank?
      Time.parse(str)
    rescue ArgumentError
      nil
    end

    def parse_bounds
      %i[lamin lamax lomin lomax].each_with_object({}) do |key, h|
        h[key] = params[key].to_f if params[key].present?
      end
    end
  end
end
