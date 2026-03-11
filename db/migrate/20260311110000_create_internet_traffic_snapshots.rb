class CreateInternetTrafficSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :internet_traffic_snapshots do |t|
      t.string :country_code, null: false
      t.string :country_name
      t.float :traffic_pct
      t.float :attack_origin_pct
      t.float :attack_target_pct
      t.datetime :recorded_at, null: false
      t.timestamps
    end

    add_index :internet_traffic_snapshots, [:country_code, :recorded_at]
    add_index :internet_traffic_snapshots, :recorded_at
  end
end
