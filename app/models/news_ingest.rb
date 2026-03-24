class NewsIngest < ApplicationRecord
  has_many :news_articles, dependent: :nullify
  has_many :news_events, dependent: :nullify

  validates :source_feed, :source_endpoint_url, :fetched_at, :payload_format, :content_hash, presence: true
end
