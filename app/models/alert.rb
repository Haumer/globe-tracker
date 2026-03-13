class Alert < ApplicationRecord
  belongs_to :watch, optional: true
  belongs_to :user

  validates :title, presence: true

  scope :unseen, -> { where(seen: false) }
  scope :recent, -> { order(created_at: :desc).limit(50) }
end
