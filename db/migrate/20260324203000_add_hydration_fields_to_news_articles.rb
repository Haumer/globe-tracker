class AddHydrationFieldsToNewsArticles < ActiveRecord::Migration[7.1]
  def change
    add_column :news_articles, :hydration_status, :string, null: false, default: "not_requested"
    add_column :news_articles, :hydration_attempts, :integer, null: false, default: 0
    add_column :news_articles, :hydration_last_attempted_at, :datetime
    add_column :news_articles, :hydrated_at, :datetime
    add_column :news_articles, :hydration_error, :string

    add_index :news_articles, :hydration_status
    add_index :news_articles, :hydrated_at
  end
end
