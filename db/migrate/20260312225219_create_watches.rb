class CreateWatches < ActiveRecord::Migration[7.1]
  def change
    create_table :watches do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :watch_type, null: false
      t.jsonb :conditions, default: {}
      t.string :notify_via, default: "in_app"
      t.boolean :active, default: true
      t.datetime :last_triggered_at
      t.integer :cooldown_minutes, default: 15

      t.timestamps
    end

    add_index :watches, [:user_id, :active]
  end
end
