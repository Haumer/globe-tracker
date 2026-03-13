class AreaReport
  def self.generate(bounds)
    new(bounds).generate
  end

  def initialize(bounds)
    @bounds = bounds.transform_keys(&:to_sym)
  end

  def generate
    {
      flights: flight_summary,
      earthquakes: earthquake_summary,
      fires: fire_summary,
      conflicts: conflict_summary,
      jamming: jamming_summary,
      infrastructure: infrastructure_summary,
      anomalies: area_anomalies,
    }.compact
  end

  private

  # ── Flights ────────────────────────────────────────────────

  def flight_summary
    flights = Flight.within_bounds(@bounds)
    total = flights.count
    return nil if total == 0

    military = flights.where(military: true).count
    emergency = flights.where(squawk: %w[7500 7600 7700]).count
    countries = flights.where.not(origin_country: nil).group(:origin_country).order(Arel.sql("count(*) DESC")).limit(5).count

    {
      total: total,
      military: military,
      civilian: total - military,
      emergency: emergency,
      top_countries: countries,
    }
  end

  # ── Earthquakes ────────────────────────────────────────────

  def earthquake_summary
    quakes = Earthquake.within_bounds(@bounds).where("event_time > ?", 7.days.ago)
    total = quakes.count
    return nil if total == 0

    max = quakes.order(magnitude: :desc).first
    avg_mag = quakes.average(:magnitude)&.round(1)

    {
      total: total,
      max_magnitude: max.magnitude,
      max_title: max.title,
      avg_magnitude: avg_mag,
      tsunami_warnings: quakes.where(tsunami: true).count,
    }
  end

  # ── Fires ──────────────────────────────────────────────────

  def fire_summary
    fires = FireHotspot.within_bounds(@bounds).where("acq_datetime > ?", 48.hours.ago)
    total = fires.count
    return nil if total == 0

    high_conf = fires.where(confidence: %w[high h]).or(fires.where("CAST(confidence AS INTEGER) >= 80")).count rescue 0
    max_frp = fires.maximum(:frp)
    satellites = fires.distinct.pluck(:satellite).compact

    {
      total: total,
      high_confidence: high_conf,
      max_frp: max_frp&.round(1),
      satellites: satellites,
    }
  end

  # ── Conflicts ──────────────────────────────────────────────

  def conflict_summary
    conflicts = ConflictEvent.where(
      latitude: @bounds[:lamin]..@bounds[:lamax],
      longitude: @bounds[:lomin]..@bounds[:lomax]
    ).where("date_end IS NULL OR date_end >= ?", 90.days.ago)
    total = conflicts.count
    return nil if total == 0

    casualties = conflicts.sum(:best_estimate)
    names = conflicts.distinct.pluck(:conflict_name).first(5)

    {
      total: total,
      casualties: casualties,
      conflicts: names,
    }
  end

  # ── GPS Jamming ────────────────────────────────────────────

  def jamming_summary
    cells = GpsJammingSnapshot.where("recorded_at > ?", 1.hour.ago)
      .where(cell_lat: @bounds[:lamin]..@bounds[:lamax], cell_lng: @bounds[:lomin]..@bounds[:lomax])
      .where("percentage > 2")

    high = cells.where("percentage > 10").count
    medium = cells.where("percentage > 2 AND percentage <= 10").count
    return nil if high == 0 && medium == 0

    {
      high_cells: high,
      medium_cells: medium,
    }
  end

  # ── Infrastructure ─────────────────────────────────────────

  def infrastructure_summary
    plants = PowerPlant.within_bounds(@bounds)
    total = plants.count
    return nil if total == 0

    nuclear = plants.where(primary_fuel: "Nuclear").count
    total_mw = plants.sum(:capacity_mw).round(0)
    fuel_mix = plants.group(:primary_fuel).order(Arel.sql("count(*) DESC")).limit(5).count

    cables = SubmarineCable.all.select do |cable|
      coords = cable.coordinates
      next false unless coords.is_a?(Array)
      flat = coords.first.is_a?(Array) && coords.first.first.is_a?(Array) ? coords.flatten(1) : coords
      flat.any? { |pt| pt.is_a?(Array) && pt.size >= 2 &&
        pt[1] >= @bounds[:lamin] && pt[1] <= @bounds[:lamax] &&
        pt[0] >= @bounds[:lomin] && pt[0] <= @bounds[:lomax] }
    end

    # Calculate % of national capacity in this area
    country_shares = plants.group(:country_code).sum(:capacity_mw).map do |code, area_mw|
      next nil unless code.present?
      national_mw = PowerPlant.where(country_code: code).sum(:capacity_mw)
      next nil if national_mw <= 0
      pct = (area_mw / national_mw * 100).round(1)
      { country: code, area_mw: area_mw.round(0).to_i, national_mw: national_mw.round(0).to_i, pct: pct }
    end.compact.sort_by { |s| -s[:pct] }.first(5)

    {
      power_plants: total,
      nuclear: nuclear,
      total_capacity_mw: total_mw.to_i,
      fuel_mix: fuel_mix,
      submarine_cables: cables.size,
      country_shares: country_shares,
    }
  end

  # ── Anomalies in area ──────────────────────────────────────

  def area_anomalies
    all = AnomalyDetector.detect
    in_area = all.select do |a|
      next false unless a[:lat] && a[:lng]
      a[:lat] >= @bounds[:lamin] && a[:lat] <= @bounds[:lamax] &&
        a[:lng] >= @bounds[:lomin] && a[:lng] <= @bounds[:lomax]
    end
    return nil if in_area.empty?
    in_area
  end
end
