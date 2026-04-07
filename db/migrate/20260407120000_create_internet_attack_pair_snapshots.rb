class CreateInternetAttackPairSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :internet_attack_pair_snapshots do |t|
      t.string :origin_country_code, null: false
      t.string :target_country_code, null: false
      t.string :origin_country_name
      t.string :target_country_name
      t.float :attack_pct
      t.datetime :recorded_at, null: false
      t.timestamps
    end

    add_index :internet_attack_pair_snapshots,
              [:origin_country_code, :target_country_code, :recorded_at],
              name: "idx_attack_pair_snapshots_route_time"
    add_index :internet_attack_pair_snapshots, :recorded_at
  end
end
