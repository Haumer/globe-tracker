class NewsClaim < ApplicationRecord
  belongs_to :news_article

  has_many :news_claim_actors, -> { order(:position) }, dependent: :delete_all
  has_many :news_actors, through: :news_claim_actors

  validates :event_family, :event_type, :extraction_method, :extraction_version, presence: true
end
