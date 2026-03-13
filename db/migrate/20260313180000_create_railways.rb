class CreateRailways < ActiveRecord::Migration[7.1]
  def change
    create_table :railways do |t|
      t.integer :category, default: 0
      t.integer :electrified, default: 0
      t.string :continent
      t.float :min_lat
      t.float :max_lat
      t.float :min_lng
      t.float :max_lng
      t.jsonb :coordinates, null: false, default: []
      t.timestamps
    end

    add_index :railways, [:min_lat, :max_lat, :min_lng, :max_lng], name: "idx_railways_bbox"
    add_index :railways, :continent
  end
end
