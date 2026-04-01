class SupplyChainOntologySyncService
  DERIVED_BY = "supply_chain_ontology_sync_v1".freeze
  COUNTRY_ENTITY_TYPE = "country".freeze
  SECTOR_ENTITY_TYPE = "sector".freeze
  INPUT_ENTITY_TYPE = "input".freeze
  MAX_COUNTRY_SECTORS = 4
  MAX_SECTOR_INPUTS = 5

  SOURCE_STATUS = {
    provider: "derived_supply_chain_ontology",
    display_name: "Supply Chain Ontology",
    feed_kind: "ontology",
    endpoint_url: nil,
  }.freeze

  class << self
    def sync(force_normalize: false, now: Time.current)
      new(force_normalize: force_normalize, now: now).sync
    end

    alias sync_recent sync
  end

  def initialize(force_normalize:, now:)
    @force_normalize = force_normalize
    @now = now
    @country_entities = {}
    @sector_entities = {}
    @commodity_entities = {}
    @input_entities = {}
    @chokepoint_entities = {}
  end

  def sync
    SupplyChainNormalizationService.refresh_if_stale(force: @force_normalize)

    result = nil

    ActiveRecord::Base.transaction do
      purge_existing_relationships!

      sync_country_entities
      sync_sector_entities
      sync_commodity_entities

      result = {
        countries: @country_entities.size,
        sectors: @sector_entities.size,
        commodities: @commodity_entities.size,
        economic_profiles: sync_economic_profile_relationships,
        import_dependencies: sync_import_dependency_relationships,
        production_dependencies: sync_production_dependency_relationships,
        chokepoint_exposures: sync_chokepoint_exposure_relationships,
        flow_dependencies: sync_structural_flow_dependencies,
      }
    end

    SourceFeedStatusRecorder.record(
      **SOURCE_STATUS,
      status: "success",
      records_fetched: source_record_count,
      records_stored: result.values.sum,
      metadata: result,
      occurred_at: @now
    )

    result
  rescue StandardError => e
    SourceFeedStatusRecorder.record(
      **SOURCE_STATUS,
      status: "error",
      error_message: e.message,
      occurred_at: Time.current
    )
    Rails.logger.error("SupplyChainOntologySyncService: #{e.message}")
    raise
  end

  private

  def source_record_count
    CountryProfile.count +
      CountrySectorProfile.count +
      SectorInputProfile.count +
      CountryCommodityDependency.count +
      CountryChokepointExposure.count
  end

  def purge_existing_relationships!
    relationship_ids = OntologyRelationship.where(derived_by: DERIVED_BY).pluck(:id)
    return if relationship_ids.empty?

    OntologyRelationshipEvidence.where(ontology_relationship_id: relationship_ids).delete_all
    OntologyRelationship.where(id: relationship_ids).delete_all
  end

  def sync_country_entities
    country_profiles.each do |profile|
      entity = OntologySyncSupport.upsert_entity(
        canonical_key: country_entity_key(profile.country_code_alpha3),
        entity_type: COUNTRY_ENTITY_TYPE,
        canonical_name: profile.country_name,
        country_code: profile.country_code,
        metadata: {
          "description" => country_description(profile),
          "country_code_alpha3" => profile.country_code_alpha3,
          "latest_year" => profile.latest_year,
          "gdp_nominal_usd" => profile.gdp_nominal_usd&.to_f,
          "gdp_per_capita_usd" => profile.gdp_per_capita_usd&.to_f,
          "population_total" => profile.population_total&.to_f,
          "imports_goods_services_pct_gdp" => profile.imports_goods_services_pct_gdp&.to_f,
          "exports_goods_services_pct_gdp" => profile.exports_goods_services_pct_gdp&.to_f,
          "energy_imports_net_pct_energy_use" => profile.energy_imports_net_pct_energy_use&.to_f,
          "top_sectors" => profile.metadata["top_sectors"],
        }.compact
      )

      OntologySyncSupport.upsert_alias(entity, profile.country_name, alias_type: "official")
      OntologySyncSupport.upsert_alias(entity, profile.country_code_alpha3, alias_type: "code")
      OntologySyncSupport.upsert_alias(entity, profile.country_code, alias_type: "code")

      @country_entities[profile.country_code_alpha3] = entity
    end
  end

  def sync_sector_entities
    country_sector_profiles.each do |profile|
      entity = OntologySyncSupport.upsert_entity(
        canonical_key: sector_entity_key(profile.country_code_alpha3, profile.sector_key),
        entity_type: SECTOR_ENTITY_TYPE,
        canonical_name: "#{profile.country_name} #{profile.sector_name}",
        country_code: profile.country_code,
        metadata: {
          "description" => "#{profile.sector_name} contributes #{profile.share_pct.to_f.round(1)}% of #{profile.country_name} GDP.",
          "country_code_alpha3" => profile.country_code_alpha3,
          "country_name" => profile.country_name,
          "sector_key" => profile.sector_key,
          "sector_name" => profile.sector_name,
          "share_pct" => profile.share_pct&.to_f,
          "rank" => profile.rank,
          "period_year" => profile.period_year,
        }.compact
      )

      OntologySyncSupport.upsert_alias(entity, profile.sector_name, alias_type: "sector")
      @sector_entities[[profile.country_code_alpha3, profile.sector_key]] = entity
    end
  end

  def sync_commodity_entities
    commodity_pairs.each do |commodity_key, commodity_name|
      entity = OntologySyncSupport.upsert_entity(
        canonical_key: commodity_entity_key(commodity_key),
        entity_type: "commodity",
        canonical_name: commodity_name,
        metadata: {
          "description" => "#{commodity_name} is tracked as a strategic supply-chain commodity.",
          "commodity_key" => commodity_key,
          "strategic" => true,
        }
      )

      OntologySyncSupport.upsert_alias(entity, commodity_name, alias_type: "official")
      @commodity_entities[commodity_key] = entity
    end
  end

  def sync_economic_profile_relationships
    country_sector_profiles.count do |profile|
      source = @sector_entities[[profile.country_code_alpha3, profile.sector_key]]
      target = @country_entities[profile.country_code_alpha3]
      next false if source.blank? || target.blank?

      relationship = OntologySyncSupport.upsert_relationship(
        source_node: source,
        target_node: target,
        relation_type: "economic_profile",
        confidence: confidence_from_share(profile.share_pct),
        derived_by: DERIVED_BY,
        explanation: "#{profile.sector_name} is a major economic channel inside #{profile.country_name}, contributing #{profile.share_pct.to_f.round(1)}% of GDP.",
        metadata: {
          "country_code_alpha3" => profile.country_code_alpha3,
          "sector_key" => profile.sector_key,
          "share_pct" => profile.share_pct&.to_f,
          "rank" => profile.rank,
          "period_year" => profile.period_year,
        }.compact
      )
      attach_evidence(relationship, profile, evidence_role: "sector_profile", confidence: confidence_from_share(profile.share_pct))
      true
    end
  end

  def sync_import_dependency_relationships
    country_commodity_dependencies.count do |dependency|
      source = @commodity_entities[dependency.commodity_key]
      target = @country_entities[dependency.country_code_alpha3]
      next false if source.blank? || target.blank?

      relationship = OntologySyncSupport.upsert_relationship(
        source_node: source,
        target_node: target,
        relation_type: "import_dependency",
        confidence: confidence_from_score(dependency.dependency_score),
        derived_by: DERIVED_BY,
        explanation: import_dependency_explanation(dependency),
        metadata: {
          "country_code_alpha3" => dependency.country_code_alpha3,
          "commodity_key" => dependency.commodity_key,
          "dependency_score" => dependency.dependency_score&.to_f,
          "import_share_gdp_pct" => dependency.import_share_gdp_pct&.to_f,
          "top_partner_share_pct" => dependency.top_partner_share_pct&.to_f,
          "supplier_count" => dependency.supplier_count,
        }.compact
      )
      attach_evidence(relationship, dependency, evidence_role: "dependency_profile", confidence: confidence_from_score(dependency.dependency_score))
      true
    end
  end

  def sync_production_dependency_relationships
    country_sector_profiles.sum do |sector_profile|
      sector_entity = @sector_entities[[sector_profile.country_code_alpha3, sector_profile.sector_key]]
      next 0 if sector_entity.blank?

      applicable_inputs_for(sector_profile.country_code_alpha3, sector_profile.sector_key).count do |input_profile|
        source = input_entity_for_profile(input_profile)
        next false if source.blank?

        relationship = OntologySyncSupport.upsert_relationship(
          source_node: source,
          target_node: sector_entity,
          relation_type: "production_dependency",
          confidence: confidence_from_coefficient(input_profile.coefficient),
          derived_by: DERIVED_BY,
          explanation: "#{display_name_for_input_profile(input_profile)} is an input dependency for #{sector_profile.country_name} #{sector_profile.sector_name}.",
          metadata: {
            "country_code_alpha3" => sector_profile.country_code_alpha3,
            "sector_key" => sector_profile.sector_key,
            "input_kind" => input_profile.input_kind,
            "input_key" => input_profile.input_key,
            "coefficient" => input_profile.coefficient&.to_f,
            "scope_key" => input_profile.scope_key,
          }.compact
        )
        attach_evidence(relationship, input_profile, evidence_role: "input_profile", confidence: confidence_from_coefficient(input_profile.coefficient))
        true
      end
    end
  end

  def sync_chokepoint_exposure_relationships
    country_chokepoint_exposures
      .group_by { |row| [row.country_code_alpha3, row.chokepoint_key] }
      .count do |(country_code_alpha3, chokepoint_key), exposures|
        source = chokepoint_entity_for(chokepoint_key)
        target = @country_entities[country_code_alpha3]
        next false if source.blank? || target.blank?

        top_exposures = exposures.sort_by { |row| -row.exposure_score.to_f }
        relationship = OntologySyncSupport.upsert_relationship(
          source_node: source,
          target_node: target,
          relation_type: "chokepoint_exposure",
          confidence: confidence_from_score(top_exposures.first.exposure_score),
          derived_by: DERIVED_BY,
          explanation: chokepoint_exposure_explanation(source.canonical_name, target.canonical_name, top_exposures),
          metadata: {
            "country_code_alpha3" => country_code_alpha3,
            "chokepoint_key" => chokepoint_key,
            "commodities" => top_exposures.map(&:commodity_key),
            "max_exposure_score" => top_exposures.map { |row| row.exposure_score.to_f }.max,
          }
        )
        top_exposures.first(3).each do |exposure|
          attach_evidence(relationship, exposure, evidence_role: "exposure_profile", confidence: confidence_from_score(exposure.exposure_score))
        end
        true
      end
  end

  def sync_structural_flow_dependencies
    country_chokepoint_exposures
      .group_by { |row| [row.chokepoint_key, row.commodity_key] }
      .count do |(chokepoint_key, commodity_key), exposures|
        source = chokepoint_entity_for(chokepoint_key)
        target = @commodity_entities[commodity_key]
        next false if source.blank? || target.blank?

        strongest = exposures.max_by { |row| row.exposure_score.to_f }
        top_countries = exposures.sort_by { |row| -row.exposure_score.to_f }.first(3).map(&:country_name)
        relationship = OntologySyncSupport.upsert_relationship(
          source_node: source,
          target_node: target,
          relation_type: "flow_dependency",
          confidence: confidence_from_score(strongest.exposure_score, floor: 0.45),
          derived_by: DERIVED_BY,
          explanation: "#{source.canonical_name} is a structural route dependency for #{target.canonical_name}, with downstream import exposure in #{top_countries.join(', ')}.",
          metadata: {
            "chokepoint_key" => chokepoint_key,
            "commodity_key" => commodity_key,
            "country_count" => exposures.map(&:country_code_alpha3).uniq.size,
            "max_exposure_score" => strongest.exposure_score&.to_f,
          }
        )
        exposures.sort_by { |row| -row.exposure_score.to_f }.first(3).each do |exposure|
          attach_evidence(relationship, exposure, evidence_role: "exposure_profile", confidence: confidence_from_score(exposure.exposure_score, floor: 0.45))
        end
        true
      end
  end

  def country_profiles
    @country_profiles ||= CountryProfile.order(:country_name).to_a
  end

  def country_sector_profiles
    @country_sector_profiles ||= CountrySectorProfile.where(rank: 1..MAX_COUNTRY_SECTORS)
      .order(:country_code_alpha3, :rank)
      .to_a
  end

  def sector_input_profiles
    @sector_input_profiles ||= SectorInputProfile.where(rank: 1..MAX_SECTOR_INPUTS)
      .order(:scope_key, :sector_key, :rank)
      .to_a
  end

  def country_commodity_dependencies
    @country_commodity_dependencies ||= CountryCommodityDependency.order(dependency_score: :desc).to_a
  end

  def country_chokepoint_exposures
    @country_chokepoint_exposures ||= CountryChokepointExposure.order(exposure_score: :desc).to_a
  end

  def commodity_pairs
    @commodity_pairs ||= begin
      names = {}

      country_commodity_dependencies.each do |dependency|
        names[dependency.commodity_key] ||= dependency.commodity_name.presence || SupplyChainCatalog.commodity_name_for(dependency.commodity_key)
      end
      country_chokepoint_exposures.each do |exposure|
        names[exposure.commodity_key] ||= exposure.commodity_name.presence || SupplyChainCatalog.commodity_name_for(exposure.commodity_key)
      end
      sector_input_profiles.each do |profile|
        next unless profile.input_kind == "commodity" || SupplyChainCatalog.commodity_name_for(profile.input_key).present?

        names[profile.input_key] ||= profile.input_name.presence || SupplyChainCatalog.commodity_name_for(profile.input_key)
      end

      names.compact.sort_by { |commodity_key, commodity_name| [commodity_name, commodity_key] }
    end
  end

  def applicable_inputs_for(country_code_alpha3, sector_key)
    scoped = sector_input_profiles.select do |profile|
      profile.country_code_alpha3 == country_code_alpha3 && profile.sector_key == sector_key
    end
    return scoped if scoped.any?

    sector_input_profiles.select do |profile|
      profile.scope_key == "global" && profile.sector_key == sector_key
    end
  end

  def input_entity_for_profile(profile)
    if profile.input_kind == "commodity" || SupplyChainCatalog.commodity_name_for(profile.input_key).present?
      @commodity_entities[profile.input_key] ||= begin
        name = profile.input_name.presence || SupplyChainCatalog.commodity_name_for(profile.input_key) || profile.input_key.to_s.humanize
        OntologySyncSupport.upsert_entity(
          canonical_key: commodity_entity_key(profile.input_key),
          entity_type: "commodity",
          canonical_name: name,
          metadata: {
            "description" => "#{name} is tracked as a strategic supply-chain commodity.",
            "commodity_key" => profile.input_key,
            "strategic" => true,
          }
        )
      end
    else
      @input_entities[[profile.input_kind, profile.input_key]] ||= OntologySyncSupport.upsert_entity(
        canonical_key: "input:#{profile.input_kind}:#{OntologySyncSupport.slugify(profile.input_key)}",
        entity_type: INPUT_ENTITY_TYPE,
        canonical_name: display_name_for_input_profile(profile),
        metadata: {
          "description" => "#{display_name_for_input_profile(profile)} is a modeled production input.",
          "input_kind" => profile.input_kind,
          "input_key" => profile.input_key,
        }
      )
    end
  end

  def chokepoint_entity_for(chokepoint_key)
    @chokepoint_entities[chokepoint_key.to_s] ||= begin
      config = ChokepointMonitorService::CHOKEPOINTS.fetch(chokepoint_key.to_sym)
      entity = OntologySyncSupport.upsert_entity(
        canonical_key: "corridor:chokepoint:#{chokepoint_key}",
        entity_type: "corridor",
        canonical_name: config.fetch(:name),
        metadata: {
          "strategic_kind" => "chokepoint",
          "description" => config[:description],
          "latitude" => config[:lat],
          "longitude" => config[:lng],
          "radius_km" => config[:radius_km],
          "countries" => config[:countries],
          "flows" => config[:flows],
        }.compact
      )
      OntologySyncSupport.upsert_alias(entity, config.fetch(:name), alias_type: "official")
      entity
    end
  end

  def attach_evidence(relationship, evidence, evidence_role:, confidence:)
    OntologySyncSupport.upsert_relationship_evidence(
      relationship,
      evidence,
      evidence_role: evidence_role,
      confidence: confidence,
      metadata: {}
    )
  end

  def country_entity_key(country_code_alpha3)
    "country:#{country_code_alpha3.to_s.downcase}"
  end

  def sector_entity_key(country_code_alpha3, sector_key)
    "sector:#{country_code_alpha3.to_s.downcase}:#{sector_key}"
  end

  def commodity_entity_key(commodity_key)
    "commodity:#{commodity_key}"
  end

  def country_description(profile)
    parts = []
    parts << format_usd_short(profile.gdp_nominal_usd, prefix: "GDP ")
    parts << "#{profile.imports_goods_services_pct_gdp.to_f.round(1)}% imports/GDP" if profile.imports_goods_services_pct_gdp.present?
    parts << "#{profile.energy_imports_net_pct_energy_use.to_f.round(1)}% net energy imports" if profile.energy_imports_net_pct_energy_use.present?
    parts << "#{profile.latest_year}" if profile.latest_year.present?
    parts.compact.join(" · ")
  end

  def import_dependency_explanation(dependency)
    parts = []
    parts << "#{dependency.country_name} depends on imported #{dependency.commodity_name}"
    parts << "(#{dependency.import_share_gdp_pct.to_f.round(2)}% of GDP)" if dependency.import_share_gdp_pct.present?
    if dependency.top_partner_country_name.present? && dependency.top_partner_share_pct.present?
      parts << "with #{dependency.top_partner_share_pct.to_f.round(1)}% sourced from #{dependency.top_partner_country_name}"
    end
    parts.join(" ")
  end

  def chokepoint_exposure_explanation(chokepoint_name, country_name, exposures)
    top_labels = exposures.first(3).map do |row|
      "#{row.commodity_name} (#{row.exposure_score.to_f.round(2)})"
    end
    "#{country_name} carries structural exposure to #{chokepoint_name} through #{top_labels.join(', ')}."
  end

  def display_name_for_input_profile(profile)
    profile.input_name.presence || profile.input_key.to_s.humanize
  end

  def confidence_from_share(value)
    confidence_from_score((value.to_f / 100.0), floor: 0.35)
  end

  def confidence_from_coefficient(value)
    numeric = value.to_f
    normalized = if numeric <= 1.0
      numeric
    else
      [Math.log10(numeric + 1) / 2.0, 1.0].min
    end

    confidence_from_score(normalized, floor: 0.35)
  end

  def confidence_from_score(value, floor: 0.4)
    (floor + (value.to_f.clamp(0.0, 1.0) * (0.95 - floor))).round(2)
  end

  def format_usd_short(value, prefix: "")
    return if value.blank?

    amount = value.to_f
    suffix = if amount >= 1_000_000_000_000
      "#{(amount / 1_000_000_000_000).round(2)}T"
    elsif amount >= 1_000_000_000
      "#{(amount / 1_000_000_000).round(1)}B"
    elsif amount >= 1_000_000
      "#{(amount / 1_000_000).round(1)}M"
    else
      amount.round.to_s
    end

    "#{prefix}$#{suffix}"
  end
end
