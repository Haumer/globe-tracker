module Api
  class PlaybackController < ApplicationController
    skip_before_action :authenticate_user!

    STRIKE_TIMELINE_WINDOW = 7.days

    # GET /api/playback?from=ISO8601&to=ISO8601&type=flight|ship|all&lamin=&lamax=&lomin=&lomax=
    def index
      from = parse_time(params[:from]) || 1.hour.ago
      to = parse_time(params[:to]) || Time.current
      entity_type = params[:type].presence || "flight"

      # Signed-in users get 7-day range, anonymous get 24 hours
      max_range = current_user ? 7.days : 24.hours
      from = [from, to - max_range].max

      bounds = parse_bounds
      # Auto-scale interval for large ranges to keep frame count manageable
      range_hours = ((to - from) / 1.hour).to_i
      default_interval = if range_hours > 48 then 120
                         elsif range_hours > 12 then 60
                         else 30
                         end
      interval_seconds = if params[:interval].present?
        params[:interval].to_i.clamp(10, 120).minutes.to_i
      elsif range_hours > 24
        default_interval.minutes.to_i
      end
      effective_bounds = bounds.size == 4 ? bounds : {}

      if effective_bounds.empty?
        render json: {
          from: from.utc.iso8601,
          to: to.utc.iso8601,
          entity_type: entity_type,
          frame_count: 0,
          frames: {},
          error: "viewport_bounds_required",
        }
        return
      end

      if entity_type == "all"
        # Unified timeline: load both flights and ships
        flight_frames = PositionSnapshot.playback_frames(entity_type: "flight", from: from, to: to, bounds: effective_bounds, interval: interval_seconds)
        ship_frames = PositionSnapshot.playback_frames(entity_type: "ship", from: from, to: to, bounds: effective_bounds, interval: interval_seconds)

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
          interval: interval_seconds,
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
      expires_in 5.minutes, public: true

      data = Rails.cache.fetch("playback:range", expires_in: 2.minutes) do
        # Use ORDER+LIMIT instead of MIN/MAX — hits the recorded_at index on 64M rows
        oldest = PositionSnapshot.order(:recorded_at).limit(1).pick(:recorded_at)
        newest = PositionSnapshot.order(recorded_at: :desc).limit(1).pick(:recorded_at)

        # Smaller tables — MIN/MAX is fine
        time_points = [oldest, newest].compact
        [
          Earthquake.minimum(:event_time),    Earthquake.maximum(:event_time),
          NaturalEvent.minimum(:event_date),  NaturalEvent.maximum(:event_date),
          NewsEvent.minimum(:published_at),   NewsEvent.maximum(:published_at),
          FireHotspot.minimum(:acq_datetime), FireHotspot.maximum(:acq_datetime),
          ConflictEvent.minimum(:date_start), ConflictEvent.maximum(:date_start),
          GpsJammingSnapshot.minimum(:recorded_at), GpsJammingSnapshot.maximum(:recorded_at),
          InternetOutage.minimum(:started_at),      InternetOutage.maximum(:started_at),
          InternetTrafficSnapshot.minimum(:recorded_at), InternetTrafficSnapshot.maximum(:recorded_at),
          WeatherAlert.minimum(:onset),       WeatherAlert.maximum(:onset),
          Notam.minimum(:effective_start),    Notam.maximum(:effective_start),
          CommodityPrice.minimum(:recorded_at), CommodityPrice.maximum(:recorded_at),
          SatelliteTleSnapshot.minimum(:recorded_at), SatelliteTleSnapshot.maximum(:recorded_at),
        ].compact.each { |t| time_points << t }

        geoconfirmed_oldest = [GeoconfirmedEvent.minimum(:posted_at), GeoconfirmedEvent.minimum(:event_time)].compact.min
        geoconfirmed_newest = [GeoconfirmedEvent.maximum(:posted_at), GeoconfirmedEvent.maximum(:event_time)].compact.max
        time_points << geoconfirmed_oldest if geoconfirmed_oldest
        time_points << geoconfirmed_newest if geoconfirmed_newest

        global_oldest = time_points.min
        global_newest = time_points.max

        # Use pg_class estimate for huge tables — exact count is unnecessary here
        snap_estimate = ActiveRecord::Base.connection.select_value(
          "SELECT reltuples::bigint FROM pg_class WHERE relname = 'position_snapshots'"
        ).to_i

        {
          oldest: global_oldest&.utc&.iso8601,
          newest: global_newest&.utc&.iso8601,
          total_snapshots: snap_estimate,
          flights: PositionSnapshot.where(entity_type: "flight").order(recorded_at: :desc).limit(1).exists? ? "available" : 0,
          ships: PositionSnapshot.where(entity_type: "ship").order(recorded_at: :desc).limit(1).exists? ? "available" : 0,
          layers: {
            earthquakes: Earthquake.count,
            natural_events: NaturalEvent.count,
            news: NewsEvent.count,
            heat_signatures: FireHotspot.count,
            geoconfirmed: GeoconfirmedEvent.count,
            conflicts: ConflictEvent.count,
            gps_jamming: GpsJammingSnapshot.count,
            outages: InternetOutage.count,
            internet_traffic: InternetTrafficSnapshot.count,
            weather_alerts: WeatherAlert.count,
            notams: Notam.count,
            markets: CommodityPrice.count,
            satellites: SatelliteTleSnapshot.count,
          },
        }
      end

      render json: data
    end

    # GET /api/playback/events?from=ISO8601&to=ISO8601&types=earthquake,news,...
    def events
      from = parse_time(params[:from]) || 1.hour.ago
      to = parse_time(params[:to]) || Time.current
      types = params[:types]&.split(",")&.map(&:strip)
      max_range = max_event_range_for(types)
      from = [from, to - max_range].max

      bounds = parse_bounds
      requested_types = Array(types).presence || []
      timeline_types = requested_types - %w[fire geoconfirmed internet_outage]

      events = []

      if timeline_types.any?
        scope = TimelineEvent.in_range(from, to).of_type(timeline_types)
        scope = scope.within_bounds(bounds) if bounds.size == 4
        timeline_limit = (timeline_types & %w[gps_jamming weather_alert notam]).any? ? 5000 : 2000
        events.concat(scope.order(recorded_at: :desc).limit(timeline_limit).includes(:eventable).filter_map { |te| timeline_event_json(te) })
      end

      if requested_types.include?("fire")
        scope = FireHotspot.in_range(from, to)
        scope = scope.within_bounds(bounds) if bounds.size == 4
        events.concat(scope.order(:acq_datetime).limit(5000).map { |fire| playback_fire_event_json(fire) })
      end

      if requested_types.include?("geoconfirmed")
        scope = GeoconfirmedEvent.where("COALESCE(posted_at, event_time, fetched_at) BETWEEN ? AND ?", from, to)
        scope = scope.within_bounds(bounds) if bounds.size == 4
        events.concat(scope.order(Arel.sql("COALESCE(posted_at, event_time, fetched_at) ASC")).limit(5000).map { |gc| playback_geoconfirmed_event_json(gc) })
      end

      if requested_types.include?("internet_outage")
        events.concat(playback_internet_outage_events(from: from, to: to, bounds: bounds))
      end

      render json: events.sort_by { |event| event[:time].to_s }
    end

    # GET /api/playback/conflicts?at=ISO8601
    def conflicts
      at = parse_time(params[:at]) || Time.current
      data = ConflictPulseService.analyze_at(at)
      render json: data
    end

    # GET /api/playback/satellites?at=ISO8601&category=starlink
    def satellites
      at = parse_time(params[:at]) || Time.current

      scope = SatelliteTleSnapshot.tles_at(at)
      if params[:categories].present?
        scope = scope.where(category: params[:categories].split(",").map(&:strip))
      elsif params[:category].present?
        scope = scope.where(category: params[:category])
      end

      render json: {
        at: at.utc.iso8601,
        count: scope.length,
        satellites: scope.map { |s|
          { norad_id: s.norad_id, name: s.name, tle_line1: s.tle_line1, tle_line2: s.tle_line2, category: s.category }
        },
      }
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
      when "fire"
        fire = te.eventable
        base.merge(
          external_id: fire.external_id,
          brightness: fire.brightness,
          confidence: fire.confidence,
          satellite: fire.satellite,
          instrument: fire.instrument,
          frp: fire.frp,
          daynight: fire.daynight,
          detectionKind: "heat_signature",
        )
      when "geoconfirmed"
        gc = te.eventable
        base.merge(
          external_id: gc.external_id,
          title: gc.title,
          region: gc.map_region,
          description: clean_geoconfirmed_description(gc.description),
          sourceUrls: gc.source_urls || [],
          geoUrls: gc.geolocation_urls || [],
          detectionKind: "verified_strike",
        )
      when "earthquake"
        eq = te.eventable
        base.merge(title: eq.title, mag: eq.magnitude, depth: eq.depth, url: eq.url, magType: eq.magnitude_type)
      when "natural_event"
        ev = te.eventable
        base.merge(title: ev.title, categoryId: ev.category_id, categoryTitle: ev.category_title, magnitudeValue: ev.magnitude_value)
      when "news"
        ne = te.eventable
        themes = parse_json_field(ne.themes)
        base.merge(name: ne.name, title: ne.title, url: ne.url, tone: ne.tone, level: ne.level,
                   category: ne.category, themes: themes, source: ne.source,
                   threat: ne.threat_level, cluster_id: ne.story_cluster_id)
      when "gps_jamming"
        gj = te.eventable
        base.merge(total: gj.total, bad: gj.bad, pct: gj.percentage, level: gj.level)
      when "internet_outage"
        io = te.eventable
        base.merge(code: io.entity_code, name: io.entity_name, score: io.score, level: io.level)
      when "weather_alert"
        wa = te.eventable
        base.merge(event: wa.event, severity: wa.severity, urgency: wa.urgency, certainty: wa.certainty,
                   headline: wa.headline, description: wa.description, areas: wa.areas,
                   sender: wa.sender, onset: wa.onset&.iso8601, expires: wa.expires&.iso8601)
      when "notam"
        n = te.eventable
        base.merge(reason: n.reason, text: n.text, radius_nm: n.radius_nm,
                   radius_m: n.radius_m, alt_low_ft: n.alt_low_ft, alt_high_ft: n.alt_high_ft,
                   effective_start: n.effective_start&.iso8601, effective_end: n.effective_end&.iso8601)
      else
        base
      end
    end

    def parse_time(str)
      return nil if str.blank?
      Time.parse(str)
    rescue ArgumentError
      nil
    end

    def max_event_range_for(types)
      requested_types = Array(types)
      return STRIKE_TIMELINE_WINDOW if (requested_types & %w[fire geoconfirmed]).any?

      7.days
    end

    def clean_geoconfirmed_description(desc)
      return nil if desc.blank?

      desc.gsub(/<[^>]+>/, "\n")
          .split(/\n+/)
          .map(&:strip)
          .reject(&:blank?)
          .reject { |line| line.start_with?("http") }
          .reject { |line| line.match?(/\A(Source|Geolocation|More images|gear ID)/i) }
          .first(3)
          .join(" ")
          .truncate(300)
          .presence
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
        time: s.recorded_at&.utc&.iso8601,
        x: s.extra.present? ? JSON.parse(s.extra) : nil,
      }
    end

    def playback_fire_event_json(fire)
      {
        id: "fire-#{fire.id}",
        type: "fire",
        lat: fire.latitude,
        lng: fire.longitude,
        time: fire.acq_datetime&.iso8601,
        external_id: fire.external_id,
        brightness: fire.brightness,
        confidence: fire.confidence,
        satellite: fire.satellite,
        instrument: fire.instrument,
        frp: fire.frp,
        daynight: fire.daynight,
        detectionKind: "heat_signature",
      }
    end

    def playback_geoconfirmed_event_json(gc)
      {
        id: "geoconfirmed-#{gc.id}",
        type: "geoconfirmed",
        lat: gc.latitude,
        lng: gc.longitude,
        time: gc.timeline_recorded_at&.iso8601,
        external_id: gc.external_id,
        title: gc.title,
        region: gc.map_region,
        description: clean_geoconfirmed_description(gc.description),
        sourceUrls: gc.source_urls || [],
        geoUrls: gc.geolocation_urls || [],
        detectionKind: "verified_strike",
      }
    end

    def playback_internet_outage_events(from:, to:, bounds:)
      scope = InternetOutage.in_range(from, to).order(:started_at).limit(1000)

      scope.filter_map do |outage|
        lat, lng = outage_centroid(outage.entity_code)
        next if bounds.size == 4 && !point_in_bounds?(lat, lng, bounds)

        {
          id: "internet-outage-#{outage.id}",
          type: "internet_outage",
          lat: lat,
          lng: lng,
          time: (outage.started_at || outage.fetched_at)&.iso8601,
          code: outage.entity_code,
          name: outage.entity_name,
          score: outage.score,
          level: outage.level,
        }
      end
    end

    def outage_centroid(code)
      centroid = CrossLayerAnalyzer::Definitions::COUNTRY_CENTROIDS[code.to_s.upcase]
      centroid ? [centroid[0], centroid[1]] : [nil, nil]
    end

    def point_in_bounds?(lat, lng, bounds)
      return false if lat.nil? || lng.nil?

      lat >= bounds[:lamin] && lat <= bounds[:lamax] &&
        lng >= bounds[:lomin] && lng <= bounds[:lomax]
    end
  end
end
