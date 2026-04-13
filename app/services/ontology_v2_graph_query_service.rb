class OntologyV2GraphQueryService
  DEFAULT_LIMIT = 32
  RELATION_GROUPS = {
    infrastructure: %w[
      impacted_infrastructure
      exposed_infrastructure
      infrastructure_disruption
      infrastructure_exposure
    ],
    events: %w[
      occurred_at
      initiated_event
      participated_in_event
      involved_in_event
      hosted_event
      mediated_event
      reported_event
      targeted_entity
      affected_entity
      affected_asset
    ],
    geography: %w[
      located_in_country
      lands_in_country
    ],
    identity: %w[
      represents_country
      place_resolves_to_country
    ],
    operations: %w[
      operational_activity
      local_corroboration
      theater_pressure
    ],
  }.freeze
  GROUP_PRIORITY = {
    infrastructure: 0,
    events: 1,
    geography: 2,
    identity: 3,
    operations: 4,
    other: 100,
  }.freeze

  class << self
    def for_node(kind:, id:, limit: DEFAULT_LIMIT)
      new.for_node(kind: kind, id: id, limit: limit)
    end
  end

  def for_node(kind:, id:, limit: DEFAULT_LIMIT)
    context = NodeContextService.resolve(kind: kind, id: id).deep_symbolize_keys
    node = load_node(context.fetch(:node))
    relationships = serialize_relationships(node, limit: limit)

    context.merge(
      relationships: relationships,
      relationship_groups: relationship_groups(relationships)
    )
  end

  private

  def load_node(payload)
    case payload.fetch(:node_type)
    when "entity"
      OntologyEntity.find(payload.fetch(:id))
    when "event"
      OntologyEvent.find(payload.fetch(:id))
    else
      raise NodeContextService::UnsupportedNodeError, "unsupported ontology v2 graph node type: #{payload.fetch(:node_type)}"
    end
  end

  def serialize_relationships(node, limit:)
    relationship_records_for(node)
      .map { |relationship, direction| NodeContextService.send(:serialize_relationship, relationship, direction: direction) }
      .sort_by { |relationship| graph_relationship_sort_key(relationship) }
      .first(limit.to_i.clamp(1, 200))
  end

  def relationship_records_for(node)
    outgoing = node.outgoing_ontology_relationships.active.includes(:ontology_relationship_evidences).to_a.map do |relationship|
      [relationship, "outgoing"]
    end
    incoming = node.incoming_ontology_relationships.active.includes(:ontology_relationship_evidences).to_a.map do |relationship|
      [relationship, "incoming"]
    end

    outgoing + incoming
  end

  def relationship_groups(relationships)
    relationships
      .group_by { |relationship| group_for(relationship.fetch(:relation_type)) }
      .map do |group, grouped_relationships|
        {
          group: group,
          count: grouped_relationships.size,
          relationships: grouped_relationships,
        }
      end
      .sort_by { |payload| GROUP_PRIORITY.fetch(payload.fetch(:group), GROUP_PRIORITY.fetch(:other)) }
  end

  def graph_relationship_sort_key(relationship)
    group = group_for(relationship.fetch(:relation_type))
    [
      GROUP_PRIORITY.fetch(group, GROUP_PRIORITY.fetch(:other)),
      NodeContextService::RELATIONSHIP_PRIORITY.fetch(relationship.fetch(:relation_type).to_s, 100),
      -relationship.fetch(:confidence).to_f,
      relationship.fetch(:node).fetch(:name).to_s,
    ]
  end

  def group_for(relation_type)
    relation_type = relation_type.to_s
    RELATION_GROUPS.each do |group, relation_types|
      return group if relation_types.include?(relation_type)
    end
    :other
  end
end
