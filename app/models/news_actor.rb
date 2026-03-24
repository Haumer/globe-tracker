class NewsActor < ApplicationRecord
  has_many :news_claim_actors, dependent: :delete_all
  has_many :news_claims, through: :news_claim_actors

  validates :canonical_key, :name, :actor_type, presence: true
end
