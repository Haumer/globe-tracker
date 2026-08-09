class CreateFireObservations < ActiveRecord::Migration[7.1]
  def change
    create_table :fire_observations do |t|
      # One row per fire per satellite pass -- the evidence behind a cluster,
      # and the series you graph to see the fire evolve.
      t.references :fire_cluster, null: false, foreign_key: { on_delete: :cascade }
      t.string :external_id, null: false

      t.string :satellite
      t.string :instrument
      t.datetime :acq_datetime, null: false

      t.float :frp_mw, null: false, default: 0.0
      t.integer :pixel_count, null: false, default: 0

      # Per-pass centroid, so a spreading fire's movement is visible.
      t.float :latitude
      t.float :longitude

      t.timestamps
    end

    add_index :fire_observations, :external_id, unique: true
    add_index :fire_observations, [:fire_cluster_id, :acq_datetime]
    add_index :fire_observations, :acq_datetime
  end
end
