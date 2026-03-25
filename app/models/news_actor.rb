class NewsActor < ApplicationRecord
  has_many :news_claim_actors, dependent: :delete_all
  has_many :news_claims, through: :news_claim_actors
  has_many :ontology_entity_links, as: :linkable, dependent: :delete_all

  validates :canonical_key, :name, :actor_type, presence: true
end
