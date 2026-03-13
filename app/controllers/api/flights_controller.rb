module Api
  class FlightsController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      bounds = {
        lamin: params[:lamin]&.to_f,
        lamax: params[:lamax]&.to_f,
        lomin: params[:lomin]&.to_f,
        lomax: params[:lomax]&.to_f
      }.compact

      # Fetch from all sources in parallel
      opensky_thread = Thread.new { ::OpenskyService.fetch_flights(bounds: bounds) }
      adsb_thread = Thread.new { ::AdsbService.fetch_flights(bounds: bounds) }
      mil_thread = Thread.new { ::AdsbService.fetch_military }

      opensky_flights = begin
        opensky_thread.value
      rescue StandardError => e
        Rails.logger.error("OpenSky thread error: #{e.message}")
        []
      end

      adsb_flights = begin
        adsb_thread.value
      rescue StandardError => e
        Rails.logger.error("ADSB thread error: #{e.message}")
        []
      end

      mil_flights = begin
        mil_thread.value
      rescue StandardError => e
        Rails.logger.error("Military flights thread error: #{e.message}")
        []
      end

      # Merge: index by icao24, ADSB.lol wins on duplicates (has military + more data)
      merged = {}
      opensky_flights&.each { |f| merged[f.icao24] = f }
      adsb_flights&.each { |f| merged[f.icao24] = f }
      mil_flights&.each { |f| merged[f.icao24] = f }

      render json: merged.values.map { |f|
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
