class NewsStoryCluster < ApplicationRecord
  belongs_to :lead_news_article, class_name: "NewsArticle", optional: true

  has_many :news_story_memberships, dependent: :delete_all
  has_many :news_articles, through: :news_story_memberships
  has_one :ontology_event, foreign_key: :primary_story_cluster_id, dependent: :nullify
  has_many :ontology_evidence_links, as: :evidence, dependent: :delete_all

  validates :cluster_key, :content_scope, :event_family, :event_type, :geo_precision,
    :first_seen_at, :last_seen_at, :verification_status, presence: true
end
