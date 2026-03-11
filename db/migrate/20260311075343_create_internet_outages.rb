class CreateInternetOutages < ActiveRecord::Migration[7.1]
  def change
    create_table :internet_outages do |t|
      t.string :external_id
      t.string :entity_type
      t.string :entity_code
      t.string :entity_name
      t.string :datasource
      t.float :score
      t.string :level
      t.string :condition
      t.datetime :started_at
      t.datetime :ended_at
      t.datetime :fetched_at

      t.timestamps
    end
    add_index :internet_outages, [:entity_type, :entity_code, :started_at], name: "idx_outages_entity_time"
    add_index :internet_outages, :fetched_at
    add_index :internet_outages, :started_at
  end
end
