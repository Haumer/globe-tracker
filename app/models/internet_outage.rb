class InternetOutage < ApplicationRecord
  include TimeRangeQueries

  has_many :timeline_events, as: :eventable, dependent: :destroy
  has_many :ontology_entity_links, as: :linkable, dependent: :delete_all
  has_many :ontology_evidence_links, as: :evidence, dependent: :delete_all

  time_range_column :started_at, recent: 24.hours
end
