class TrainObservation < ApplicationRecord
  include BoundsFilterable

  belongs_to :train_ingest, optional: true
  belongs_to :matched_railway, class_name: "Railway", optional: true

  validates :external_id, presence: true, uniqueness: true
  validates :fetched_at, presence: true

  scope :current, -> {
    where("expires_at > ? OR fetched_at > ?", Time.current, 2.minutes.ago)
  }
end
