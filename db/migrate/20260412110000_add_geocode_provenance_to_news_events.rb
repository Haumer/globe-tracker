class AddGeocodeProvenanceToNewsEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :news_events, :geocode_place_name, :string
    add_column :news_events, :geocode_country_code, :string
    add_column :news_events, :geocode_admin_area, :string
    add_column :news_events, :geocode_basis, :string
    add_column :news_events, :geocode_precision, :string, default: "unknown", null: false
    add_column :news_events, :geocode_kind, :string, default: "unknown", null: false
    add_column :news_events, :geocode_confidence, :float, default: 0.0, null: false
    add_column :news_events, :geocode_metadata, :jsonb, default: {}, null: false

    add_index :news_events, [:geocode_kind, :geocode_confidence], name: "idx_news_events_on_geocode_kind_confidence"
    add_index :news_events, :geocode_country_code
    add_index :news_events, :geocode_basis
  end
end
