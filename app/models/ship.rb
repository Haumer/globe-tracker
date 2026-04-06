class Ship < ApplicationRecord
  include BoundsFilterable

  NAVAL_SHIP_TYPES = [35, 55].freeze
  NAVAL_NAME_PATTERN = /\b(USS|HMS|HMAS|INS|KRI|HMCS|HMNZS|FGS|FS|ITS|ESPS|TCG|ROKS|JS|BRP)\b/i

  has_many :ontology_entity_links, as: :linkable, dependent: :delete_all

  def naval_vessel?
    NAVAL_SHIP_TYPES.include?(ship_type.to_i) || NAVAL_NAME_PATTERN.match?(name.to_s)
  end
end
