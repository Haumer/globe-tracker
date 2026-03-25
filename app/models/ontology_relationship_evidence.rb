class OntologyRelationshipEvidence < ApplicationRecord
  belongs_to :ontology_relationship
  belongs_to :evidence, polymorphic: true

  validates :evidence_role, presence: true
end
