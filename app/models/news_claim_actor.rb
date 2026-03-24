class NewsClaimActor < ApplicationRecord
  belongs_to :news_claim
  belongs_to :news_actor

  validates :role, :position, presence: true
end
