class AddContentScopeToNewsArticlesAndEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :news_articles, :content_scope, :string, null: false, default: "adjacent"
    add_column :news_articles, :scope_reason, :string
    add_index :news_articles, :content_scope

    add_column :news_events, :content_scope, :string
    add_index :news_events, :content_scope
  end
end
