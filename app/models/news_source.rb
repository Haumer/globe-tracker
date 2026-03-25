class NewsSource < ApplicationRecord
  has_many :news_articles, dependent: :restrict_with_exception
  has_many :news_events, dependent: :nullify
  has_many :ontology_entity_links, as: :linkable, dependent: :delete_all

  validates :canonical_key, :name, :source_kind, presence: true
end
