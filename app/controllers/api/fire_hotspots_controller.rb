module Api
  class FireHotspotsController < ApplicationController
    skip_before_action :authenticate_user!

    # Countries with active military conflict — hotspots here may be strikes
    CONFLICT_COUNTRIES = {
      "UA" => { lat: 44..53,   lng: 22..41   }, # Ukraine
      "IR" => { lat: 25..40,   lng: 44..64   }, # Iran
      "IL" => { lat: 29..34,   lng: 34..36   }, # Israel
      "PS" => { lat: 30..33,   lng: 34..36   }, # Palestine/Gaza
      "LB" => { lat: 33..35,   lng: 35..37   }, # Lebanon
      "SY" => { lat: 32..37,   lng: 35..42   }, # Syria
      "IQ" => { lat: 29..38,   lng: 39..49   }, # Iraq
      "YE" => { lat: 12..19,   lng: 42..54   }, # Yemen
      "SD" => { lat: 8..22,    lng: 22..39   }, # Sudan
      "MM" => { lat: 10..28,   lng: 92..102  }, # Myanmar
      "AF" => { lat: 29..39,   lng: 60..75   }, # Afghanistan
      "PK" => { lat: 24..37,   lng: 61..78   }, # Pakistan (border regions)
    }.freeze

    def index
      hotspots = FireHotspot.recent.order(acq_datetime: :desc).limit(5000)

      render json: hotspots.map { |h|
        strike = possible_strike?(h)
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
          strike ? 1 : 0, # index 10: possible strike flag
        ]
      }
    end

    private

    def possible_strike?(h)
      # High confidence + significant thermal signature
      conf = h.confidence.to_s
      is_confident = conf == "high" || conf == "h" || conf.to_i >= 80
      return false unless is_confident

      # Must be in a conflict zone
      in_conflict = CONFLICT_COUNTRIES.any? do |_code, bounds|
        bounds[:lat].cover?(h.latitude) && bounds[:lng].cover?(h.longitude)
      end
      return false unless in_conflict

      # Nighttime detections in conflict zones are more likely strikes
      # High FRP (>20 MW) in conflict zones is suspicious regardless of time
      is_night = h.daynight == "N"
      high_frp = (h.frp || 0) > 20
      high_brightness = (h.brightness || 0) > 360

      is_night || high_frp || high_brightness
    end
  end
end
