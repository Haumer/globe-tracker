class CreateCameras < ActiveRecord::Migration[7.1]
  def change
    create_table :cameras do |t|
      t.string  :webcam_id,    null: false
      t.string  :source,       null: false  # windy, youtube, nycdot
      t.string  :title
      t.float   :latitude,     null: false
      t.float   :longitude,    null: false
      t.string  :status,       default: "active"  # active, expired, dead
      t.string  :camera_type                       # live, timelapse, etc.
      t.boolean :is_live,      default: false
      t.string  :player_url
      t.string  :image_url
      t.string  :preview_url
      t.string  :city
      t.string  :region
      t.string  :country
      t.string  :video_id                          # YouTube video ID
      t.string  :channel_title                     # YouTube channel
      t.integer :view_count
      t.jsonb   :metadata,     default: {}
      t.datetime :last_checked_at
      t.datetime :fetched_at
      t.datetime :expires_at                       # computed from staleness tier

      t.timestamps
    end

    add_index :cameras, [:webcam_id, :source], unique: true, name: "idx_cameras_dedup"
    add_index :cameras, [:latitude, :longitude], name: "idx_cameras_geo"
    add_index :cameras, :source
    add_index :cameras, :status
    add_index :cameras, :fetched_at
    add_index :cameras, :expires_at
  end
end
