class CreatePipelines < ActiveRecord::Migration[7.1]
  def change
    create_table :pipelines do |t|
      t.string :pipeline_id
      t.string :name
      t.string :pipeline_type
      t.string :status
      t.float :length_km
      t.jsonb :coordinates
      t.string :color
      t.string :country
      t.datetime :fetched_at

      t.timestamps
    end

    add_index :pipelines, :pipeline_id, unique: true
  end
end
