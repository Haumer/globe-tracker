class AddStoryClusterIdToNewsEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :news_events, :story_cluster_id, :string
    add_index :news_events, :story_cluster_id
  end
end
