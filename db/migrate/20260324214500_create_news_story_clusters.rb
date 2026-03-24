class CreateNewsStoryClusters < ActiveRecord::Migration[7.1]
  def change
    create_table :news_story_clusters do |t|
      t.string :cluster_key, null: false
      t.string :canonical_title
      t.string :content_scope, null: false, default: "adjacent"
      t.string :event_family, null: false
      t.string :event_type, null: false
      t.string :location_name
      t.float :latitude
      t.float :longitude
      t.string :geo_precision, null: false, default: "unknown"
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.integer :article_count, null: false, default: 0
      t.integer :source_count, null: false, default: 0
      t.float :cluster_confidence, null: false, default: 0.0
      t.string :verification_status, null: false, default: "single_source"
      t.references :lead_news_article, foreign_key: { to_table: :news_articles }
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :news_story_clusters, :cluster_key, unique: true
    add_index :news_story_clusters, [ :event_family, :last_seen_at ]
    add_index :news_story_clusters, [ :content_scope, :last_seen_at ]

    create_table :news_story_memberships do |t|
      t.references :news_story_cluster, null: false, foreign_key: true
      t.references :news_article, null: false, foreign_key: true, index: { unique: true }
      t.float :match_score, null: false, default: 0.0
      t.boolean :primary, null: false, default: true
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :news_story_memberships, [ :news_story_cluster_id, :primary ], name: "idx_news_story_memberships_cluster_primary"
  end
end
