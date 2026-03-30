class AddAssigneeToInvestigationCases < ActiveRecord::Migration[7.1]
  def up
    add_reference :investigation_cases, :assignee, foreign_key: { to_table: :users }
    execute <<~SQL.squish
      UPDATE investigation_cases
      SET assignee_id = user_id
      WHERE assignee_id IS NULL
    SQL
  end

  def down
    remove_reference :investigation_cases, :assignee, foreign_key: { to_table: :users }
  end
end
