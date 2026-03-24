class AddEventFamilyToNewsClaims < ActiveRecord::Migration[7.1]
  def change
    add_column :news_claims, :event_family, :string, null: false, default: "general"
    add_index :news_claims, :event_family
  end
end
