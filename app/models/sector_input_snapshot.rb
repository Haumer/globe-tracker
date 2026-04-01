class SectorInputSnapshot < ApplicationRecord
  validates :scope_key, :sector_key, :sector_name, :input_kind, :input_key,
    :period_year, :source, :dataset, presence: true

  scope :latest_first, -> { order(period_year: :desc, scope_key: :asc, sector_key: :asc) }
end
