class CreateServiceRuntimeStates < ActiveRecord::Migration[7.1]
  def change
    create_table :service_runtime_states do |t|
      t.string :service_name, null: false
      t.string :desired_state, null: false, default: "running"
      t.string :reported_state, null: false, default: "stopped"
      t.datetime :reported_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :service_runtime_states, :service_name, unique: true
  end
end
