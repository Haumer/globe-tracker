require "test_helper"

class SupplyChainOntologySyncServiceTest < ActiveSupport::TestCase
  setup do
    CountryProfile.delete_all
    CountrySectorProfile.delete_all
    SectorInputProfile.delete_all
    CountryCommodityDependency.delete_all
    CountryChokepointExposure.delete_all
    SourceFeedStatus.delete_all

    OntologyRelationshipEvidence.delete_all
    OntologyRelationship.delete_all
    OntologyEntityAlias.delete_all
    OntologyEntity.delete_all

    CountryProfile.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      latest_year: 2024,
      gdp_nominal_usd: 4_200_000_000_000,
      imports_goods_services_pct_gdp: 21.6,
      energy_imports_net_pct_energy_use: 87.4,
      metadata: { "top_sectors" => [{ "sector_key" => "manufacturing", "sector_name" => "Manufacturing", "share_pct" => 19.3, "rank" => 1 }] },
      fetched_at: Time.current
    )

    CountrySectorProfile.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      sector_key: "manufacturing",
      sector_name: "Manufacturing",
      period_year: 2024,
      share_pct: 19.3,
      rank: 1,
      metadata: {},
      fetched_at: Time.current
    )

    SectorInputProfile.create!(
      scope_key: "global",
      sector_key: "manufacturing",
      sector_name: "Manufacturing",
      input_kind: "commodity",
      input_key: "helium",
      input_name: "Helium",
      period_year: 2024,
      coefficient: 0.42,
      rank: 1,
      metadata: {},
      fetched_at: Time.current
    )

    CountryCommodityDependency.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      period_start: Date.new(2025, 1, 1),
      period_end: Date.new(2025, 1, 31),
      period_type: "month",
      import_value_usd: 2_000_000_000,
      supplier_count: 2,
      top_partner_country_code: "AE",
      top_partner_country_code_alpha3: "ARE",
      top_partner_country_name: "United Arab Emirates",
      top_partner_share_pct: 75.0,
      concentration_hhi: 0.625,
      import_share_gdp_pct: 0.0476,
      dependency_score: 0.64,
      metadata: {},
      fetched_at: Time.current
    )

    CountryChokepointExposure.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "hormuz",
      chokepoint_name: "Strait of Hormuz",
      exposure_score: 0.62,
      dependency_score: 0.64,
      supplier_share_pct: 100.0,
      rationale: "Japan is exposed to Hormuz through Gulf crude imports.",
      metadata: { "supporting_partner_codes" => ["ARE", "SAU"] },
      fetched_at: Time.current
    )
    CountryChokepointExposure.create!(
      country_code: "JP",
      country_code_alpha3: "JPN",
      country_name: "Japan",
      commodity_key: "oil_crude",
      commodity_name: "Crude Oil",
      chokepoint_key: "malacca",
      chokepoint_name: "Strait of Malacca",
      exposure_score: 0.38,
      dependency_score: 0.64,
      supplier_share_pct: 100.0,
      rationale: "Japan is exposed to Malacca on East Asia energy routes.",
      metadata: { "supporting_partner_codes" => ["ARE", "SAU"] },
      fetched_at: Time.current
    )
  end

  test "projects supply-chain profiles into ontology entities and relationships" do
    result = SupplyChainOntologySyncService.sync(force_normalize: false)

    assert_operator result[:countries], :>=, 1
    assert_operator result[:commodities], :>=, SupplyChainCatalog::STRATEGIC_COMMODITIES.size
    assert_operator result[:flow_dependencies], :>=, 1

    japan = OntologyEntity.find_by!(canonical_key: "country:jpn")
    manufacturing = OntologyEntity.find_by!(canonical_key: "sector:jpn:manufacturing")
    crude_oil = OntologyEntity.find_by!(canonical_key: "commodity:oil_crude")
    helium = OntologyEntity.find_by!(canonical_key: "commodity:helium")
    hormuz = OntologyEntity.find_by!(canonical_key: "corridor:chokepoint:hormuz")

    import_relationship = OntologyRelationship.find_by!(
      source_node: crude_oil,
      target_node: japan,
      relation_type: "import_dependency",
      derived_by: SupplyChainOntologySyncService::DERIVED_BY
    )
    assert_equal "dependency_profile", import_relationship.ontology_relationship_evidences.first.evidence_role

    production_relationship = OntologyRelationship.find_by!(
      source_node: helium,
      target_node: manufacturing,
      relation_type: "production_dependency",
      derived_by: SupplyChainOntologySyncService::DERIVED_BY
    )
    assert_includes production_relationship.explanation, "Japan Manufacturing"

    economic_relationship = OntologyRelationship.find_by!(
      source_node: manufacturing,
      target_node: japan,
      relation_type: "economic_profile",
      derived_by: SupplyChainOntologySyncService::DERIVED_BY
    )
    assert_operator economic_relationship.confidence, :>=, 0.4

    exposure_relationship = OntologyRelationship.find_by!(
      source_node: hormuz,
      target_node: japan,
      relation_type: "chokepoint_exposure",
      derived_by: SupplyChainOntologySyncService::DERIVED_BY
    )
    assert_includes exposure_relationship.explanation, "Japan"

    flow_relationship = OntologyRelationship.find_by!(
      source_node: hormuz,
      target_node: crude_oil,
      relation_type: "flow_dependency",
      derived_by: SupplyChainOntologySyncService::DERIVED_BY
    )
    assert_includes flow_relationship.explanation, "Crude Oil"

    status = SourceFeedStatus.find_by(feed_key: "derived_supply_chain_ontology:supply-chain-ontology")
    assert_equal "success", status.status
  end

  test "projects baseline strategic commodities and chokepoint flows without dependency rows" do
    CountryCommodityDependency.delete_all
    CountryChokepointExposure.delete_all
    SectorInputProfile.delete_all

    result = SupplyChainOntologySyncService.sync(force_normalize: false)

    assert_operator result[:commodities], :>=, SupplyChainCatalog::STRATEGIC_COMMODITIES.size

    crude_oil = OntologyEntity.find_by!(canonical_key: "commodity:oil_crude")
    hormuz = OntologyEntity.find_by!(canonical_key: "corridor:chokepoint:hormuz")
    flow_relationship = OntologyRelationship.find_by!(
      source_node: hormuz,
      target_node: crude_oil,
      relation_type: "flow_dependency",
      derived_by: SupplyChainOntologySyncService::DERIVED_BY
    )

    assert_includes flow_relationship.explanation, "Largest oil chokepoint globally"
    assert_equal "global_chokepoint_flow", flow_relationship.metadata.fetch("source_kind")
  end
end
