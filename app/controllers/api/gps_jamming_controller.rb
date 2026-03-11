module Api
  class GpsJammingController < ApplicationController
    include TimelineRecorder
    skip_before_action :authenticate_user!

    NACP_THRESHOLD = 6
    CELL_SIZE = 1.0

    def index
      # Timeline mode: return historical snapshots
      if params[:from].present? && params[:to].present?
        from = Time.parse(params[:from]) rescue 1.hour.ago
        to = Time.parse(params[:to]) rescue Time.current
        # Get the most recent snapshot batch within the range
        latest = GpsJammingSnapshot.in_range(from, to).maximum(:recorded_at)
        if latest
          snaps = GpsJammingSnapshot.where(recorded_at: latest)
          return render(json: snaps.map { |s|
            { lat: s.cell_lat, lng: s.cell_lng, total: s.total, bad: s.bad, pct: s.percentage, level: s.level }
          })
        else
          return render(json: [])
        end
      end

      flights = Flight.where(source: "adsb")
                      .where.not(latitude: nil, longitude: nil, nac_p: nil)
                      .where("updated_at > ?", 1.hour.ago)
                      .select(:id, :latitude, :longitude, :nac_p)

      cells = {}

      flights.find_each do |f|
        next if f.latitude.nil? || f.longitude.nil? || f.nac_p.nil?
        cell_lat = (f.latitude / CELL_SIZE).floor * CELL_SIZE
        cell_lng = (f.longitude / CELL_SIZE).floor * CELL_SIZE
        key = "#{cell_lat},#{cell_lng}"

        cells[key] ||= { lat: cell_lat + CELL_SIZE / 2, lng: cell_lng + CELL_SIZE / 2, total: 0, bad: 0 }
        cells[key][:total] += 1
        cells[key][:bad] += 1 if f.nac_p <= NACP_THRESHOLD
      end

      now = Time.current
      result = cells.values
                    .select { |c| c[:total] >= 3 }
                    .map do |c|
        pct = (c[:bad].to_f / c[:total] * 100).round(1)
        level = if pct > 10 then "high"
                elsif pct > 2 then "medium"
                else "low"
                end
        {
          lat: c[:lat],
          lng: c[:lng],
          total: c[:total],
          bad: c[:bad],
          pct: pct,
          level: level,
        }
      end

      # Persist snapshot
      if result.any?
        snapshots = result.map do |c|
          {
            cell_lat: c[:lat],
            cell_lng: c[:lng],
            total: c[:total],
            bad: c[:bad],
            percentage: c[:pct],
            level: c[:level],
            recorded_at: now,
            created_at: now,
            updated_at: now,
          }
        end
        GpsJammingSnapshot.insert_all(snapshots)

        # Record significant jamming cells to timeline (medium/high only)
        significant = GpsJammingSnapshot.where(recorded_at: now, level: %w[medium high])
        tl_rows = significant.map do |s|
          {
            event_type: "gps_jamming",
            eventable_type: "GpsJammingSnapshot",
            eventable_id: s.id,
            latitude: s.cell_lat,
            longitude: s.cell_lng,
            recorded_at: s.recorded_at,
            created_at: now,
            updated_at: now,
          }
        end
        TimelineEvent.insert_all(tl_rows) if tl_rows.any?
      end

      render json: result
    end
  end
end
