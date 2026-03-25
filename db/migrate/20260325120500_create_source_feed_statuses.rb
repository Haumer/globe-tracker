class CreateSourceFeedStatuses < ActiveRecord::Migration[7.1]
  def change
    create_table :source_feed_statuses do |t|
      t.string :feed_key, null: false
      t.string :provider, null: false
      t.string :display_name, null: false
      t.string :feed_kind, null: false
      t.string :endpoint_url
      t.string :status, null: false, default: "unknown"
      t.datetime :last_success_at
      t.datetime :last_error_at
      t.integer :last_http_status
      t.integer :last_records_fetched, null: false, default: 0
      t.integer :last_records_stored, null: false, default: 0
      t.string :last_error_message
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :source_feed_statuses, :feed_key, unique: true
    add_index :source_feed_statuses, :provider
    add_index :source_feed_statuses, :status
  end
end
