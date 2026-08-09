module OntologySyncSupport
  module_function

  def upsert_entity(canonical_key:, entity_type:, canonical_name:, country_code: nil, metadata: {})
    persist_upsert(OntologyEntity, canonical_key: canonical_key) do |entity|
      entity.entity_type = entity_type
      entity.canonical_name = canonical_name
      entity.country_code = country_code
      entity.metadata = (entity.metadata || {}).merge(metadata.compact)
    end
  end

  def upsert_alias(entity, name, alias_type:)
    return if name.blank?

    persist_upsert(OntologyEntityAlias, ontology_entity: entity, name: name) do |record|
      record.alias_type = alias_type if record.new_record?
    end
  end

  def upsert_link(entity, linkable, role:, method:, confidence: 1.0, metadata: {})
    persist_upsert(
      OntologyEntityLink,
      ontology_entity: entity,
      linkable: linkable,
      role: role
    ) do |link|
      link.method = method
      link.confidence = confidence
      link.metadata = metadata
    end
  end

  def upsert_evidence_link(event, evidence, evidence_role:, confidence:, metadata: {})
    persist_upsert(
      OntologyEvidenceLink,
      ontology_event: event,
      evidence: evidence,
      evidence_role: evidence_role
    ) do |link|
      link.confidence = confidence || 0.0
      link.metadata = metadata
    end
  end

  def upsert_relationship(source_node:, target_node:, relation_type:, confidence:, fresh_until: nil, derived_by:, explanation: nil, metadata: {})
    persist_upsert(
      OntologyRelationship,
      source_node: source_node,
      target_node: target_node,
      relation_type: relation_type
    ) do |relationship|
      relationship.confidence = confidence || 0.0
      relationship.fresh_until = fresh_until
      relationship.derived_by = derived_by
      relationship.explanation = explanation
      relationship.metadata = metadata.compact
    end
  end

  def upsert_relationship_evidence(relationship, evidence, evidence_role:, confidence:, metadata: {})
    persist_upsert(
      OntologyRelationshipEvidence,
      ontology_relationship: relationship,
      evidence: evidence,
      evidence_role: evidence_role
    ) do |link|
      link.confidence = confidence || 0.0
      link.metadata = metadata.compact
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

  # Metadata keys that record when a sync last looked at a row rather than
  # anything about the row itself. Nothing reads them, and stamping them on
  # every pass made every record dirty: a no-op re-sync of 80 events still
  # issued 81 UPDATEs, because the only difference was the timestamp the sync
  # had just written.
  TOUCH_METADATA_KEYS = %w[synced_at asset_graph_synced_at].freeze

  def persist_upsert(model_class, find_by_attributes)
    attempts = 0

    begin
      model_class.find_or_initialize_by(find_by_attributes).tap do |record|
        yield record
        next if record.persisted? && only_touch_changes?(record)

        record.save!
      end
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      raise if attempts > 1

      retry
    end
  end

  # True when re-deriving this record produced nothing new -- so the write can
  # be skipped entirely and the row keeps its original updated_at, which is what
  # incremental passes filter on.
  def only_touch_changes?(record)
    changes = record.changes.except("updated_at", "created_at")
    return true if changes.empty?
    return false unless changes.keys == ["metadata"]

    before, after = changes.fetch("metadata")
    before.to_h.except(*TOUCH_METADATA_KEYS) == after.to_h.except(*TOUCH_METADATA_KEYS)
  end
end
