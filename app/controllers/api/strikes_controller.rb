module Api
  class StrikesController < ApplicationController
    skip_before_action :authenticate_user!

    CONFLICT_COUNTRIES = Api::FireHotspotsController::CONFLICT_COUNTRIES

    # Radius (degrees) to exclude hotspots near known industrial sites
    INDUSTRIAL_EXCLUSION_RADIUS = 0.05 # ~5.5km

    # Proximity for FIRMS <-> GeoConfirmed correlation
    GC_MATCH_RADIUS_DEG = 0.3  # ~33km
    GC_MATCH_WINDOW = 48.hours

    def index
      # ── FIRMS thermal detections ──────────────────────────────
      hotspots = FireHotspot.recent
        .where("confidence IN ('high', 'h', 'nominal', 'n') OR CAST(confidence AS INTEGER) >= 50")
        .where("frp > 10 OR brightness > 340 OR daynight = 'N'")
        .order(acq_datetime: :desc)

      in_conflict = hotspots.select do |h|
        CONFLICT_COUNTRIES.any? { |_, b| b[:lat].cover?(h.latitude) && b[:lng].cover?(h.longitude) }
      end

      industrial_sites = load_industrial_sites
      firms_strikes = in_conflict.reject { |h| near_industrial?(h, industrial_sites) }

      # ── GeoConfirmed verified events ──────────────────────────
      gc_events = GeoconfirmedEvent
        .where("posted_at > ? OR event_time > ?", 7.days.ago, 7.days.ago)
        .where.not(latitude: nil)
        .to_a

      # ── Temporal clustering for FIRMS ─────────────────────────
      firms_strikes.each do |h|
        cluster = firms_strikes.count do |other|
          next false if other.equal?(h)
          (h.latitude - other.latitude).abs < 0.5 &&
            (h.longitude - other.longitude).abs < 0.5 &&
            h.acq_datetime && other.acq_datetime &&
            (h.acq_datetime - other.acq_datetime).abs < 7200
        end
        h.define_singleton_method(:cluster_size) { cluster }
      end

      # ── Cross-reference FIRMS with GeoConfirmed ───────────────
      news_locations = load_recent_conflict_news_locations

      # Index GeoConfirmed events for spatial lookup
      gc_by_firms = firms_strikes.map do |h|
        matching_gc = gc_events.select do |gc|
          (h.latitude - gc.latitude).abs < GC_MATCH_RADIUS_DEG &&
            (h.longitude - gc.longitude).abs < GC_MATCH_RADIUS_DEG &&
            time_within_window?(h.acq_datetime, gc.posted_at || gc.event_time, GC_MATCH_WINDOW)
        end
        [h, matching_gc]
      end.to_h

      # Track which GeoConfirmed events were matched to a FIRMS detection
      matched_gc_ids = gc_by_firms.values.flatten.map(&:id).to_set

      expires_in 5.minutes, public: true

      # ── Build FIRMS strike entries ────────────────────────────
      firms_json = gc_by_firms.map do |h, matched_gcs|
        news_nearby = news_locations.any? do |nl|
          (h.latitude - nl[0]).abs < 2.0 && (h.longitude - nl[1]).abs < 2.0
        end
        gc_corroborated = matched_gcs.any?

        confidence_label = if gc_corroborated
          "verified"
        elsif h.cluster_size >= 2 && news_nearby
          "high"
        elsif h.cluster_size >= 2 || news_nearby
          "medium"
        else
          "low"
        end

        gc_info = if gc_corroborated
          best = matched_gcs.min_by { |gc| gc.posted_at || gc.event_time || Time.current }
          {
            title: best.title,
            posted_at: (best.posted_at || best.event_time)&.to_i&.*(1000),
            source_url: best.source_urls&.first,
            source_urls: best.source_urls || [],
            geolocation_urls: best.geolocation_urls || [],
            description: clean_description(best.description),
            region: best.map_region,
          }
        end

        [
          h.external_id,       # 0
          h.latitude,          # 1
          h.longitude,         # 2
          h.brightness,        # 3
          h.confidence,        # 4
          h.satellite,         # 5
          h.instrument,        # 6
          h.frp,               # 7
          h.daynight,          # 8
          h.acq_datetime&.to_i&.*(1000), # 9
          confidence_label,    # 10
          h.cluster_size,      # 11
          gc_info,             # 12: geoconfirmed match (or nil)
        ]
      end

      # ── Standalone GeoConfirmed events (not matched to FIRMS) ─
      gc_standalone_json = gc_events.reject { |gc| matched_gc_ids.include?(gc.id) }.map do |gc|
        best_time = gc.posted_at || gc.event_time
        [
          gc.external_id,       # 0
          gc.latitude,          # 1
          gc.longitude,         # 2
          gc.title,             # 3
          gc.map_region,        # 4
          best_time&.to_i&.*(1000), # 5
          gc.source_urls || [],     # 6: array of source URLs
          clean_description(gc.description), # 7
          gc.geolocation_urls || [], # 8: array of geolocation URLs
        ]
      end

      render json: {
        firms: firms_json,
        geoconfirmed: gc_standalone_json,
      }
    end

    private

    def time_within_window?(t1, t2, window)
      return false if t1.nil? || t2.nil?

      (t1 - t2).abs < window
    end

    def load_industrial_sites
      @industrial_sites ||= begin
        industrial_fuels = %w[Gas Oil Petcoke Cogeneration]
        plants = PowerPlant.where(primary_fuel: industrial_fuels)
          .where.not(latitude: nil, longitude: nil)
          .pluck(:latitude, :longitude)

        plants + [
          [38.50, 61.48],  # Shatlyk gas field, Turkmenistan border
          [29.08, 50.82],  # Assaluyeh / South Pars gas complex
          [27.50, 52.60],  # Kangan gas processing
          [30.43, 49.08],  # Abadan refinery
          [32.38, 48.42],  # Ahvaz oil field
          [35.48, 53.05],  # Semnan refinery
        ]
      end
    end

    def near_industrial?(hotspot, sites)
      sites.any? do |lat, lng|
        (hotspot.latitude - lat).abs < INDUSTRIAL_EXCLUSION_RADIUS &&
          (hotspot.longitude - lng).abs < INDUSTRIAL_EXCLUSION_RADIUS
      end
    end

    def clean_description(desc)
      return nil if desc.blank?

      lines = desc.gsub(/<[^>]+>/, "\n").split(/\n+/)
      lines
        .map(&:strip)
        .reject(&:blank?)
        .reject { |l| l.start_with?("http") }
        .reject { |l| l =~ /\ASource\(s\):/i }
        .reject { |l| l =~ /\AGeolocation\(s\):/i }
        .reject { |l| l =~ /\AMore images:/i }
        .reject { |l| l =~ /\Agear ID:/i }
        .first(3)
        .join(" ")
        .truncate(300)
        .presence
    end

    def load_recent_conflict_news_locations
      @conflict_news_locs ||= NewsEvent
        .where("published_at > ?", 48.hours.ago)
        .where(category: %w[conflict terror])
        .where.not(latitude: nil)
        .pluck(:latitude, :longitude)
    end
  end
end
