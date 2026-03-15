class CreateWeatherAlerts < ActiveRecord::Migration[7.1]
  def change
    create_table :weather_alerts do |t|
      t.string  :external_id, null: false
      t.string  :event
      t.string  :severity
      t.string  :urgency
      t.string  :certainty
      t.string  :headline
      t.text    :description
      t.string  :areas
      t.string  :sender
      t.datetime :onset
      t.datetime :expires
      t.float   :latitude
      t.float   :longitude
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :weather_alerts, :external_id, unique: true
    add_index :weather_alerts, :onset
    add_index :weather_alerts, :fetched_at
    add_index :weather_alerts, [:latitude, :longitude]
  end
end
