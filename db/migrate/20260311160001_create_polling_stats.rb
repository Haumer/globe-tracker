class CreatePollingStats < ActiveRecord::Migration[7.1]
  def change
    create_table :polling_stats do |t|
      t.string :source, null: false
      t.string :poll_type, null: false
      t.integer :records_fetched, default: 0
      t.integer :records_stored, default: 0
      t.integer :duration_ms, default: 0
      t.string :status, null: false
      t.text :error_message
      t.datetime :created_at, null: false
    end

    add_index :polling_stats, :created_at
    add_index :polling_stats, :source
  end
end
