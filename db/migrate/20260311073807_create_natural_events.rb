class CreateNaturalEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :natural_events do |t|
      t.string :external_id
      t.string :title
      t.string :category_id
      t.string :category_title
      t.float :latitude
      t.float :longitude
      t.datetime :event_date
      t.float :magnitude_value
      t.string :magnitude_unit
      t.string :link
      t.jsonb :sources
      t.jsonb :geometry_points
      t.datetime :fetched_at

      t.timestamps
    end
    add_index :natural_events, :external_id, unique: true
    add_index :natural_events, :event_date
    add_index :natural_events, :fetched_at
  end
end
