module Api
  class FlightsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      bounds = parse_bounds

      # Read from DB — the GlobalPollerService keeps flights fresh in the background
      flights = Flight.where("updated_at > ?", 2.minutes.ago)
      flights = flights.within_bounds(bounds) if bounds.present?

      render json: flights.map { |f|
        {
          icao24: f.icao24,
          callsign: f.callsign,
          latitude: f.latitude,
          longitude: f.longitude,
          altitude: f.altitude,
          speed: f.speed,
          heading: f.heading,
          origin_country: f.origin_country,
          on_ground: f.on_ground,
          vertical_rate: f.vertical_rate,
          time_position: f.time_position,
          source: f.source,
          registration: f.registration,
          aircraft_type: f.aircraft_type,
          military: f.military,
          squawk: f.squawk,
          emergency: f.emergency,
          category: f.category,
          indicated_airspeed: f.indicated_airspeed,
          true_airspeed: f.true_airspeed,
          mach: f.mach,
          mag_heading: f.mag_heading,
          true_heading: f.true_heading,
          roll: f.roll,
          track_rate: f.track_rate,
          nav_qnh: f.nav_qnh,
          nav_altitude_mcp: f.nav_altitude_mcp,
          nav_altitude_fms: f.nav_altitude_fms,
          wind_direction: f.wind_direction,
          wind_speed: f.wind_speed,
          outside_air_temp: f.outside_air_temp,
          signal_strength: f.signal_strength,
          message_type: f.message_type,
        }
      }
    end

    def show
      callsign = params[:id]&.strip
      route = ::OpenskyService.fetch_route(callsign)
      render json: route
    end
  end
end
