class AddSourceToCommodityPrices < ActiveRecord::Migration[7.1]
  def change
    add_column :commodity_prices, :source, :string
    add_index :commodity_prices, :source
  end
end
