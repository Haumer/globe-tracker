class NewsArticle < ApplicationRecord
  belongs_to :news_source
  belongs_to :news_ingest, optional: true

  has_many :news_claims, dependent: :delete_all
  has_many :news_events, dependent: :nullify

  validates :url, :canonical_url, :normalization_status, :content_scope, presence: true

  scope :hydration_pending, -> { where(hydration_status: %w[queued failed not_requested]) }
end
