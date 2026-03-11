class CreateTimelineEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :timeline_events do |t|
      t.string :event_type, null: false
      t.string :eventable_type, null: false
      t.bigint :eventable_id, null: false
      t.float :latitude
      t.float :longitude
      t.datetime :recorded_at, null: false
      t.timestamps
    end

    add_index :timeline_events, :recorded_at
    add_index :timeline_events, [:event_type, :recorded_at]
    add_index :timeline_events, [:eventable_type, :eventable_id], unique: true
  end
end
