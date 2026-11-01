# Answers "which cable is nearest this point, and how far" for many points
# without comparing each one against every cable vertex.
#
# The naive version -- every slow ship against every vertex of every cable --
# was what SyncTheaterRelationshipsJob did, and at 21,000 anchored ships and
# 722 cables each run took three to four hours, piled up ten-minute launches
# until seven of the ten Sidekiq threads were in that loop, and starved the
# live-flight queue. Bucketing vertices into one-degree cells makes a lookup
# touch only the handful of cells a search radius can reach.
class SubmarineCableProximityIndex
  EARTH_RADIUS_KM = 6371.0
  KM_PER_DEGREE = 111.32
  CELL_DEGREES = 1.0

  Match = Struct.new(:cable, :distance_km, keyword_init: true)

  # points_for turns a cable into [[lat, lng], ...]; the caller already owns
  # the logic for choosing landing points over the full polyline.
  def self.build(cables, &points_for)
    index = new
    cables.each do |cable|
      points_for.call(cable).each { |lat, lng| index.add(cable, lat.to_f, lng.to_f) }
    end
    index
  end

  def initialize
    @cells = Hash.new { |hash, key| hash[key] = [] }
    @size = 0
  end

  attr_reader :size

  def add(cable, lat, lng)
    @cells[cell_for(lat, lng)] << [lat, lng, cable]
    @size += 1
  end

  # Nearest vertex within within_km of (lat, lng), as a Match, or nil. Any
  # vertex that close lies in the cells the search covers, so the answer is
  # the same as a full scan would give.
  def nearest(lat, lng, within_km:)
    return nil if lat.nil? || lng.nil? || @size.zero?

    lat = lat.to_f
    lng = lng.to_f
    best = nil

    each_candidate_cell(lat, lng, within_km) do |key|
      bucket = @cells[key] if @cells.key?(key)
      next unless bucket

      bucket.each do |point_lat, point_lng, cable|
        distance = haversine_km(point_lat, point_lng, lat, lng)
        next if distance > within_km
        next if best && distance >= best.distance_km

        best = Match.new(cable: cable, distance_km: distance)
      end
    end

    best
  end

  private

  LNG_CELLS = (360 / CELL_DEGREES).to_i

  # Longitude cells live in 0...LNG_CELLS so that stored keys and wrapped
  # lookup keys agree on both sides of the antimeridian.
  def cell_for(lat, lng)
    [(lat / CELL_DEGREES).floor, (normalize_lng(lng) / CELL_DEGREES).floor % LNG_CELLS]
  end

  # A degree of latitude is ~111 km everywhere; a degree of longitude shrinks
  # toward the poles, so the longitude span widens with latitude. Longitude
  # cells wrap so a search near the antimeridian sees both sides of it.
  def each_candidate_cell(lat, lng, within_km)
    lat_cells = (within_km / (KM_PER_DEGREE * CELL_DEGREES)).ceil
    cos_lat = Math.cos(lat * Math::PI / 180.0).abs
    lng_cells =
      if cos_lat < 0.01
        180
      else
        [(within_km / (KM_PER_DEGREE * CELL_DEGREES * cos_lat)).ceil, 180].min
      end

    center_lat, center_lng = cell_for(lat, lng)

    (-lat_cells..lat_cells).each do |dlat|
      (-lng_cells..lng_cells).each do |dlng|
        yield [center_lat + dlat, (center_lng + dlng) % LNG_CELLS]
      end
    end
  end

  def normalize_lng(lng)
    ((lng + 180.0) % 360.0) - 180.0
  end

  def haversine_km(lat1, lng1, lat2, lng2)
    radians_per_degree = Math::PI / 180.0
    dlat = (lat2 - lat1) * radians_per_degree
    dlng = (lng2 - lng1) * radians_per_degree
    a = Math.sin(dlat / 2)**2 +
      Math.cos(lat1 * radians_per_degree) *
      Math.cos(lat2 * radians_per_degree) *
      Math.sin(dlng / 2)**2

    EARTH_RADIUS_KM * (2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)))
  end
end
