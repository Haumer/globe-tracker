class CreateNewsIngests < ActiveRecord::Migration[7.1]
  def change
    create_table :news_ingests do |t|
      t.string :source_feed, null: false
      t.string :source_endpoint_url, null: false
      t.string :external_id
      t.string :raw_url
      t.text :raw_title
      t.text :raw_summary
      t.datetime :raw_published_at
      t.datetime :fetched_at, null: false
      t.string :payload_format, null: false
      t.jsonb :raw_payload, null: false, default: {}
      t.integer :http_status
      t.string :content_hash, null: false

      t.timestamps
    end

    add_index :news_ingests, :content_hash, unique: true
    add_index :news_ingests, :fetched_at
    add_index :news_ingests, :source_feed

    add_reference :news_events, :news_ingest, foreign_key: true
  end
end
