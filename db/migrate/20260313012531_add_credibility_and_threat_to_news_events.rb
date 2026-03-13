class AddCredibilityAndThreatToNewsEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :news_events, :credibility, :string
    add_column :news_events, :threat_level, :string
  end
end
