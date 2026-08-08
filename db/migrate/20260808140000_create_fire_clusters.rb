class CreateFireClusters < ActiveRecord::Migration[7.1]
  def change
    create_table :fire_clusters do |t|
      t.string :external_id, null: false
      t.float :latitude, null: false
      t.float :longitude, null: false

      # Peak single-pass FRP sum. Never the sum across passes -- a fire seen on
      # 15 satellite passes would otherwise report 15x its real intensity.
      t.float :intensity_mw, null: false, default: 0.0
      t.float :latest_mw, null: false, default: 0.0
      t.string :tier, null: false

      t.integer :pixel_count, null: false, default: 0
      t.integer :pass_count, null: false, default: 0
      t.integer :detection_count, null: false, default: 0

      t.datetime :first_detected_at
      t.datetime :last_detected_at
      t.jsonb :satellites, null: false, default: []

      t.float :min_latitude
      t.float :max_latitude
      t.float :min_longitude
      t.float :max_longitude

      t.datetime :computed_at, null: false

      t.timestamps
    end

    add_index :fire_clusters, :external_id, unique: true
    add_index :fire_clusters, :tier
    add_index :fire_clusters, :intensity_mw
    add_index :fire_clusters, :last_detected_at
    add_index :fire_clusters, [:latitude, :longitude]
  end
end
