class OntologyRelationship < ApplicationRecord
  belongs_to :source_node, polymorphic: true
  belongs_to :target_node, polymorphic: true

  has_many :ontology_relationship_evidences, dependent: :delete_all

  validates :relation_type, :derived_by, presence: true

  scope :active, -> { where("fresh_until IS NULL OR fresh_until > ?", Time.current) }

  def active?
    fresh_until.blank? || fresh_until.future?
  end
end
