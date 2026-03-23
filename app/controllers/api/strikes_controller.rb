module Api
  class StrikesController < ApplicationController
    skip_before_action :authenticate_user!

    CONFLICT_COUNTRIES = Api::FireHotspotsController::CONFLICT_COUNTRIES

    # Radius (degrees) to exclude hotspots near known industrial sites
    INDUSTRIAL_EXCLUSION_RADIUS = 0.05 # ~5.5km

    def index
      hotspots = FireHotspot.recent
        .where(confidence: %w[high h])
        .where("frp > 20 OR brightness > 360 OR daynight = 'N'")
        .order(acq_datetime: :desc)

      # Filter to conflict zones
      in_conflict = hotspots.select do |h|
        CONFLICT_COUNTRIES.any? { |_, b| b[:lat].cover?(h.latitude) && b[:lng].cover?(h.longitude) }
      end

      # Exclude hotspots near known oil/gas/industrial infrastructure
      industrial_sites = load_industrial_sites
      strikes = in_conflict.reject { |h| near_industrial?(h, industrial_sites) }

      # Temporal clustering boost: flag hotspots that have 2+ neighbors
      # within 0.5° (~55km) and 2 hours — likely coordinated strike
      strikes.each do |h|
        cluster = strikes.count do |other|
          next false if other.equal?(h)
          (h.latitude - other.latitude).abs < 0.5 &&
            (h.longitude - other.longitude).abs < 0.5 &&
            h.acq_datetime && other.acq_datetime &&
            (h.acq_datetime - other.acq_datetime).abs < 7200 # 2 hours
        end
        h.define_singleton_method(:cluster_size) { cluster }
      end

      # News correlation: check if conflict news exists near this location
      news_locations = load_recent_conflict_news_locations

      expires_in 5.minutes, public: true

      render json: strikes.map { |h|
        news_nearby = news_locations.any? do |nl|
          (h.latitude - nl[0]).abs < 2.0 && (h.longitude - nl[1]).abs < 2.0
        end
        confidence_label = if h.cluster_size >= 2 && news_nearby
          "high" # clustered + news corroboration
        elsif h.cluster_size >= 2 || news_nearby
          "medium" # one signal
        else
          "low" # lone detection, no news
        end

        [
          h.external_id,
          h.latitude,
          h.longitude,
          h.brightness,
          h.confidence,
          h.satellite,
          h.instrument,
          h.frp,
          h.daynight,
          h.acq_datetime&.to_i&.*(1000),
          confidence_label,    # index 10: strike confidence
          h.cluster_size,      # index 11: nearby detections
        ]
      }
    end

    private

    def load_industrial_sites
      @industrial_sites ||= begin
        # Oil, gas, petcoke plants in conflict zones — these produce constant thermal signatures
        industrial_fuels = %w[Gas Oil Petcoke Cogeneration]
        plants = PowerPlant.where(primary_fuel: industrial_fuels)
          .where.not(latitude: nil, longitude: nil)
          .pluck(:latitude, :longitude)

        # Also add well-known gas flare / refinery locations not in power plant DB
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

    def load_recent_conflict_news_locations
      @conflict_news_locs ||= NewsEvent
        .where("published_at > ?", 48.hours.ago)
        .where(category: %w[conflict terror])
        .where.not(latitude: nil)
        .pluck(:latitude, :longitude)
    end
  end
end
