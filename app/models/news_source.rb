class NewsSource < ApplicationRecord
  has_many :news_articles, dependent: :restrict_with_exception
  has_many :news_events, dependent: :nullify

  validates :canonical_key, :name, :source_kind, presence: true
end
