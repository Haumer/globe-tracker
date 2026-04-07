class InternetAttackPairSnapshot < ApplicationRecord
  scope :latest_batch, -> {
    max_time = maximum(:recorded_at)
    max_time ? where(recorded_at: max_time) : none
  }

  scope :latest_batch_at, ->(time) {
    target_time = time.presence
    max_time = target_time ? where("recorded_at <= ?", target_time).maximum(:recorded_at) : maximum(:recorded_at)
    max_time ? where(recorded_at: max_time) : none
  }
end
