module Api
  class GpsJammingController < ApplicationController
    include TimelineRecorder
    skip_before_action :authenticate_user!

    NACP_THRESHOLD = 4
    HEX_SIZE = 1.0 # degrees (~111km) — radius of each hexagon, matches real GPS jamming footprint
    STALE_AFTER = 5.minutes

    def index
      # Timeline mode: return historical snapshots
      if params[:from].present? && params[:to].present?
        from = Time.parse(params[:from]) rescue 1.hour.ago
        to = Time.parse(params[:to]) rescue Time.current
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

      # Snapshots are now computed by GlobalPollerService in the background

      # Render latest reading per cell from the last hour — stale cells expire naturally
      cutoff = 1.hour.ago
      snaps = GpsJammingSnapshot
                .where("recorded_at > ?", cutoff)
                .where("percentage > 0 AND total >= 8")
                .select(
                  "DISTINCT ON (cell_lat, cell_lng) cell_lat, cell_lng, total, bad, percentage, level, recorded_at"
                )
                .order("cell_lat, cell_lng, recorded_at DESC")

      expires_in 30.seconds, public: true

      now = Time.current
      render json: snaps.map { |s|
        age_minutes = ((now - s.recorded_at) / 60.0)
        # Degrade confidence: fade percentage linearly over 1 hour
        fade = [1.0 - (age_minutes / 60.0), 0.0].max
        pct = (s.percentage.to_f * fade).round(1)
        level = if pct > 10 then "high"
                elsif pct > 2 then "medium"
                else "low"
                end
        { lat: s.cell_lat, lng: s.cell_lng, total: s.total, bad: s.bad, pct: pct, level: level }
      }
    end

    private

    def compute_snapshot
      flights = Flight.where(source: "adsb")
                      .where.not(latitude: nil, longitude: nil, nac_p: nil)
                      .where("updated_at > ?", 1.hour.ago)
                      .select(:id, :latitude, :longitude, :nac_p)

      cells = {}
      row_h = HEX_SIZE * Math.sqrt(3)

      flights.find_each do |f|
        next if f.latitude.nil? || f.longitude.nil? || f.nac_p.nil?

        row = (f.latitude / row_h).round
        center_lat = row * row_h

        cos_lat = Math.cos(center_lat * Math::PI / 180)
        cos_lat = 0.01 if cos_lat < 0.01
        col_w = HEX_SIZE * 1.5 / cos_lat
        offset = row.odd? ? col_w / 2.0 : 0.0
        col = ((f.longitude - offset) / col_w).round

        center_lng = col * col_w + offset
        key = "#{row},#{col}"

        cells[key] ||= { lat: center_lat, lng: center_lng, total: 0, bad: 0 }
        cells[key][:total] += 1
        cells[key][:bad] += 1 if f.nac_p <= NACP_THRESHOLD
      end

      now = Time.current
      result = cells.values
                    .select { |c| c[:total] >= 8 }
                    .map do |c|
        pct = (c[:bad].to_f / c[:total] * 100).round(1)
        level = if pct > 10 then "high"
                elsif pct > 2 then "medium"
                else "low"
                end
        { lat: c[:lat], lng: c[:lng], total: c[:total], bad: c[:bad], pct: pct, level: level }
      end

      return unless result.any?

      snapshots = result.map do |c|
        {
          cell_lat: c[:lat], cell_lng: c[:lng],
          total: c[:total], bad: c[:bad],
          percentage: c[:pct], level: c[:level],
          recorded_at: now, created_at: now, updated_at: now,
        }
      end
      GpsJammingSnapshot.insert_all(snapshots)

      # Record significant jamming cells to timeline
      significant = GpsJammingSnapshot.where(recorded_at: now, level: %w[medium high])
      tl_rows = significant.map do |s|
        {
          event_type: "gps_jamming",
          eventable_type: "GpsJammingSnapshot", eventable_id: s.id,
          latitude: s.cell_lat, longitude: s.cell_lng,
          recorded_at: s.recorded_at, created_at: now, updated_at: now,
        }
      end
      TimelineEvent.insert_all(tl_rows) if tl_rows.any?
    end
  end
end
