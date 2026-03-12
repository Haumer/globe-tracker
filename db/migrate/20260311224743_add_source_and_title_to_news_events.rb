class AddSourceAndTitleToNewsEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :news_events, :source, :string
    add_column :news_events, :title, :string
    add_index :news_events, :source
    add_index :news_events, :title
  end
end
