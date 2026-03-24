class CreateNewsSourcesAndArticles < ActiveRecord::Migration[7.1]
  def change
    create_table :news_sources do |t|
      t.string :canonical_key, null: false
      t.string :name, null: false
      t.string :source_kind, null: false, default: "publisher"
      t.string :publisher_domain
      t.string :publisher_country
      t.string :publisher_city
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :news_sources, :canonical_key, unique: true
    add_index :news_sources, :publisher_domain
    add_index :news_sources, :source_kind

    create_table :news_articles do |t|
      t.references :news_source, null: false, foreign_key: true
      t.references :news_ingest, foreign_key: true
      t.string :url, null: false
      t.string :canonical_url, null: false
      t.string :title
      t.text :summary
      t.string :publisher_name
      t.string :publisher_domain
      t.string :language
      t.datetime :published_at
      t.datetime :fetched_at
      t.string :normalization_status, null: false, default: "normalized"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :news_articles, :canonical_url, unique: true
    add_index :news_articles, :published_at
    add_index :news_articles, :publisher_domain

    add_reference :news_events, :news_source, foreign_key: true
    add_reference :news_events, :news_article, foreign_key: true
  end
end
