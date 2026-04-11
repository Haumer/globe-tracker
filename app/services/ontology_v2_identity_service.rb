class OntologyV2IdentityService
  DERIVED_BY = "ontology_v2_identity_v1".freeze
  REPRESENTS_COUNTRY = "represents_country".freeze
  PLACE_RESOLVES_TO_COUNTRY = "place_resolves_to_country".freeze
  ACTOR_ENTITY_TYPE = "actor".freeze
  COUNTRY_ENTITY_TYPE = "country".freeze
  PLACE_ENTITY_TYPE = "place".freeze
  STATE_ACTOR_KEY_PREFIX = "actor:state:".freeze

  class << self
    def sync(now: Time.current)
      new(now: now).sync
    end

    def health_report
      new.health_report
    end

    def country_for_code(code)
      new.country_for_code(code)
    end

    def country_for_name(name)
      new.country_for_name(name)
    end
  end

  def initialize(now: Time.current)
    @now = now
  end

  def sync
    result = nil

    ActiveRecord::Base.transaction do
      result = {
        actor_country_links: sync_state_actor_country_links,
        place_country_links: sync_place_country_links,
      }
      result[:health] = health_report
    end

    result
  end

  def health_report
    actor_links = identity_relationship_scope(REPRESENTS_COUNTRY)
    place_links = identity_relationship_scope(PLACE_RESOLVES_TO_COUNTRY)

    {
      countries: country_scope.count,
      state_actors: state_actor_scope.count,
      state_actor_country_links: actor_links.count,
      place_country_links: place_links.count,
      disconnected_state_actors: disconnected_state_actors(actor_links),
      disconnected_country_named_places: disconnected_country_named_places(place_links),
      ambiguous_country_codes: ambiguous_country_codes,
      ambiguous_country_names: ambiguous_country_names,
    }
  end

  def country_for_code(code)
    return if code.blank?

    country_entities_by_code[code.to_s.upcase]
  end

  def country_for_name(name)
    country_entities_by_name[normalize_name(name)]
  end

  private

  attr_reader :now

  def sync_state_actor_country_links
    count = 0

    state_actor_scope.find_each do |actor|
      country = country_for_actor(actor)
      next if country.blank?

      delete_stale_identity_links(actor, REPRESENTS_COUNTRY, keep_target: country)
      OntologySyncSupport.upsert_relationship(
        source_node: actor,
        target_node: country,
        relation_type: REPRESENTS_COUNTRY,
        confidence: 0.95,
        derived_by: DERIVED_BY,
        explanation: "#{actor.canonical_name} is modeled as the state actor for #{country.canonical_name}.",
        metadata: identity_metadata(country).merge(
          "match_method" => "country_code",
          "synced_at" => now.iso8601
        )
      )
      count += 1
    end

    count
  end

  def sync_place_country_links
    count = 0
    country_by_name = country_entities_by_name

    country_named_place_scope.each do |place|
      country = country_by_name[normalize_name(place.canonical_name)]
      next if country.blank?

      delete_stale_identity_links(place, PLACE_RESOLVES_TO_COUNTRY, keep_target: country)
      OntologySyncSupport.upsert_relationship(
        source_node: place,
        target_node: country,
        relation_type: PLACE_RESOLVES_TO_COUNTRY,
        confidence: 0.75,
        derived_by: DERIVED_BY,
        explanation: "#{place.canonical_name} resolves to the country object #{country.canonical_name}; verify coordinates before using as a point location.",
        metadata: identity_metadata(country).merge(
          "match_method" => "canonical_name",
          "requires_geo_review" => true,
          "synced_at" => now.iso8601
        )
      )
      count += 1
    end

    count
  end

  def stale_identity_links(source, relation_type, keep_target:)
    OntologyRelationship
      .where(source_node: source, relation_type: relation_type, derived_by: DERIVED_BY)
      .where.not(target_node_type: keep_target.class.name, target_node_id: keep_target.id)
  end

  def delete_stale_identity_links(source, relation_type, keep_target:)
    stale_ids = stale_identity_links(source, relation_type, keep_target: keep_target).pluck(:id)
    return if stale_ids.empty?

    OntologyRelationshipEvidence.where(ontology_relationship_id: stale_ids).delete_all
    OntologyRelationship.where(id: stale_ids).delete_all
  end

  def country_for_actor(actor)
    country_codes_for(actor).lazy.filter_map { |code| country_entities_by_code[code] }.first ||
      country_entities_by_name[normalize_name(actor.canonical_name)]
  end

  def country_codes_for(actor)
    [
      actor.country_code,
      actor.metadata["country_code"],
      actor.metadata["country_code_alpha3"],
      actor.metadata["iso2"],
      actor.metadata["iso3"],
      actor.canonical_key.delete_prefix(STATE_ACTOR_KEY_PREFIX),
    ].compact_blank.map { |code| code.to_s.upcase }.uniq
  end

  def identity_metadata(country)
    {
      "country_entity_id" => country.id,
      "country_canonical_key" => country.canonical_key,
      "country_code" => country.country_code,
      "country_code_alpha3" => country.metadata["country_code_alpha3"] || country.canonical_key.to_s.split(":").last&.upcase,
    }.compact
  end

  def disconnected_state_actors(actor_links)
    linked_actor_ids = actor_links.pluck(:source_node_id).index_with(true)

    state_actor_scope.filter_map do |actor|
      next if linked_actor_ids[actor.id]

      {
        id: actor.id,
        canonical_key: actor.canonical_key,
        canonical_name: actor.canonical_name,
        country_code: actor.country_code,
        expected_country_key: country_for_actor(actor)&.canonical_key,
      }
    end
  end

  def disconnected_country_named_places(place_links)
    linked_place_ids = place_links.pluck(:source_node_id).index_with(true)

    country_named_place_scope.filter_map do |place|
      next if linked_place_ids[place.id]

      {
        id: place.id,
        canonical_key: place.canonical_key,
        canonical_name: place.canonical_name,
        expected_country_key: country_entities_by_name[normalize_name(place.canonical_name)]&.canonical_key,
      }
    end
  end

  def ambiguous_country_codes
    country_entities_by_all_codes.filter_map do |code, countries|
      next if countries.size < 2

      {
        code: code,
        country_keys: countries.map(&:canonical_key).sort,
      }
    end.sort_by { |row| row.fetch(:code) }
  end

  def ambiguous_country_names
    country_scope.group_by { |country| normalize_name(country.canonical_name) }.filter_map do |name, countries|
      next if name.blank? || countries.size < 2

      {
        name: name,
        country_keys: countries.map(&:canonical_key).sort,
      }
    end.sort_by { |row| row.fetch(:name) }
  end

  def country_entities_by_code
    @country_entities_by_code ||= country_entities_by_all_codes.each_with_object({}) do |(code, countries), memo|
      memo[code] = countries.first if countries.size == 1
    end
  end

  def country_entities_by_all_codes
    @country_entities_by_all_codes ||= country_scope.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |country, memo|
      country_codes_for_country(country).each { |code| memo[code] << country }
    end
  end

  def country_codes_for_country(country)
    [
      country.country_code,
      country.metadata["country_code"],
      country.metadata["country_code_alpha3"],
      country.metadata["iso2"],
      country.metadata["iso3"],
      country.canonical_key.to_s.split(":").last,
    ].compact_blank.map { |code| code.to_s.upcase }.uniq
  end

  def country_entities_by_name
    @country_entities_by_name ||= country_scope.each_with_object({}) do |country, memo|
      normalized_name = normalize_name(country.canonical_name)
      memo[normalized_name] ||= country if normalized_name.present?
    end
  end

  def country_named_place_scope
    OntologyEntity.where(entity_type: PLACE_ENTITY_TYPE).select do |place|
      country_entities_by_name.key?(normalize_name(place.canonical_name))
    end
  end

  def identity_relationship_scope(relation_type)
    OntologyRelationship.where(
      source_node_type: "OntologyEntity",
      target_node_type: "OntologyEntity",
      relation_type: relation_type,
      derived_by: DERIVED_BY
    )
  end

  def state_actor_scope
    OntologyEntity
      .where(entity_type: ACTOR_ENTITY_TYPE)
      .where("canonical_key LIKE ? OR metadata->>'actor_type' = ?", "#{STATE_ACTOR_KEY_PREFIX}%", "state")
  end

  def country_scope
    OntologyEntity.where(entity_type: COUNTRY_ENTITY_TYPE)
  end

  def normalize_name(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end
end
