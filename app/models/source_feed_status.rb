class SourceFeedStatus < ApplicationRecord
  validates :feed_key, :provider, :display_name, :feed_kind, :status, presence: true

  scope :active_first, -> {
    order(
      Arel.sql(
        "CASE status " \
        "WHEN 'error' THEN 0 " \
        "WHEN 'disabled' THEN 1 " \
        "WHEN 'unknown' THEN 2 " \
        "WHEN 'success' THEN 3 " \
        "ELSE 4 END"
      ),
      last_success_at: :desc,
      display_name: :asc
    )
  }
end
