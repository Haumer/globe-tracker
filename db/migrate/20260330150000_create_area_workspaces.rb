class CreateAreaWorkspaces < ActiveRecord::Migration[7.1]
  def change
    create_table :area_workspaces do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :scope_type, null: false
      t.jsonb :bounds, null: false, default: {}
      t.jsonb :scope_metadata, null: false, default: {}
      t.string :profile, null: false, default: "general"
      t.jsonb :default_layers, null: false, default: []

      t.timestamps
    end

    add_index :area_workspaces, :scope_type
    add_index :area_workspaces, :profile
    add_index :area_workspaces, [:user_id, :updated_at]
  end
end
