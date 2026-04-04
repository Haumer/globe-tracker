class TradeLocation < ApplicationRecord
  validates :locode, :name, :location_kind, :status, :source, presence: true

  scope :active, -> { where(status: "active") }
end
