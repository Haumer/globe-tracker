class CreateOntologyLayer < ActiveRecord::Migration[7.1]
  def change
    create_table :ontology_entities do |t|
      t.string :canonical_key, null: false
      t.string :entity_type, null: false
      t.string :canonical_name, null: false
      t.string :country_code
      t.references :parent_entity, foreign_key: { to_table: :ontology_entities }
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ontology_entities, :canonical_key, unique: true
    add_index :ontology_entities, :entity_type
    add_index :ontology_entities, :country_code

    create_table :ontology_entity_aliases do |t|
      t.references :ontology_entity, null: false, foreign_key: true
      t.string :name, null: false
      t.string :alias_type, null: false, default: "common"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ontology_entity_aliases, [:ontology_entity_id, :name], unique: true, name: "idx_ontology_entity_aliases_unique_name"
    add_index :ontology_entity_aliases, :alias_type

    create_table :ontology_entity_links do |t|
      t.references :ontology_entity, null: false, foreign_key: true
      t.string :linkable_type, null: false
      t.bigint :linkable_id, null: false
      t.string :role, null: false
      t.float :confidence, null: false, default: 1.0
      t.string :method, null: false, default: "sync"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ontology_entity_links, [:linkable_type, :linkable_id], name: "idx_ontology_entity_links_linkable"
    add_index :ontology_entity_links, [:ontology_entity_id, :linkable_type, :linkable_id, :role],
      unique: true,
      name: "idx_ontology_entity_links_unique_role"

    create_table :ontology_events do |t|
      t.string :canonical_key, null: false
      t.string :event_family, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: "active"
      t.references :place_entity, foreign_key: { to_table: :ontology_entities }
      t.references :primary_story_cluster, foreign_key: { to_table: :news_story_clusters }
      t.string :verification_status, null: false, default: "unverified"
      t.string :geo_precision, null: false, default: "unknown"
      t.float :confidence, null: false, default: 0.0
      t.float :source_reliability, null: false, default: 0.0
      t.float :geo_confidence, null: false, default: 0.0
      t.datetime :started_at
      t.datetime :ended_at
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ontology_events, :canonical_key, unique: true
    add_index :ontology_events, [:event_family, :last_seen_at]
    add_index :ontology_events, :verification_status

    create_table :ontology_event_entities do |t|
      t.references :ontology_event, null: false, foreign_key: true
      t.references :ontology_entity, null: false, foreign_key: true
      t.string :role, null: false
      t.float :confidence, null: false, default: 1.0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ontology_event_entities, [:ontology_event_id, :ontology_entity_id, :role],
      unique: true,
      name: "idx_ontology_event_entities_unique_role"

    create_table :ontology_evidence_links do |t|
      t.references :ontology_event, null: false, foreign_key: true
      t.string :evidence_type, null: false
      t.bigint :evidence_id, null: false
      t.string :evidence_role, null: false, default: "supporting"
      t.float :confidence, null: false, default: 1.0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ontology_evidence_links, [:evidence_type, :evidence_id], name: "idx_ontology_evidence_links_evidence"
    add_index :ontology_evidence_links, [:ontology_event_id, :evidence_type, :evidence_id, :evidence_role],
      unique: true,
      name: "idx_ontology_evidence_links_unique_role"
  end
end
