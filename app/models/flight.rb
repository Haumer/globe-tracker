class Flight < ApplicationRecord
  include BoundsFilterable

  has_many :ontology_entity_links, as: :linkable, dependent: :delete_all
end
