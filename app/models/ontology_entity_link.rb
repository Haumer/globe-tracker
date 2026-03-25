class OntologyEntityLink < ApplicationRecord
  belongs_to :ontology_entity
  belongs_to :linkable, polymorphic: true

  validates :role, :method, presence: true
end
