
# Bulk-loads the GeoNames `cities5000` gazetteer into places/place_aliases.
#
# Before this, the gazetteer held 568 hand-curated places across 9 countries --
# a Ukraine/Gaza conflict list plus DACH city profiles. Anything outside it
# fell through to publisher-country geocoding, which is why 60% of ingested
# events landed on a newspaper's country rather than the story's location and
# 536 events shared just 74 distinct coordinates.
#
# cities5000 covers every settlement above ~5,000 people (~69k worldwide).
# That is deliberately not the largest tier available: cities1000 adds ~80k
# villages, but also places named "Same", "Why", "Of" and "Best", which match
# ordinary prose. A fabricated location is worse than none on a conflict map,
# so coverage is being raised one step at a time with the false-positive rate
# measured in between.
#
# Aliases come from the alternatenames column of the same file, so no second
# download is needed. Each place also gets a transliterated alias, letting
# "Koln" reach "Köln".
class GeonamesImportService
  SOURCE_URL = "https://download.geonames.org/export/dump/cities5000.zip".freeze

  # Population floor of the file itself; the low end of the score ramp.
  MIN_LOG_POP = 3.7
  MAX_LOG_POP = 7.6
  # Auto-imported places rank below the hand-curated set (0.35-0.99) so a
  # curated entry wins any tie against its GeoNames duplicate. Bakhmut matters
  # to this app far more than its population implies.
  SCORE_FLOOR = 0.10
  SCORE_CEILING = 0.75
  CAPITAL_BONUS = 0.12
  ADMIN_SEAT_BONUS = 0.05

  # Short names are where false positives live -- two- and three-letter place
  # names collide with ordinary words in every language.
  MIN_ALIAS_LENGTH = 4
  MAX_ALIASES_PER_PLACE = 10
  BATCH_SIZE = 2_000

  Row = Struct.new(:geonameid, :name, :asciiname, :alternatenames, :lat, :lng,
                   :feature_code, :country_code, :admin1, :population)

  class << self
    def import!(path:, logger: Rails.logger)
      new(logger: logger).import!(path: path)
    end
  end

  def initialize(logger: Rails.logger)
    @logger = logger
    @places = 0
    @aliases = 0
  end

  def import!(path:)
    each_batch(path) do |rows|
      upsert_places(rows)
      upsert_aliases(rows)
    end
    @logger.info("GeonamesImportService: #{@places} places, #{@aliases} aliases")
    { places: @places, aliases: @aliases }
  end

  private

  def each_batch(path)
    buffer = []
    File.foreach(path, encoding: "UTF-8") do |line|
      row = parse_line(line)
      next if row.nil?

      buffer << row
      next if buffer.size < BATCH_SIZE

      yield buffer
      buffer = []
    end
    yield buffer if buffer.any?
  end

  def parse_line(line)
    f = line.chomp.split("\t")
    return nil if f.size < 15

    population = f[14].to_i
    lat = f[4].to_f
    lng = f[5].to_f
    return nil if f[1].blank? || lat.zero? && lng.zero?

    Row.new(f[0], f[1], f[2], f[3], lat, lng, f[7], f[8].presence&.downcase, f[10], population)
  end

  def upsert_places(rows)
    now = Time.current
    attrs = rows.map do |row|
      {
        canonical_key: canonical_key(row),
        name: row.name,
        normalized_name: Place.normalize_name(row.name),
        place_type: "city",
        country_code: row.country_code,
        admin_area: row.admin1.presence,
        latitude: row.lat,
        longitude: row.lng,
        population: row.population,
        importance_score: importance_score(row),
        source: "geonames",
        metadata: { "geonameid" => row.geonameid, "feature_code" => row.feature_code },
        created_at: now,
        updated_at: now,
      }
    end
    Place.upsert_all(attrs, unique_by: :canonical_key)
    @places += attrs.size
  end

  def upsert_aliases(rows)
    now = Time.current
    ids = Place.where(canonical_key: rows.map { |row| canonical_key(row) }).pluck(:canonical_key, :id).to_h
    attrs = rows.flat_map do |row|
      place_id = ids[canonical_key(row)]
      next [] if place_id.nil?

      alias_names(row).map do |name, normalized|
        {
          place_id: place_id,
          name: name,
          normalized_name: normalized,
          alias_type: "geonames",
          metadata: {},
          created_at: now,
          updated_at: now,
        }
      end
    end
    return if attrs.empty?

    # A place can list the same surface form twice across native/ascii/alternate
    # columns; the unique index would reject the whole batch.
    attrs.uniq! { |row| [ row[:place_id], row[:normalized_name] ] }
    PlaceAlias.upsert_all(attrs, unique_by: %i[place_id normalized_name])
    @aliases += attrs.size
  end

  # Native name, transliteration, and the file's own alternate names -- which
  # is what makes "Cologne"/"Köln"/"Kolonia" and Greek, Cyrillic and Arabic
  # forms all resolve to one place.
  def alias_names(row)
    candidates = [ row.name, row.asciiname, Place.ascii_name(row.name) ]
    candidates.concat(row.alternatenames.to_s.split(",")) if row.alternatenames.present?

    seen = {}
    candidates.each do |candidate|
      name = candidate.to_s.strip
      next if name.blank? || name.length < MIN_ALIAS_LENGTH

      normalized = Place.normalize_name(name)
      next if normalized.blank? || normalized.length < MIN_ALIAS_LENGTH
      next if seen.key?(normalized)

      seen[normalized] = name
      break if seen.size >= MAX_ALIASES_PER_PLACE
    end
    seen.map { |normalized, name| [ name, normalized ] }
  end

  def importance_score(row)
    log_pop = row.population.positive? ? Math.log10(row.population) : MIN_LOG_POP
    ratio = ((log_pop - MIN_LOG_POP) / (MAX_LOG_POP - MIN_LOG_POP)).clamp(0.0, 1.0)
    score = SCORE_FLOOR + (SCORE_CEILING - SCORE_FLOOR) * ratio
    score += CAPITAL_BONUS if row.feature_code == "PPLC"
    score += ADMIN_SEAT_BONUS if row.feature_code == "PPLA"
    score.round(4)
  end

  def canonical_key(row)
    "place:geonames:#{row.geonameid}"
  end
end
