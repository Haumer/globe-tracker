# Which registry entity, if any, does a piece of news text name?
#
# Phase 1.1-1.2 of the ontology v3 plan. Rings 0 (news events) and 3 (the supply
# chain graph) both work and share no edges: 93 clusters mention the Strait of
# Hormuz, the Hormuz entity carries 138 relationships out to 69 countries, and
# nothing joins them. The join is this: the name in the headline, resolved to the
# registry row it refers to.
#
# The filtering is the whole problem. 68,307 registry entities contribute 123,547
# surface forms, and a naive match against them produces `power_plant:That`,
# `port:POLICE` and `power_plant:JUST` -- real registry rows whose names happen to
# be English words. The plan's instruction is to filter on ambiguity rather than
# frequency, because a frequency cut steep enough to remove "Security" also
# removes "Hormuz" (93 of 2,249 clusters). So each test below asks a question
# about the *string*, never about how often it occurs.
class RegistryNameIndex
  # Everything with a physical location that the supply-chain graph can reason
  # about. Corridors are the ones the earlier prototype omitted, and they are the
  # ones that carry the chokepoint relationships.
  REGISTRY_TYPES = %w[corridor power_plant port airport military_base submarine_cable].freeze

  # A token appearing in more distinct registry names than this is describing a
  # category, not naming a thing: "international" is a component of 1,302 names,
  # "station" 1,671, "power" 3,466. Real names sit at the bottom of that scale --
  # hormuz, jazan, mandeb and bosphorus are each a component of exactly 1.
  GENERIC_COMPONENT_SPREAD = 12

  # Below this, a surface is initialese or a fragment rather than a name.
  MINIMUM_SURFACE_LENGTH = 4

  # Share of mid-sentence occurrences that must be capitalised for a single-token
  # surface to read as a name. Measured from the corpus rather than a stopword
  # list: "hormuz" is capitalised 91 times of 91, "police" 4 of 21, "just" 0 of 7.
  NAME_CAPITALISATION_RATIO = 0.9

  Match = Struct.new(:surface, :entity_id, :entity_type, :entity_name, :facility_named, keyword_init: true) do
    # Ports and power plants are overwhelmingly named after the settlement they
    # sit in, so matching one proves a place was mentioned, not that the asset
    # was: "NAGASAKI" is a real port, but a story about the bombing anniversary
    # is not about that port, and neither is a Hong Kong property story about the
    # container terminal. What separates the two is whether the name identifies a
    # facility ("Los Angeles International Airport", "KHARG ISLAND OIL TERMINAL")
    # or is a bare toponym ("HONG KONG"). Corridors are exempt: they are curated,
    # twelve rows, and a corridor is never named after a city.
    #
    # Everything else is a candidate, not a conclusion. Phase 1.4 -- narrow
    # deterministically, then have the model pick one or none -- is what settles
    # them; until it exists they are reported and not written.
    def confident? = entity_type == "corridor" || facility_named
  end

  class << self
    def call(text, corpus: nil)
      new(corpus: corpus).match(text)
    end

    # Titles carry a trailing " - Publisher" or " | Publisher". Left in, the
    # masthead is matched like any other text, which is how "Bangkok Post" became
    # the port of Bangkok on a story about New Zealand, and "Barron's" a power
    # plant on a story about Hormuz. The same publisher-as-place defect
    # NewsPlaceResolver exists to stop, one layer further out.
    def strip_publisher(title)
      title.to_s.sub(/\s+[-|–—]\s+[^-|–—]{2,40}\s*\z/, "")
    end

    def normalize(text)
      text.to_s.downcase.gsub(/[^a-z0-9 ]/, " ").squeeze(" ").strip
    end
  end

  # corpus: the text the capitalisation profile is learned from. Defaults to the
  # recent cluster titles, which is the same distribution the matcher runs over.
  def initialize(corpus: nil)
    @corpus = corpus
  end

  def match(text)
    normalized = self.class.normalize(self.class.strip_publisher(text))
    return [] if normalized.blank?

    found = ngrams(normalized).uniq.select { |gram| usable.key?(gram) }
    # Longest match wins. "strait of hormuz" and "hormuz" both hit; reporting
    # both would double-count one mention of one place.
    found = found.reject { |gram| found.any? { |other| other != gram && other.include?(gram) } }

    found.map do |gram|
      id = usable.fetch(gram)
      type, name = entity_meta.fetch(id)
      Match.new(surface: gram, entity_id: id, entity_type: type, entity_name: name,
                facility_named: facility_named?(gram))
    end
  end

  # A facility type is what a registry name *ends* with -- "... International
  # Airport", "... OIL TERMINAL", "... Power Station". Name particles are common
  # too ("los", "st", "north", "da") but they lead, never trail, which is what
  # separates "LOS ANGELES INTERNATIONAL AIRPORT" from the port called "LOS
  # ANGELES". Testing any token instead of the last one admits both.
  def facility_named?(surface)
    trailing_token_spread.fetch(surface.split.last, 0) > GENERIC_COMPONENT_SPREAD
  end

  # Surfaces that survived every test, mapped to the one entity they name.
  def usable
    @usable ||= build_usable
  end

  # The other registry assets sitting at the same place as a match.
  #
  # A town's refinery, port and airport share its name in spelling variants the
  # index cannot bridge: the Jazan refinery is "JAZAN", the port beside it is
  # "JIZAN", and a headline using one spelling reaches only one of them. So
  # "Saudi Aramco refinery erupts in flames in Jizan" offered the model nothing
  # but a port, and it correctly answered none.
  #
  # Deterministic narrowing of the kind the plan asks for: co-location is a fact
  # about coordinates, and it turns the question from "is this about the port"
  # into "which of these three is it", which the text usually answers outright by
  # saying refinery. Wrong neighbours are cheap here because the model still has
  # to pick, and none remains available.
  # Does the text talk about a facility at all -- a refinery, a port, a reactor?
  #
  # Deliberately a short hand-checked list rather than something derived. The
  # obvious derivation, "tokens that end registry names", was tried and is far
  # too permissive: 123k names end in enough ordinary words that 20 of 22 sample
  # headlines passed, including every one the resolver had got wrong. This list
  # is twenty words and can be read in full, which is the same argument the plan
  # makes for curating twelve corridors by hand.
  #
  # Without this gate a story that merely mentions a city gets handed that city's
  # port and airport as options, and the model takes one: migration policy in
  # Ceuta became the port of Ceuta, a SWAT team at a school became a military
  # base, and a strike on Kyiv became a power plant named Kiev.
  FACILITY_WORDS = %w[
    refinery refineries plant plants reactor npp nuclear turbine
    port ports harbour harbor terminal dock airport airfield airbase
    pipeline dam grid substation station facility
  ].to_set.freeze

  def facility_mentioned?(text)
    self.class.normalize(self.class.strip_publisher(text))
      .split.any? { |token| FACILITY_WORDS.include?(token) }
  end

  def co_located(match, radius_km: 25.0, limit: 6)
    origin = OntologyEntity.find_by(id: match.entity_id)
    lat, lng = coordinates_of(origin)
    return [] unless lat && lng

    located_entities.filter_map do |id, type, name, other_lat, other_lng|
      next if id == match.entity_id
      next if haversine_km(lat, lng, other_lat, other_lng) > radius_km

      Match.new(surface: match.surface, entity_id: id, entity_type: type,
                entity_name: name, facility_named: false)
    end.first(limit)
  end

  def rejections
    usable
    @rejections
  end

  private

  def build_usable
    @rejections = Hash.new(0)
    keep = {}

    surfaces.each do |surface, entity_ids|
      single_token = !surface.include?(" ")

      if surface.length < MINIMUM_SURFACE_LENGTH
        @rejections[:too_short] += 1
      elsif surface.match?(/\A[0-9 ]+\z/)
        @rejections[:numeric] += 1
      elsif entity_ids.size > 1
        # The plan's first test: does the string map to one entity or many.
        @rejections[:ambiguous_multi_entity] += 1
      elsif country_surfaces.include?(surface)
        # A story about France is not a story about the power plant named France.
        @rejections[:is_a_country_name] += 1
      elsif single_token && !name_like?(surface)
        @rejections[:common_word] += 1
      elsif surface.split.all? { |token| token_spread.fetch(token, 0) > GENERIC_COMPONENT_SPREAD }
        # Every token is a category word, so the name describes a kind of thing
        # rather than one thing: the registry holds a military base actually
        # called "Military Camp", which otherwise matches any story mentioning
        # one. A real name carries at least one distinctive token -- "kharg" in
        # KHARG ISLAND OIL TERMINAL, "angeles" in Los Angeles International
        # Airport. Subsumes the single-token case.
        @rejections[:generic_component] += 1
      else
        keep[surface] = entity_ids.first
      end
    end

    keep
  end

  def surfaces
    @surfaces ||= begin
      index = Hash.new { |hash, key| hash[key] = [] }

      entity_meta.each do |id, (_type, name)|
        surface = self.class.normalize(name)
        index[surface] << id if surface.present?
      end

      OntologyEntityAlias
        .joins(:ontology_entity)
        .where(ontology_entities: { entity_type: REGISTRY_TYPES })
        .pluck(:ontology_entity_id, :name)
        .each do |id, name|
          next unless entity_meta.key?(id)

          surface = self.class.normalize(name)
          index[surface] << id if surface.present?
        end

      index.transform_values(&:uniq)
    end
  end

  def entity_meta
    @entity_meta ||= OntologyEntity
      .where(entity_type: REGISTRY_TYPES)
      .pluck(:id, :entity_type, :canonical_name)
      .each_with_object({}) { |(id, type, name), memo| memo[id] = [type, name] }
  end

  def country_surfaces
    @country_surfaces ||= begin
      names = OntologyEntity.where(entity_type: "country").pluck(:canonical_name)
      names += OntologyEntityAlias.joins(:ontology_entity)
        .where(ontology_entities: { entity_type: "country" }).pluck(:name)
      names.map { |name| self.class.normalize(name) }.reject(&:blank?).to_set
    end
  end

  # How many distinct registry names each token is a component of.
  def token_spread
    @token_spread ||= surfaces.keys.each_with_object(Hash.new(0)) do |surface, memo|
      surface.split.uniq.each { |token| memo[token] += 1 }
    end
  end

  def coordinates_of(entity)
    return [nil, nil] unless entity

    [entity.metadata["latitude"]&.to_f, entity.metadata["longitude"]&.to_f]
  end

  # Registry entities that carry a coordinate, as flat tuples. Loaded once per
  # index; co_located is called only for the candidate tier, which is small.
  def located_entities
    @located_entities ||= OntologyEntity
      .where(entity_type: REGISTRY_TYPES)
      .where("metadata->>'latitude' IS NOT NULL AND metadata->>'longitude' IS NOT NULL")
      .pluck(:id, :entity_type, :canonical_name,
             Arel.sql("(metadata->>'latitude')::float"), Arel.sql("(metadata->>'longitude')::float"))
  end

  def haversine_km(lat1, lng1, lat2, lng2)
    radians = Math::PI / 180.0
    dlat = (lat2 - lat1) * radians
    dlng = (lng2 - lng1) * radians
    a = Math.sin(dlat / 2)**2 +
      Math.cos(lat1 * radians) * Math.cos(lat2 * radians) * Math.sin(dlng / 2)**2
    6371.0 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end

  # How many distinct registry names end with each token.
  def trailing_token_spread
    @trailing_token_spread ||= surfaces.keys.each_with_object(Hash.new(0)) do |surface, memo|
      last = surface.split.last
      memo[last] += 1 if last
    end
  end

  def name_like?(token)
    capitalised, lowercased = capitalisation_profile.fetch(token, [0, 0])
    seen = capitalised + lowercased
    # Never seen in the corpus means nothing argues against it being a name.
    return true if seen.zero?

    (capitalised.to_f / seen) >= NAME_CAPITALISATION_RATIO
  end

  # Counts each token's mid-sentence capitalisation. The first word of a title is
  # skipped because its capitalisation is grammatical, not evidence.
  def capitalisation_profile
    @capitalisation_profile ||= corpus.each_with_object({}) do |text, memo|
      text.to_s.split(/\s+/).each_with_index do |word, position|
        next if position.zero?

        clean = word.gsub(/[^A-Za-z]/, "")
        next if clean.length < 3

        entry = memo[clean.downcase] ||= [0, 0]
        entry[clean[0] == clean[0].upcase ? 0 : 1] += 1
      end
    end
  end

  def corpus
    @corpus ||= NewsStoryCluster.where("last_seen_at >= ?", 21.days.ago).pluck(:canonical_title)
  end

  def ngrams(text, max: 5)
    words = text.split
    (1..max).flat_map { |size| words.each_cons(size).map { |slice| slice.join(" ") } }
  end
end
