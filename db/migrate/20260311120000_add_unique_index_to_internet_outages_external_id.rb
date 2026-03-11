class AddUniqueIndexToInternetOutagesExternalId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL.squish
      DELETE FROM internet_outages a
      USING internet_outages b
      WHERE a.id < b.id
        AND a.external_id = b.external_id
        AND a.external_id IS NOT NULL
    SQL

    add_index :internet_outages, :external_id, unique: true, algorithm: :concurrently
  end

  def down
    remove_index :internet_outages, :external_id
  end
end
