class CreateSupplyChainProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :country_profiles do |t|
      t.string :country_code
      t.string :country_code_alpha3, null: false
      t.string :country_name, null: false
      t.integer :latest_year
      t.decimal :gdp_nominal_usd, precision: 20, scale: 2
      t.decimal :gdp_per_capita_usd, precision: 20, scale: 2
      t.decimal :population_total, precision: 20, scale: 0
      t.decimal :imports_goods_services_pct_gdp, precision: 10, scale: 4
      t.decimal :exports_goods_services_pct_gdp, precision: 10, scale: 4
      t.decimal :energy_imports_net_pct_energy_use, precision: 10, scale: 4
      t.jsonb :metadata, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :country_profiles, :country_code_alpha3, unique: true
    add_index :country_profiles, :country_code
    add_index :country_profiles, :fetched_at

    create_table :country_sector_profiles do |t|
      t.string :country_code
      t.string :country_code_alpha3, null: false
      t.string :country_name, null: false
      t.string :sector_key, null: false
      t.string :sector_name, null: false
      t.integer :period_year, null: false
      t.decimal :share_pct, precision: 10, scale: 4
      t.integer :rank
      t.jsonb :metadata, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :country_sector_profiles, %i[country_code_alpha3 sector_key], unique: true, name: "idx_country_sector_profiles_unique_sector"
    add_index :country_sector_profiles, :country_code
    add_index :country_sector_profiles, :fetched_at
    add_index :country_sector_profiles, :rank

    create_table :sector_input_profiles do |t|
      t.string :scope_key, null: false, default: "global"
      t.string :country_code
      t.string :country_code_alpha3
      t.string :country_name
      t.string :sector_key, null: false
      t.string :sector_name, null: false
      t.string :input_kind, null: false
      t.string :input_key, null: false
      t.string :input_name
      t.integer :period_year, null: false
      t.decimal :coefficient, precision: 20, scale: 8
      t.integer :rank
      t.jsonb :metadata, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :sector_input_profiles, %i[scope_key sector_key input_kind input_key], unique: true, name: "idx_sector_input_profiles_unique_input"
    add_index :sector_input_profiles, :country_code_alpha3
    add_index :sector_input_profiles, :fetched_at

    create_table :country_commodity_dependencies do |t|
      t.string :country_code
      t.string :country_code_alpha3, null: false
      t.string :country_name, null: false
      t.string :commodity_key, null: false
      t.string :commodity_name
      t.date :period_start
      t.date :period_end
      t.string :period_type
      t.decimal :import_value_usd, precision: 20, scale: 2
      t.integer :supplier_count
      t.string :top_partner_country_code
      t.string :top_partner_country_code_alpha3
      t.string :top_partner_country_name
      t.decimal :top_partner_share_pct, precision: 10, scale: 4
      t.decimal :concentration_hhi, precision: 10, scale: 6
      t.decimal :import_share_gdp_pct, precision: 10, scale: 6
      t.decimal :dependency_score, precision: 10, scale: 6
      t.jsonb :metadata, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :country_commodity_dependencies, %i[country_code_alpha3 commodity_key], unique: true, name: "idx_country_commodity_dependencies_unique_commodity"
    add_index :country_commodity_dependencies, :country_code
    add_index :country_commodity_dependencies, :dependency_score
    add_index :country_commodity_dependencies, :fetched_at

    create_table :country_chokepoint_exposures do |t|
      t.string :country_code
      t.string :country_code_alpha3, null: false
      t.string :country_name, null: false
      t.string :commodity_key, null: false
      t.string :commodity_name
      t.string :chokepoint_key, null: false
      t.string :chokepoint_name, null: false
      t.decimal :exposure_score, precision: 10, scale: 6
      t.decimal :dependency_score, precision: 10, scale: 6
      t.decimal :supplier_share_pct, precision: 10, scale: 4
      t.text :rationale
      t.jsonb :metadata, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :country_chokepoint_exposures, %i[country_code_alpha3 commodity_key chokepoint_key], unique: true, name: "idx_country_chokepoint_exposures_unique_chokepoint"
    add_index :country_chokepoint_exposures, :country_code
    add_index :country_chokepoint_exposures, :exposure_score
    add_index :country_chokepoint_exposures, :fetched_at
  end
end
