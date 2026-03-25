class AddTrustFieldsToNewsClaimsAndStoryClusters < ActiveRecord::Migration[7.1]
  def change
    change_table :news_claims, bulk: true do |t|
      t.float :extraction_confidence, null: false, default: 0.0
      t.float :actor_confidence, null: false, default: 0.0
      t.float :event_confidence, null: false, default: 0.0
      t.float :geo_confidence, null: false, default: 0.0
      t.float :source_reliability, null: false, default: 0.0
      t.string :verification_status, null: false, default: "unverified"
      t.string :geo_precision, null: false, default: "unknown"
      t.jsonb :provenance, null: false, default: {}
    end

    add_index :news_claims, :verification_status
    add_index :news_claims, :geo_precision

    change_table :news_story_clusters, bulk: true do |t|
      t.float :source_reliability, null: false, default: 0.0
      t.float :geo_confidence, null: false, default: 0.0
      t.jsonb :provenance, null: false, default: {}
    end
  end
end
