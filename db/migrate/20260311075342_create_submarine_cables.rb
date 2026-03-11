class CreateSubmarineCables < ActiveRecord::Migration[7.1]
  def change
    create_table :submarine_cables do |t|
      t.string :cable_id
      t.string :name
      t.string :color
      t.jsonb :coordinates
      t.jsonb :landing_points
      t.datetime :fetched_at

      t.timestamps
    end
    add_index :submarine_cables, :cable_id, unique: true
  end
end
