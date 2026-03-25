class OntologyEventEntity < ApplicationRecord
  belongs_to :ontology_event
  belongs_to :ontology_entity

  validates :role, presence: true
end
