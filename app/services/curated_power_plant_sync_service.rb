class CuratedPowerPlantSyncService
  def self.sync!
    new.sync!
  end

  def sync!
    records = CuratedPowerPlantCatalog.all
    return { updated: 0, inserted: 0, total: 0 } if records.blank?

    updated = 0
    inserted = 0
    now = Time.current

    records.each do |record|
      attrs = normalized_attributes(record, now)
      next if attrs.blank?

      if (plant = matched_plant(record))
        plant.update!(attrs.except(:gppd_idnr, :created_at))
        updated += 1
      elsif attrs[:latitude].present? && attrs[:longitude].present?
        PowerPlant.create!(attrs)
        inserted += 1
      end
    end

    { updated:, inserted:, total: records.size }
  end

  private

  def matched_plant(record)
    if record["match_gppd_idnr"].present?
      plant = PowerPlant.find_by(gppd_idnr: record["match_gppd_idnr"].to_s)
      return plant if plant.present?
    end

    if record["match_name"].present? && record["country_code"].present?
      plant = PowerPlant.find_by(
        name: record["match_name"].to_s,
        country_code: record["country_code"].to_s.upcase
      )
      return plant if plant.present?
    end

    if record["gppd_idnr"].present?
      PowerPlant.find_by(gppd_idnr: record["gppd_idnr"].to_s)
    end
  end

  def normalized_attributes(record, now)
    country_code = record["country_code"].to_s.upcase.presence
    name = record["name"].presence || record["match_name"].presence
    gppd_idnr = record["gppd_idnr"].presence || synthetic_gppd_id(record)

    return if gppd_idnr.blank? || name.blank? || country_code.blank?

    attrs = {
      gppd_idnr: gppd_idnr,
      name: name,
      country_code: country_code,
      country_name: record["country_name"].presence,
      capacity_mw: record["capacity_mw"],
      primary_fuel: record["primary_fuel"].presence,
      owner: record["owner"].presence,
      source: record["source_name"].presence,
      url: record["source_url"].presence,
      updated_at: now,
      created_at: now,
    }

    if record["lat"].present? && record["lng"].present?
      attrs[:latitude] = record["lat"].to_f
      attrs[:longitude] = record["lng"].to_f
    end

    attrs.compact
  end

  def synthetic_gppd_id(record)
    slug = record["id"].presence || record["name"].to_s.parameterize.presence
    return if slug.blank?

    "CURATED-#{slug.upcase}"
  end
end
