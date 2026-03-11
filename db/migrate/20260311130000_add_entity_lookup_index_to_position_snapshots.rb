class AddEntityLookupIndexToPositionSnapshots < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :position_snapshots,
              [:entity_type, :entity_id, :recorded_at],
              order: { recorded_at: :desc },
              name: "idx_position_snapshots_entity_lookup",
              algorithm: :concurrently
  end
end
