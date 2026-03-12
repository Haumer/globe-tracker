class CreateWorkspaces < ActiveRecord::Migration[7.1]
  def change
    create_table :workspaces do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.float :camera_lat
      t.float :camera_lng
      t.float :camera_height
      t.float :camera_heading
      t.float :camera_pitch
      t.jsonb :layers, default: {}
      t.jsonb :filters, default: {}
      t.boolean :is_default, default: false
      t.boolean :shared, default: false
      t.string :slug

      t.timestamps
    end

    add_index :workspaces, :slug, unique: true
    add_index :workspaces, [:user_id, :is_default]
  end
end
