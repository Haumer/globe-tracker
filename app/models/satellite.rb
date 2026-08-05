class Satellite < ApplicationRecord
  OBSERVATION_CATEGORIES = %w[
    weather
    resource
    planet
    radar
    dmc
  ].freeze

  OBSERVATION_MISSION_TYPES = %w[
    early_warning
    imaging
    missile_defense
    radar_imaging
    reconnaissance
    sigint
    space_surveillance
    stealth_recon
    weather
  ].freeze

  scope :observation_capable, -> {
    where(
      arel_table[:category].in(OBSERVATION_CATEGORIES)
        .or(arel_table[:mission_type].in(OBSERVATION_MISSION_TYPES))
    )
  }

  def observation_capable?
    OBSERVATION_CATEGORIES.include?(category) || OBSERVATION_MISSION_TYPES.include?(mission_type)
  end
end
