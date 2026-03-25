class OntologyEntityAlias < ApplicationRecord
  belongs_to :ontology_entity

  validates :name, :alias_type, presence: true
end
