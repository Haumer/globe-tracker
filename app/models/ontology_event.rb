class OntologyEvent < ApplicationRecord
  belongs_to :place_entity, class_name: "OntologyEntity", optional: true
  belongs_to :primary_story_cluster, class_name: "NewsStoryCluster", optional: true

  has_many :ontology_event_entities, dependent: :delete_all
  has_many :ontology_entities, through: :ontology_event_entities
  has_many :ontology_evidence_links, dependent: :delete_all
  has_many :outgoing_ontology_relationships,
    as: :source_node,
    class_name: "OntologyRelationship",
    dependent: :delete_all
  has_many :incoming_ontology_relationships,
    as: :target_node,
    class_name: "OntologyRelationship",
    dependent: :delete_all

  validates :canonical_key, :event_family, :event_type, :status, :verification_status, :geo_precision, presence: true
end
