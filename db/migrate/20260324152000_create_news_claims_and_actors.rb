class CreateNewsClaimsAndActors < ActiveRecord::Migration[7.1]
  def change
    create_table :news_actors do |t|
      t.string :canonical_key, null: false
      t.string :name, null: false
      t.string :actor_type, null: false
      t.string :country_code
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :news_actors, :canonical_key, unique: true
    add_index :news_actors, :actor_type
    add_index :news_actors, :country_code

    create_table :news_claims do |t|
      t.references :news_article, null: false, foreign_key: true
      t.string :event_type, null: false
      t.text :claim_text
      t.float :confidence
      t.string :extraction_method, null: false, default: "heuristic"
      t.string :extraction_version, null: false, default: "headline_rules_v1"
      t.datetime :published_at
      t.boolean :primary, null: false, default: true
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    remove_index :news_claims, :news_article_id
    add_index :news_claims, :news_article_id, unique: true
    add_index :news_claims, :event_type
    add_index :news_claims, :published_at

    create_table :news_claim_actors do |t|
      t.references :news_claim, null: false, foreign_key: true
      t.references :news_actor, null: false, foreign_key: true
      t.string :role, null: false
      t.integer :position, null: false
      t.float :confidence
      t.string :matched_text
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :news_claim_actors, [ :news_claim_id, :news_actor_id, :role ], unique: true, name: "idx_news_claim_actors_unique_role"
    add_index :news_claim_actors, [ :news_claim_id, :position ], unique: true, name: "idx_news_claim_actors_unique_position"
  end
end
