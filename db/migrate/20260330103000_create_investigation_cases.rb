class CreateInvestigationCases < ActiveRecord::Migration[7.1]
  def change
    create_table :investigation_cases do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :summary
      t.string :status, null: false, default: "open"
      t.string :severity, null: false, default: "medium"
      t.timestamps
    end
    add_index :investigation_cases, [:user_id, :status]
    add_index :investigation_cases, [:user_id, :updated_at]

    create_table :investigation_case_objects do |t|
      t.references :investigation_case, null: false, foreign_key: true
      t.string :object_kind, null: false
      t.string :object_identifier, null: false
      t.string :title, null: false
      t.text :summary
      t.string :object_type
      t.float :latitude
      t.float :longitude
      t.jsonb :source_context, null: false, default: {}
      t.timestamps
    end
    add_index :investigation_case_objects, [:investigation_case_id, :created_at], name: "idx_case_objects_case_created_at"
    add_index :investigation_case_objects, [:investigation_case_id, :object_kind, :object_identifier], unique: true, name: "idx_case_objects_unique_object"

    create_table :investigation_case_notes do |t|
      t.references :investigation_case, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.string :kind, null: false, default: "note"
      t.timestamps
    end
    add_index :investigation_case_notes, [:investigation_case_id, :created_at], name: "idx_case_notes_case_created_at"
  end
end
