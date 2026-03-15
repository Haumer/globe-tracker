class CreateNotams < ActiveRecord::Migration[7.1]
  def change
    create_table :notams do |t|
      t.string  :external_id, null: false
      t.string  :source                    # "faa" or "openaip"
      t.float   :latitude
      t.float   :longitude
      t.float   :radius_nm
      t.integer :radius_m
      t.integer :alt_low_ft
      t.integer :alt_high_ft
      t.string  :reason
      t.string  :text
      t.string  :country
      t.datetime :effective_start
      t.datetime :effective_end
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :notams, :external_id, unique: true
    add_index :notams, :effective_start
    add_index :notams, :fetched_at
    add_index :notams, [:latitude, :longitude]
  end
end
