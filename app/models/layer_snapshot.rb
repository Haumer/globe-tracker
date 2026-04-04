class LayerSnapshot < ApplicationRecord
  STATUSES = %w[pending ready error].freeze

  validates :snapshot_type, :scope_key, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :for_snapshot, ->(snapshot_type, scope_key = "global") {
    where(snapshot_type: snapshot_type.to_s, scope_key: scope_key.to_s)
  }

  def fresh?
    expires_at.present? && expires_at > Time.current
  end

  def pending?
    status == "pending"
  end
end
