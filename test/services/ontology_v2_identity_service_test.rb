require "test_helper"

class OntologyV2IdentityServiceTest < ActiveSupport::TestCase
  test "links state actor records to canonical country records" do
    actor = create_state_actor
    country = create_country

    result = OntologyV2IdentityService.sync(now: Time.utc(2026, 4, 11, 12, 0, 0))

    assert_equal 1, result.fetch(:actor_country_links)
    relationship = OntologyRelationship.find_by!(
      source_node: actor,
      target_node: country,
      relation_type: OntologyV2IdentityService::REPRESENTS_COUNTRY
    )

    assert_equal OntologyV2IdentityService::DERIVED_BY, relationship.derived_by
    assert_equal 0.95, relationship.confidence
    assert_equal "KWT", relationship.metadata["country_code_alpha3"]
    assert_empty result.dig(:health, :disconnected_state_actors)
  end

  test "resolves country named place records to canonical country records" do
    place = OntologyEntity.create!(
      canonical_key: "place:kuwait",
      entity_type: "place",
      canonical_name: "Kuwait",
      metadata: { "latitude" => 28.61, "longitude" => 77.21, "geo_precision" => "point" }
    )
    country = create_country

    result = OntologyV2IdentityService.sync(now: Time.utc(2026, 4, 11, 12, 0, 0))

    assert_equal 1, result.fetch(:place_country_links)
    relationship = OntologyRelationship.find_by!(
      source_node: place,
      target_node: country,
      relation_type: OntologyV2IdentityService::PLACE_RESOLVES_TO_COUNTRY
    )

    assert_equal 0.75, relationship.confidence
    assert_equal true, relationship.metadata["requires_geo_review"]
    assert_equal "canonical_name", relationship.metadata["match_method"]
    assert_empty result.dig(:health, :disconnected_country_named_places)
  end

  test "health report flags disconnected country actor and place duplicates before sync" do
    create_state_actor
    create_country
    OntologyEntity.create!(
      canonical_key: "place:kuwait",
      entity_type: "place",
      canonical_name: "Kuwait"
    )

    report = OntologyV2IdentityService.health_report

    assert_equal ["actor:state:kw"], report.fetch(:disconnected_state_actors).map { |row| row.fetch(:canonical_key) }
    assert_equal ["place:kuwait"], report.fetch(:disconnected_country_named_places).map { |row| row.fetch(:canonical_key) }
  end

  test "does not link generic place records without a country match" do
    create_country
    source_place = OntologyEntity.create!(
      canonical_key: "place:cbs-news",
      entity_type: "place",
      canonical_name: "CBS News"
    )

    OntologyV2IdentityService.sync

    assert_not OntologyRelationship.exists?(
      source_node: source_place,
      relation_type: OntologyV2IdentityService::PLACE_RESOLVES_TO_COUNTRY
    )
  end

  private

  def create_state_actor
    OntologyEntity.create!(
      canonical_key: "actor:state:kw",
      entity_type: "actor",
      canonical_name: "Kuwait",
      country_code: "KW",
      metadata: { "actor_type" => "state" }
    )
  end

  def create_country
    OntologyEntity.create!(
      canonical_key: "country:kwt",
      entity_type: "country",
      canonical_name: "Kuwait",
      country_code: "KW",
      metadata: { "country_code_alpha3" => "KWT" }
    )
  end
end
