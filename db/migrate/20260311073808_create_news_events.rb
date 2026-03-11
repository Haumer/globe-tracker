class CreateNewsEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :news_events do |t|
      t.string :url
      t.string :name
      t.float :latitude
      t.float :longitude
      t.float :tone
      t.string :level
      t.string :category
      t.jsonb :themes
      t.datetime :published_at
      t.datetime :fetched_at

      t.timestamps
    end
    add_index :news_events, :url, unique: true
    add_index :news_events, :published_at
    add_index :news_events, :fetched_at
    add_index :news_events, :category
  end
end
