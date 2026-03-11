class InternetTrafficSnapshot < ApplicationRecord
  scope :latest_batch, -> {
    max_time = maximum(:recorded_at)
    max_time ? where(recorded_at: max_time) : none
  }
end
