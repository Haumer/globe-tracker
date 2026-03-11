class CreateConflictEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :conflict_events do |t|
      t.integer :external_id, null: false
      t.string :conflict_name
      t.string :side_a
      t.string :side_b
      t.string :country
      t.string :region
      t.string :where_description
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.date :date_start
      t.date :date_end
      t.integer :best_estimate, default: 0
      t.integer :deaths_a, default: 0
      t.integer :deaths_b, default: 0
      t.integer :deaths_civilians, default: 0
      t.integer :type_of_violence
      t.string :source_headline
      t.timestamps
    end

    add_index :conflict_events, :external_id, unique: true
    add_index :conflict_events, :date_start
    add_index :conflict_events, [:latitude, :longitude]
    add_index :conflict_events, :type_of_violence
  end
end
