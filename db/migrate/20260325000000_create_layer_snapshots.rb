class CreateLayerSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :layer_snapshots do |t|
      t.string :snapshot_type, null: false
      t.string :scope_key, null: false, default: "global"
      t.string :status, null: false, default: "ready"
      t.string :error_code
      t.jsonb :payload, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :fetched_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :layer_snapshots, [:snapshot_type, :scope_key], unique: true
    add_index :layer_snapshots, :expires_at
    add_index :layer_snapshots, :status
  end
end
