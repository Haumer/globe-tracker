class SectorInputProfile < ApplicationRecord
  validates :scope_key, :sector_key, :sector_name, :input_kind, :input_key, :period_year, presence: true
end
