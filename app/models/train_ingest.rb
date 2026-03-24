class TrainIngest < ApplicationRecord
  has_many :train_observations, dependent: :nullify

  STATUSES = %w[fetched failed].freeze

  validates :source_key, :source_name, :fetched_at, presence: true
  validates :status, inclusion: { in: STATUSES }
end
