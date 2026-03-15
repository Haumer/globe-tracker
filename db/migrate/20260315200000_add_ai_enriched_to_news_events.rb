class AddAiEnrichedToNewsEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :news_events, :ai_enriched, :boolean, default: false
    add_index :news_events, :ai_enriched
  end
end
