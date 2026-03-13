class Watch < ApplicationRecord
  belongs_to :user
  has_many :alerts, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }
  validates :watch_type, presence: true, inclusion: { in: %w[entity area event] }
  validates :cooldown_minutes, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }

  def cooled_down?
    last_triggered_at.nil? || last_triggered_at < cooldown_minutes.minutes.ago
  end
end
