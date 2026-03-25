class CreateOntologyRelationships < ActiveRecord::Migration[7.1]
  def change
    create_table :ontology_relationships do |t|
      t.string :source_node_type, null: false
      t.bigint :source_node_id, null: false
      t.string :target_node_type, null: false
      t.bigint :target_node_id, null: false
      t.string :relation_type, null: false
      t.float :confidence, null: false, default: 0.0
      t.datetime :fresh_until
      t.string :derived_by, null: false, default: "sync"
      t.text :explanation
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ontology_relationships, [:source_node_type, :source_node_id], name: "idx_ontology_relationships_source"
    add_index :ontology_relationships, [:target_node_type, :target_node_id], name: "idx_ontology_relationships_target"
    add_index :ontology_relationships,
      [:source_node_type, :source_node_id, :target_node_type, :target_node_id, :relation_type],
      unique: true,
      name: "idx_ontology_relationships_unique_type"
    add_index :ontology_relationships, :fresh_until

    create_table :ontology_relationship_evidences do |t|
      t.references :ontology_relationship, null: false, foreign_key: true
      t.string :evidence_type, null: false
      t.bigint :evidence_id, null: false
      t.string :evidence_role, null: false, default: "supporting"
      t.float :confidence, null: false, default: 1.0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ontology_relationship_evidences,
      [:evidence_type, :evidence_id],
      name: "idx_ontology_relationship_evidences_lookup"
    add_index :ontology_relationship_evidences,
      [:ontology_relationship_id, :evidence_type, :evidence_id, :evidence_role],
      unique: true,
      name: "idx_ontology_relationship_evidences_unique_role"
  end
end
