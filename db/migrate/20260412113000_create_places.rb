class CreatePlaces < ActiveRecord::Migration[7.1]
  def change
    create_table :places do |t|
      t.string :canonical_key, null: false
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.string :place_type, default: "city", null: false
      t.string :country_code
      t.string :country_name
      t.string :admin_area
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.integer :population
      t.float :importance_score, default: 0.0, null: false
      t.string :source, default: "seed", null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :places, :canonical_key, unique: true
    add_index :places, [:normalized_name, :country_code]
    add_index :places, [:place_type, :country_code]
    add_index :places, :source

    create_table :place_aliases do |t|
      t.references :place, null: false, foreign_key: true
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.string :alias_type, default: "common", null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :place_aliases, :normalized_name
    add_index :place_aliases, [:place_id, :normalized_name], unique: true
  end
end
