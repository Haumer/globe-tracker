class OntologyV2BackfillService
  STAGES = %w[
    identity
    asset_airports
    asset_military_bases
    asset_power_plants
    asset_ports
    asset_submarine_cables
    event_graph
    infrastructure_impact
  ].freeze
  ASSET_STAGE_TARGETS = {
    "asset_airports" => "airports",
    "asset_military_bases" => "military_bases",
    "asset_power_plants" => "power_plants",
    "asset_ports" => "ports",
    "asset_submarine_cables" => "submarine_cables",
  }.freeze
  # Two chains, split by how fast the underlying data actually moves.
  #
  # The reference stages walk ~56,000 airport, base, power plant, port and cable
  # rows whose source tables refresh every 12-24 hours. The live stages derive
  # from events that arrive continuously and want to be minutes old, not hours.
  #
  # Chaining runs within a group, never across it, so a live pass cannot end up
  # queued behind 56,000 rows of static reference data -- which is exactly how
  # the old arrangement buried everything after its fourth stage.
  STAGE_GROUPS = {
    "reference" => %w[
      identity
      asset_airports
      asset_military_bases
      asset_power_plants
      asset_ports
      asset_submarine_cables
    ].freeze,
    "live" => %w[
      event_graph
      infrastructure_impact
    ].freeze,
  }.freeze

  PROVIDER = "ontology-v2".freeze
  FEED_KIND = "ontology".freeze

  def self.group_for(stage)
    STAGE_GROUPS.find { |_name, stages| stages.include?(stage.to_s) }&.first
  end

  class << self
    def run(stage: STAGES.first, cursor: nil, batch_size: 500, now: Time.current)
      new(now: now).run(stage: stage, cursor: cursor, batch_size: batch_size)
    end
  end

  def initialize(now: Time.current)
    @now = now
  end

  def run(stage:, cursor: nil, batch_size: 500)
    stage = stage.to_s
    raise ArgumentError, "unknown ontology v2 backfill stage: #{stage}" unless STAGES.include?(stage)

    result = normalize_stage_result(stage: stage, cursor: cursor, payload: run_stage(stage, cursor: cursor, batch_size: batch_size))
    record_feed_status(stage: stage, status: "success", result: result)
    result
  rescue StandardError => e
    record_feed_status(stage: stage, status: "error", error: e) if stage.present?
    raise
  end

  private

  attr_reader :now

  def run_stage(stage, cursor:, batch_size:)
    if stage == "identity"
      return sync_identity
    end

    if ASSET_STAGE_TARGETS.key?(stage)
      return OntologyV2AssetGraphService.sync_batch(
        target: ASSET_STAGE_TARGETS.fetch(stage),
        cursor: cursor,
        batch_size: batch_size,
        now: now
      )
    end

    case stage
    when "event_graph"
      OntologyV2EventGraphService.sync_batch(cursor: cursor, batch_size: batch_size, now: now)
    when "infrastructure_impact"
      OntologyV2InfrastructureImpactService.sync_batch(cursor: cursor, batch_size: batch_size, now: now)
    end
  end

  def sync_identity
    payload = OntologyV2IdentityService.sync(now: now)
    records_stored = payload.fetch(:actor_country_links).to_i + payload.fetch(:place_country_links).to_i
    records_fetched = payload.dig(:health, :state_actors).to_i + payload.dig(:health, :countries).to_i

    payload.merge(
      records_fetched: records_fetched,
      records_stored: records_stored,
      complete: true,
      next_cursor: nil
    )
  end

  def normalize_stage_result(stage:, cursor:, payload:)
    payload = (payload || {}).symbolize_keys
    complete = payload.key?(:complete) ? payload.fetch(:complete) : payload[:next_cursor].blank?

    {
      stage: stage,
      cursor: cursor,
      next_cursor: payload[:next_cursor],
      next_stage: complete ? next_stage_after(stage) : nil,
      complete: complete,
      records_fetched: payload[:records_fetched].to_i,
      records_stored: payload[:records_stored].to_i,
      synced_at: now.iso8601,
    }.merge(payload.except(:cursor, :next_cursor, :complete, :records_fetched, :records_stored))
  end

  # Advance only within the stage's own group, so a chain ends at its group
  # boundary rather than running on into work on a different cadence.
  def next_stage_after(stage)
    group = self.class.group_for(stage)
    return nil if group.nil?

    stages = STAGE_GROUPS.fetch(group)
    stages[stages.index(stage.to_s).to_i + 1]
  end

  def record_feed_status(stage:, status:, result: {}, error: nil)
    SourceFeedStatusRecorder.record(
      provider: PROVIDER,
      display_name: "Ontology v2 #{stage.to_s.tr("_", " ")}",
      feed_kind: FEED_KIND,
      endpoint_url: "ontology-v2://#{stage}",
      status: status,
      records_fetched: result[:records_fetched].to_i,
      records_stored: result[:records_stored].to_i,
      error_message: error&.message,
      metadata: {
        stage: stage,
        cursor: result[:cursor],
        next_cursor: result[:next_cursor],
        next_stage: result[:next_stage],
        complete: result[:complete],
      }.compact,
      occurred_at: now
    )
  end
end
