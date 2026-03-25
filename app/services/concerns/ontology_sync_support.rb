module OntologySyncSupport
  module_function

  def upsert_entity(canonical_key:, entity_type:, canonical_name:, country_code: nil, metadata: {})
    OntologyEntity.find_or_initialize_by(canonical_key: canonical_key).tap do |entity|
      entity.entity_type = entity_type
      entity.canonical_name = canonical_name
      entity.country_code = country_code
      entity.metadata = (entity.metadata || {}).merge(metadata.compact)
      entity.save!
    end
  end

  def upsert_alias(entity, name, alias_type:)
    return if name.blank?

    OntologyEntityAlias.find_or_create_by!(ontology_entity: entity, name: name) do |record|
      record.alias_type = alias_type
    end
  end

  def upsert_link(entity, linkable, role:, method:, confidence: 1.0, metadata: {})
    OntologyEntityLink.find_or_initialize_by(
      ontology_entity: entity,
      linkable: linkable,
      role: role
    ).tap do |link|
      link.method = method
      link.confidence = confidence
      link.metadata = metadata
      link.save!
    end
  end

  def upsert_evidence_link(event, evidence, evidence_role:, confidence:, metadata: {})
    OntologyEvidenceLink.find_or_initialize_by(
      ontology_event: event,
      evidence: evidence,
      evidence_role: evidence_role
    ).tap do |link|
      link.confidence = confidence || 0.0
      link.metadata = metadata
      link.save!
    end
  end

  def upsert_relationship(source_node:, target_node:, relation_type:, confidence:, fresh_until: nil, derived_by:, explanation: nil, metadata: {})
    OntologyRelationship.find_or_initialize_by(
      source_node: source_node,
      target_node: target_node,
      relation_type: relation_type
    ).tap do |relationship|
      relationship.confidence = confidence || 0.0
      relationship.fresh_until = fresh_until
      relationship.derived_by = derived_by
      relationship.explanation = explanation
      relationship.metadata = metadata.compact
      relationship.save!
    end
  end

  def upsert_relationship_evidence(relationship, evidence, evidence_role:, confidence:, metadata: {})
    OntologyRelationshipEvidence.find_or_initialize_by(
      ontology_relationship: relationship,
      evidence: evidence,
      evidence_role: evidence_role
    ).tap do |link|
      link.confidence = confidence || 0.0
      link.metadata = metadata.compact
      link.save!
    end
  end

  def slugify(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
  end

  def normalized_confidence(value)
    numeric = value.to_f
    return 0.0 if numeric.negative?
    return 1.0 if numeric > 100.0
    return numeric / 100.0 if numeric > 1.0

    numeric
  end
end
