class OntologyEvidenceLink < ApplicationRecord
  belongs_to :ontology_event
  belongs_to :evidence, polymorphic: true

  validates :evidence_role, presence: true
end
