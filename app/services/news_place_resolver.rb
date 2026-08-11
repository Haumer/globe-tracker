# One honest answer to "where did this happen".
#
# The clusterer used to resolve location as `context[:location_name] || event&.name`,
# and NewsEvent#name is the publisher. That is how 3,269 of 3,835 `occurred_at`
# relationships came to anchor an event to its own newspaper, and how 354 of the
# 630 `place` entities in the graph ended up being mastheads -- France 24,
# Guardian World, DW News. Anything derived from a place inherits that error,
# which is why OntologyV2InfrastructureImpactService had to grow a
# `publisher_location_name?` guard: a downstream patch for an upstream defect.
#
# This never reads `name`. It works only from the geocode_* columns, which
# record both what was resolved and how, and it refuses to answer rather than
# answer with a masthead.
class NewsPlaceResolver
  # Tiers at which geocode_place_name is a place. Below these it is a bare
  # country code ("CL"), or the publisher, so the name is not usable even though
  # the coordinate may be.
  LOCATED_PRECISIONS = %w[city place region airport].freeze

  # Bases that describe where the *newsroom* is, not where the story happened.
  # `source_country_hint` (27.2% of events) takes the publisher's country;
  # `publisher_domain` (6.9%) takes the domain's. Together they are just over a
  # third of all news coordinates, and for a Chilean paper covering Gaza they
  # place the event in Chile.
  PUBLISHER_BASES = %w[publisher_domain source_country_hint].freeze

  # Bases that only ever establish a country, however they were derived.
  COUNTRY_ONLY_BASES = %w[ai_country title_country_keyword].freeze

  Resolution = Struct.new(
    :tier, :name, :country_code, :latitude, :longitude, :precision, :basis, :confidence,
    keyword_init: true
  ) do
    def place? = tier == :place
    def country? = tier == :country
    def none? = tier == :none
    # Whether the resolution is good enough to anchor a graph node to.
    def usable? = tier != :none
    # Whether the coordinate reflects the story rather than the newsroom.
    def coordinate_trusted? = latitude.present? && longitude.present? && !PUBLISHER_BASES.include?(basis.to_s)
  end

  NONE = Resolution.new(tier: :none).freeze

  class << self
    # Accepts a NewsEvent, or anything answering the geocode_* readers. Returns
    # NONE for nil so callers never need a presence check first.
    def call(event)
      return NONE if event.blank?

      resolve(
        place_name: value(event, :geocode_place_name),
        country_code: value(event, :geocode_country_code),
        precision: value(event, :geocode_precision),
        basis: value(event, :geocode_basis),
        confidence: value(event, :geocode_confidence),
        latitude: value(event, :latitude),
        longitude: value(event, :longitude)
      )
    end

    def resolve(place_name: nil, country_code: nil, precision: nil, basis: nil,
                confidence: nil, latitude: nil, longitude: nil)
      basis = basis.to_s.presence
      precision = precision.to_s.presence
      code = normalize_country_code(country_code)

      shared = {
        country_code: code,
        latitude: numeric(latitude),
        longitude: numeric(longitude),
        precision: precision,
        basis: basis,
        confidence: confidence&.to_f,
      }

      if named_place?(place_name, precision, basis)
        return Resolution.new(tier: :place, name: place_name.to_s.strip, **shared)
      end

      # A country is a real answer, just a coarse one -- and it resolves to a
      # country entity that already exists rather than minting a new place.
      # Publisher-derived bases are excluded even here: the publisher's country
      # is not the story's country.
      if code.present? && !PUBLISHER_BASES.include?(basis)
        return Resolution.new(tier: :country, name: country_name(code), **shared)
      end

      Resolution.new(tier: :none, **shared)
    end

    # Country entities are already in the graph with their ISO codes, so a
    # country-tier resolution points at an existing node instead of creating a
    # parallel one. Memoized per process; the table changes at most daily.
    def country_name(code)
      return nil if code.blank?

      country_names[code] || fallback_country_names[code] || code.upcase
    end

    def reset_cache!
      @country_names = nil
      @fallback_country_names = nil
    end

    private

    def named_place?(place_name, precision, basis)
      return false if place_name.blank?
      return false unless LOCATED_PRECISIONS.include?(precision)
      return false if PUBLISHER_BASES.include?(basis)
      return false if COUNTRY_ONLY_BASES.include?(basis)

      # A two-letter value at a located precision is a country code that leaked
      # into the wrong column, not a place called "CL".
      place_name.to_s.strip.length > 2
    end

    def country_names
      @country_names ||= OntologyEntity.where(entity_type: "country")
        .where.not(country_code: nil)
        .pluck(:country_code, :canonical_name)
        .each_with_object({}) { |(code, name), memo| memo[code.to_s.downcase] ||= name }
    rescue ActiveRecord::StatementInvalid
      # The resolver is used from the clusterer, which runs during migrations.
      {}
    end

    def fallback_country_names
      @fallback_country_names ||= NewsGeocodable::COUNTRY_NAME_MAP
        .each_with_object({}) { |(name, code), memo| memo[code.to_s.downcase] ||= name.split.map(&:capitalize).join(" ") }
    end

    def normalize_country_code(value)
      code = value.to_s.strip.downcase
      code.length == 2 ? code : nil
    end

    def numeric(value)
      return nil if value.blank?

      value.to_f
    end

    def value(record, attribute)
      record.public_send(attribute) if record.respond_to?(attribute)
    end
  end
end
