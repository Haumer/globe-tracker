class NewsStoryMembership < ApplicationRecord
  belongs_to :news_story_cluster
  belongs_to :news_article

  validates :match_score, presence: true
end
