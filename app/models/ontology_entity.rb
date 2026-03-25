class OntologyEntity < ApplicationRecord
  belongs_to :parent_entity, class_name: "OntologyEntity", optional: true

  has_many :child_entities, class_name: "OntologyEntity", foreign_key: :parent_entity_id, dependent: :nullify
  has_many :ontology_entity_aliases, dependent: :delete_all
  has_many :ontology_entity_links, dependent: :delete_all
  has_many :ontology_event_entities, dependent: :delete_all
  has_many :ontology_events, through: :ontology_event_entities
  has_many :outgoing_ontology_relationships,
    as: :source_node,
    class_name: "OntologyRelationship",
    dependent: :delete_all
  has_many :incoming_ontology_relationships,
    as: :target_node,
    class_name: "OntologyRelationship",
    dependent: :delete_all

  validates :canonical_key, :entity_type, :canonical_name, presence: true
end
