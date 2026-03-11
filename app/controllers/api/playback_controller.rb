module Api
  class PlaybackController < ApplicationController
    skip_before_action :authenticate_user!

    # GET /api/playback?from=ISO8601&to=ISO8601&type=flight|ship|all&lamin=&lamax=&lomin=&lomax=
    def index
      from = parse_time(params[:from]) || 1.hour.ago
      to = parse_time(params[:to]) || Time.current
      entity_type = params[:type].presence || "flight"

      # Cap range to 24 hours
      from = [from, to - 24.hours].max

      bounds = {
        lamin: params[:lamin]&.to_f,
        lamax: params[:lamax]&.to_f,
        lomin: params[:lomin]&.to_f,
        lomax: params[:lomax]&.to_f
      }.compact

      interval = (params[:interval] || 10).to_i.clamp(5, 60)
      effective_bounds = bounds.size == 4 ? bounds : {}

      if entity_type == "all"
        # Unified timeline: load both flights and ships
        flight_frames = PositionSnapshot.playback_frames(entity_type: "flight", from: from, to: to, bounds: effective_bounds, interval: interval)
        ship_frames = PositionSnapshot.playback_frames(entity_type: "ship", from: from, to: to, bounds: effective_bounds, interval: interval)

        # Merge into unified frames with type annotation
        all_keys = (flight_frames.keys + ship_frames.keys).uniq.sort
        merged = {}
        all_keys.each do |key|
          entries = []
          (flight_frames[key] || []).each { |s| entries << snapshot_json(s).merge(type: "flight") }
          (ship_frames[key] || []).each { |s| entries << snapshot_json(s).merge(type: "ship") }
          merged[key] = entries
        end

        render json: {
          from: from.utc.iso8601,
          to: to.utc.iso8601,
          entity_type: "all",
          frame_count: merged.size,
          frames: merged,
        }
      else
        frames = PositionSnapshot.playback_frames(
          entity_type: entity_type,
          from: from,
          to: to,
          bounds: effective_bounds,
          interval: interval,
        )

        render json: {
          from: from.utc.iso8601,
          to: to.utc.iso8601,
          entity_type: entity_type,
          frame_count: frames.size,
          frames: frames.transform_values { |snaps| snaps.map { |s| snapshot_json(s) } },
        }
      end
    end

    # GET /api/playback/range — returns available data time range across all types
    def range
      oldest = PositionSnapshot.minimum(:recorded_at)
      newest = PositionSnapshot.maximum(:recorded_at)

      # Find the true global oldest/newest across all data types
      time_points = [oldest, newest].compact
      [
        Earthquake.minimum(:event_time),
        Earthquake.maximum(:event_time),
        NaturalEvent.minimum(:event_date),
        NaturalEvent.maximum(:event_date),
        NewsEvent.minimum(:published_at),
        NewsEvent.maximum(:published_at),
        GpsJammingSnapshot.minimum(:recorded_at),
        GpsJammingSnapshot.maximum(:recorded_at),
        InternetOutage.minimum(:started_at),
        InternetOutage.maximum(:started_at),
      ].compact.each { |t| time_points << t }

      global_oldest = time_points.min
      global_newest = time_points.max

      render json: {
        oldest: global_oldest&.utc&.iso8601,
        newest: global_newest&.utc&.iso8601,
        total_snapshots: PositionSnapshot.count,
        flights: PositionSnapshot.flights.count,
        ships: PositionSnapshot.ships.count,
        layers: {
          earthquakes: Earthquake.count,
          natural_events: NaturalEvent.count,
          news: NewsEvent.count,
          gps_jamming: GpsJammingSnapshot.count,
          outages: InternetOutage.count,
        },
      }
    end

    # GET /api/playback/events?from=ISO8601&to=ISO8601&types=earthquake,news,...
    def events
      from = parse_time(params[:from]) || 1.hour.ago
      to = parse_time(params[:to]) || Time.current
      from = [from, to - 24.hours].max

      types = params[:types]&.split(",")&.map(&:strip)

      scope = TimelineEvent.in_range(from, to)
      scope = scope.of_type(types) if types.present?

      bounds = {
        lamin: params[:lamin]&.to_f,
        lamax: params[:lamax]&.to_f,
        lomin: params[:lomin]&.to_f,
        lomax: params[:lomax]&.to_f
      }.compact
      scope = scope.within_bounds(bounds) if bounds.size == 4

      timeline_events = scope.order(:recorded_at).limit(2000).includes(:eventable)

      render json: timeline_events.filter_map { |te| timeline_event_json(te) }
    end

    private

    def timeline_event_json(te)
      return nil unless te.eventable

      base = {
        id: te.id,
        type: te.event_type,
        lat: te.latitude,
        lng: te.longitude,
        time: te.recorded_at&.iso8601,
      }

      case te.event_type
      when "earthquake"
        eq = te.eventable
        base.merge(title: eq.title, mag: eq.magnitude, depth: eq.depth, url: eq.url, magType: eq.magnitude_type)
      when "natural_event"
        ev = te.eventable
        base.merge(title: ev.title, categoryId: ev.category_id, categoryTitle: ev.category_title, magnitudeValue: ev.magnitude_value)
      when "news"
        ne = te.eventable
        themes = ne.themes.is_a?(String) ? (JSON.parse(ne.themes) rescue []) : (ne.themes || [])
        base.merge(name: ne.name, url: ne.url, tone: ne.tone, level: ne.level, category: ne.category, themes: themes)
      when "gps_jamming"
        gj = te.eventable
        base.merge(total: gj.total, bad: gj.bad, pct: gj.percentage, level: gj.level)
      when "internet_outage"
        io = te.eventable
        base.merge(code: io.entity_code, name: io.entity_name, score: io.score, level: io.level)
      else
        base
      end
    end

    # GET /api/playback/satellites?at=ISO8601&category=starlink
    def satellites
      at = parse_time(params[:at]) || Time.current

      scope = SatelliteTleSnapshot.tles_at(at)
      scope = scope.where(category: params[:category]) if params[:category].present?

      render json: {
        at: at.utc.iso8601,
        count: scope.length,
        satellites: scope.map { |s|
          { norad_id: s.norad_id, name: s.name, tle_line1: s.tle_line1, tle_line2: s.tle_line2, category: s.category }
        },
      }
    end

    def parse_time(str)
      return nil if str.blank?
      Time.parse(str)
    rescue ArgumentError
      nil
    end

    def snapshot_json(s)
      {
        id: s.entity_id,
        type: s.entity_type,
        callsign: s.callsign,
        lat: s.latitude,
        lng: s.longitude,
        alt: s.altitude,
        hdg: s.heading,
        spd: s.speed,
        vr: s.vertical_rate,
        gnd: s.on_ground,
        x: s.extra.present? ? JSON.parse(s.extra) : nil,
      }
    end
  end
end
