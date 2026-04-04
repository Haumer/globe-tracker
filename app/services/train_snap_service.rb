class TrainSnapService
  EARTH_METERS_PER_DEGREE = 111_320.0
  CANDIDATE_RADIUS_M = 800.0
  MAX_SNAP_DISTANCE_M = 350.0
  HIGH_CONFIDENCE_DISTANCE_M = 45.0
  MEDIUM_CONFIDENCE_DISTANCE_M = 120.0
  STICKY_MATCH_BONUS_M = 20.0

  def self.snap_all(trains, previous_matches_by_external_id: {})
    new(trains, previous_matches_by_external_id: previous_matches_by_external_id).snap_all
  end

  def initialize(trains, previous_matches_by_external_id: {})
    @trains = Array(trains)
    @previous_matches_by_external_id = previous_matches_by_external_id || {}
  end

  def snap_all
    return {} if @trains.empty? || !Railway.exists?

    candidates = load_candidate_railways
    return {} if candidates.empty?

    @trains.each_with_object({}) do |train, snapped|
      match = snap_train(train, candidates)
      snapped[train[:id]] = match if match.present?
    end
  end

  private

  def load_candidate_railways
    lats = @trains.filter_map { |train| train[:lat]&.to_f }
    lngs = @trains.filter_map { |train| train[:lng]&.to_f }
    return [] if lats.empty? || lngs.empty?

    south = lats.min - meters_to_lat(CANDIDATE_RADIUS_M)
    north = lats.max + meters_to_lat(CANDIDATE_RADIUS_M)
    center_lat = (lats.min + lats.max) / 2.0
    lng_pad = meters_to_lng(CANDIDATE_RADIUS_M, center_lat)
    west = lngs.min - lng_pad
    east = lngs.max + lng_pad

    Railway.where("max_lat >= ? AND min_lat <= ? AND max_lng >= ? AND min_lng <= ?", south, north, west, east).to_a
  end

  def snap_train(train, candidates)
    lat = train[:lat]&.to_f
    lng = train[:lng]&.to_f
    return nil unless lat && lng

    lat_pad = meters_to_lat(CANDIDATE_RADIUS_M)
    lng_pad = meters_to_lng(CANDIDATE_RADIUS_M, lat)
    previous_match = @previous_matches_by_external_id[train[:id]]
    previous_railway_id = previous_match&.matched_railway_id

    best = nil

    candidates.each do |railway|
      next unless overlaps_search_window?(railway, lat, lng, lat_pad, lng_pad)
      next unless railway.coordinates.is_a?(Array) && railway.coordinates.size >= 2

      railway.coordinates.each_cons(2) do |a, b|
        projection = project_onto_segment(lat, lng, a, b)
        next unless projection

        effective_distance = projection[:distance_m]
        effective_distance -= STICKY_MATCH_BONUS_M if railway.id == previous_railway_id

        if best.nil? || effective_distance < best[:effective_distance]
          best = projection.merge(
            railway_id: railway.id,
            effective_distance: effective_distance
          )
        end
      end
    end

    return nil unless best
    return nil if best[:distance_m] > MAX_SNAP_DISTANCE_M

    {
      matched_railway_id: best[:railway_id],
      snapped_latitude: best[:lat],
      snapped_longitude: best[:lng],
      snap_distance_m: best[:distance_m].round(1),
      snap_confidence: snap_confidence(best[:distance_m]),
    }
  end

  def overlaps_search_window?(railway, lat, lng, lat_pad, lng_pad)
    railway.max_lat.to_f >= lat - lat_pad &&
      railway.min_lat.to_f <= lat + lat_pad &&
      railway.max_lng.to_f >= lng - lng_pad &&
      railway.min_lng.to_f <= lng + lng_pad
  end

  def project_onto_segment(lat, lng, point_a, point_b)
    return nil unless point_a.is_a?(Array) && point_b.is_a?(Array)

    cos_lat = [Math.cos(lat * Math::PI / 180.0).abs, 0.1].max

    ax = (point_a[0].to_f - lng) * EARTH_METERS_PER_DEGREE * cos_lat
    ay = (point_a[1].to_f - lat) * EARTH_METERS_PER_DEGREE
    bx = (point_b[0].to_f - lng) * EARTH_METERS_PER_DEGREE * cos_lat
    by = (point_b[1].to_f - lat) * EARTH_METERS_PER_DEGREE

    dx = bx - ax
    dy = by - ay
    len_sq = (dx * dx) + (dy * dy)

    if len_sq.zero?
      return {
        lat: point_a[1].to_f,
        lng: point_a[0].to_f,
        distance_m: Math.sqrt((ax * ax) + (ay * ay)),
      }
    end

    t = [[-((ax * dx) + (ay * dy)) / len_sq, 0.0].max, 1.0].min
    proj_x = ax + (dx * t)
    proj_y = ay + (dy * t)

    {
      lat: lat + (proj_y / EARTH_METERS_PER_DEGREE),
      lng: lng + (proj_x / (EARTH_METERS_PER_DEGREE * cos_lat)),
      distance_m: Math.sqrt((proj_x * proj_x) + (proj_y * proj_y)),
    }
  end

  def snap_confidence(distance_m)
    return "high" if distance_m <= HIGH_CONFIDENCE_DISTANCE_M
    return "medium" if distance_m <= MEDIUM_CONFIDENCE_DISTANCE_M

    "low"
  end

  def meters_to_lat(meters)
    meters / EARTH_METERS_PER_DEGREE
  end

  def meters_to_lng(meters, lat)
    meters / (EARTH_METERS_PER_DEGREE * [Math.cos(lat * Math::PI / 180.0).abs, 0.1].max)
  end
end
