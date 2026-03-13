class CreateAlerts < ActiveRecord::Migration[7.1]
  def change
    create_table :alerts do |t|
      t.references :watch, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.jsonb :details, default: {}
      t.string :entity_type
      t.string :entity_id
      t.float :lat
      t.float :lng
      t.boolean :seen, default: false

      t.timestamps
    end

    add_index :alerts, [:user_id, :seen, :created_at]
  end
end
