class CreateMilitaryBases < ActiveRecord::Migration[7.1]
  def change
    create_table :military_bases do |t|
      t.string :external_id, null: false
      t.string :name
      t.string :base_type
      t.string :country
      t.string :operator
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.string :source
      t.jsonb :metadata, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :military_bases, :external_id, unique: true
    add_index :military_bases, [:latitude, :longitude]
  end
end
