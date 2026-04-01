class CreateSupplyChainDataTables < ActiveRecord::Migration[7.1]
  def change
    create_table :country_indicator_snapshots do |t|
      t.string :country_code
      t.string :country_code_alpha3, null: false
      t.string :country_name, null: false
      t.string :indicator_key, null: false
      t.string :indicator_name, null: false
      t.string :period_type, null: false, default: "year"
      t.date :period_start, null: false
      t.date :period_end
      t.decimal :value_numeric, precision: 20, scale: 6
      t.string :value_text
      t.string :unit
      t.string :source, null: false
      t.string :dataset, null: false
      t.string :series_key
      t.string :release_version
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :country_indicator_snapshots, :country_code
    add_index :country_indicator_snapshots, :country_code_alpha3
    add_index :country_indicator_snapshots, :indicator_key
    add_index :country_indicator_snapshots, :fetched_at
    add_index :country_indicator_snapshots,
      %i[country_code_alpha3 indicator_key period_type period_start dataset],
      unique: true,
      name: "idx_country_indicator_snapshots_unique_period"

    create_table :country_sector_snapshots do |t|
      t.string :country_code
      t.string :country_code_alpha3, null: false
      t.string :country_name, null: false
      t.string :sector_key, null: false
      t.string :sector_name, null: false
      t.string :metric_key, null: false
      t.string :metric_name, null: false
      t.integer :period_year, null: false
      t.decimal :value_numeric, precision: 20, scale: 6
      t.string :unit
      t.string :source, null: false
      t.string :dataset, null: false
      t.string :release_version
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :country_sector_snapshots, :country_code
    add_index :country_sector_snapshots, :country_code_alpha3
    add_index :country_sector_snapshots, :sector_key
    add_index :country_sector_snapshots, :fetched_at
    add_index :country_sector_snapshots,
      %i[country_code_alpha3 sector_key metric_key period_year dataset],
      unique: true,
      name: "idx_country_sector_snapshots_unique_period"

    create_table :trade_flow_snapshots do |t|
      t.string :reporter_country_code
      t.string :reporter_country_code_alpha3, null: false
      t.string :reporter_country_name
      t.string :partner_country_code
      t.string :partner_country_code_alpha3, null: false
      t.string :partner_country_name
      t.string :flow_direction, null: false
      t.string :commodity_key, null: false
      t.string :commodity_name
      t.string :hs_code
      t.string :period_type, null: false, default: "month"
      t.date :period_start, null: false
      t.date :period_end
      t.decimal :trade_value_usd, precision: 20, scale: 2
      t.decimal :quantity, precision: 20, scale: 4
      t.string :quantity_unit
      t.string :source, null: false
      t.string :dataset, null: false
      t.string :release_version
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :trade_flow_snapshots, :reporter_country_code
    add_index :trade_flow_snapshots, :reporter_country_code_alpha3
    add_index :trade_flow_snapshots, :partner_country_code
    add_index :trade_flow_snapshots, :partner_country_code_alpha3
    add_index :trade_flow_snapshots, :commodity_key
    add_index :trade_flow_snapshots, :fetched_at
    add_index :trade_flow_snapshots,
      %i[
        reporter_country_code_alpha3 partner_country_code_alpha3 flow_direction
        commodity_key hs_code period_type period_start dataset
      ],
      unique: true,
      name: "idx_trade_flow_snapshots_unique_period"

    create_table :energy_balance_snapshots do |t|
      t.string :country_code
      t.string :country_code_alpha3, null: false
      t.string :country_name, null: false
      t.string :commodity_key, null: false
      t.string :metric_key, null: false
      t.string :period_type, null: false, default: "month"
      t.date :period_start, null: false
      t.date :period_end
      t.decimal :value_numeric, precision: 20, scale: 6
      t.string :unit
      t.string :source, null: false
      t.string :dataset, null: false
      t.string :release_version
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :energy_balance_snapshots, :country_code
    add_index :energy_balance_snapshots, :country_code_alpha3
    add_index :energy_balance_snapshots, :commodity_key
    add_index :energy_balance_snapshots, :fetched_at
    add_index :energy_balance_snapshots,
      %i[country_code_alpha3 commodity_key metric_key period_type period_start dataset],
      unique: true,
      name: "idx_energy_balance_snapshots_unique_period"

    create_table :sector_input_snapshots do |t|
      t.string :scope_key, null: false, default: "global"
      t.string :country_code
      t.string :country_code_alpha3
      t.string :country_name
      t.string :sector_key, null: false
      t.string :sector_name, null: false
      t.string :input_kind, null: false
      t.string :input_key, null: false
      t.string :input_name
      t.decimal :coefficient, precision: 20, scale: 8
      t.integer :period_year, null: false
      t.string :source, null: false
      t.string :dataset, null: false
      t.string :release_version
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :sector_input_snapshots, :scope_key
    add_index :sector_input_snapshots, :sector_key
    add_index :sector_input_snapshots, :input_key
    add_index :sector_input_snapshots, :fetched_at
    add_index :sector_input_snapshots,
      %i[scope_key sector_key input_kind input_key period_year dataset],
      unique: true,
      name: "idx_sector_input_snapshots_unique_period"

    create_table :trade_locations do |t|
      t.string :locode, null: false
      t.string :country_code
      t.string :country_code_alpha3
      t.string :country_name
      t.string :subdivision_code
      t.string :name, null: false
      t.string :normalized_name
      t.string :location_kind, null: false, default: "trade_node"
      t.string :function_codes
      t.float :latitude
      t.float :longitude
      t.string :status, null: false, default: "active"
      t.string :source, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :trade_locations, :locode, unique: true
    add_index :trade_locations, :country_code
    add_index :trade_locations, :country_code_alpha3
    add_index :trade_locations, :location_kind
    add_index :trade_locations, %i[latitude longitude]
  end
end
