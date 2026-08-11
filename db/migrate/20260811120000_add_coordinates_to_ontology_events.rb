class AddCoordinatesToOntologyEvents < ActiveRecord::Migration[7.1]
  # Location lived only at place_entity_id -> ontology_entities.metadata, a JSONB
  # document with no index on it, so "events near here" could not be asked
  # without a sequential scan over 606k entities. The coordinate is a property of
  # where the event happened, not of the place node it happens to share with
  # other events, so it belongs on the event.
  #
  # Composite btree over (latitude, longitude) to match every other geo table
  # here (fire_hotspots, conflict_events, power_plants). No PostGIS in this
  # database; a bounding box on the leading column is what the callers ask for.
  def change
    add_column :ontology_events, :latitude, :float
    add_column :ontology_events, :longitude, :float
    add_index :ontology_events, [:latitude, :longitude]
  end
end
