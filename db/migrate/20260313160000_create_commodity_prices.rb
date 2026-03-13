class CreateCommodityPrices < ActiveRecord::Migration[7.1]
  def change
    create_table :commodity_prices do |t|
      t.string :symbol, null: false          # e.g. "OIL", "GOLD", "GAS", "EUR", "JPY"
      t.string :category, null: false         # "commodity", "currency", "index"
      t.string :name, null: false             # "Crude Oil (WTI)", "Gold", "EUR/USD"
      t.decimal :price, precision: 15, scale: 4
      t.decimal :change_pct, precision: 8, scale: 4  # daily % change
      t.string :unit                          # "USD/barrel", "USD/oz", etc.
      t.float :latitude                       # production center lat (for map placement)
      t.float :longitude                      # production center lng
      t.string :region                        # "Middle East", "North America", etc.
      t.datetime :recorded_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :commodity_prices, [:symbol, :recorded_at], unique: true
    add_index :commodity_prices, :category
    add_index :commodity_prices, :recorded_at
  end
end
