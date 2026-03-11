class PollingStat < ApplicationRecord
  scope :recent, -> { where("created_at > ?", 1.hour.ago) }
  scope :by_source, ->(source) { where(source: source) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "error") }
end
