class CreateTrainIngestsAndObservations < ActiveRecord::Migration[7.1]
  def change
    create_table :train_ingests do |t|
      t.string :source_key, null: false
      t.string :source_name, null: false
      t.string :status, null: false, default: "fetched"
      t.string :error_code
      t.jsonb :request_metadata, null: false, default: {}
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :train_ingests, :source_key
    add_index :train_ingests, :status
    add_index :train_ingests, :fetched_at

    create_table :train_observations do |t|
      t.string :external_id, null: false
      t.references :train_ingest, foreign_key: true
      t.string :source, null: false, default: "hafas"
      t.string :operator_key
      t.string :operator_name
      t.string :name
      t.string :category
      t.string :category_long
      t.string :flag
      t.float :latitude
      t.float :longitude
      t.string :direction
      t.integer :progress
      t.jsonb :raw_payload, null: false, default: {}
      t.datetime :fetched_at, null: false
      t.datetime :expires_at

      t.timestamps
    end

    add_index :train_observations, :external_id, unique: true
    add_index :train_observations, :operator_key
    add_index :train_observations, :fetched_at
    add_index :train_observations, :expires_at
  end
end
