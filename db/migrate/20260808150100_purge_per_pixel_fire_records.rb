class PurgePerPixelFireRecords < ActiveRecord::Migration[7.1]
  # Fires used to be recorded one row per satellite PIXEL rather than per fire.
  # That left production with 490,383 timeline events and 155,579 ontology
  # events for roughly 25,000 real fires -- fires were 99% of the timeline, and
  # "disaster/fire_hotspot" was the largest event family in the graph despite
  # not one of its rows being a distinct fire.
  #
  # FireClusterService now records one timeline event and one ontology event per
  # fire complex, with each satellite pass linked as evidence. These rows are
  # superseded, so they go. Irreversible by design: the replacements are rebuilt
  # from fire_hotspots on the next poll, and restoring the per-pixel rows would
  # only recreate the flood.
  def up
    say_with_time "removing per-pixel fire timeline events" do
      TimelineEvent.where(event_type: "fire", eventable_type: "FireHotspot").delete_all
    end

    say_with_time "removing per-pixel fire ontology events and their links" do
      # Batched: this is ~155k rows and the delete cascades through two tables.
      total = 0
      loop do
        ids = OntologyEvent.where(event_family: "disaster", event_type: "fire_hotspot")
                           .limit(5_000).pluck(:id)
        break if ids.empty?

        OntologyEvidenceLink.where(ontology_event_id: ids).delete_all
        OntologyEventEntity.where(ontology_event_id: ids).delete_all if defined?(OntologyEventEntity)
        OntologyRelationship.where(source_node_type: "OntologyEvent", source_node_id: ids).delete_all
        OntologyRelationship.where(target_node_type: "OntologyEvent", target_node_id: ids).delete_all
        total += OntologyEvent.where(id: ids).delete_all
      end
      total
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
