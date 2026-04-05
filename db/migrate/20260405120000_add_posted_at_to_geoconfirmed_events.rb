class AddPostedAtToGeoconfirmedEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :geoconfirmed_events, :posted_at, :datetime
    add_index :geoconfirmed_events, :posted_at
  end
end
