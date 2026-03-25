class AddOriginSourceFieldsToNewsArticles < ActiveRecord::Migration[7.1]
  def change
    change_table :news_articles, bulk: true do |t|
      t.string :origin_source_name
      t.string :origin_source_kind
      t.string :origin_source_domain
    end

    add_index :news_articles, :origin_source_kind
    add_index :news_articles, :origin_source_domain
  end
end
