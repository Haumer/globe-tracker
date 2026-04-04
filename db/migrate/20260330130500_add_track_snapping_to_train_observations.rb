class AddTrackSnappingToTrainObservations < ActiveRecord::Migration[7.1]
  def change
    add_reference :train_observations, :matched_railway, foreign_key: { to_table: :railways }
    add_column :train_observations, :snapped_latitude, :float
    add_column :train_observations, :snapped_longitude, :float
    add_column :train_observations, :snap_distance_m, :float
    add_column :train_observations, :snap_confidence, :string

    add_index :train_observations, :snap_confidence
  end
end
