# Each situation's biography, kept on its own row.
#
# The builder's window decides membership -- which clusters still belong -- and
# stays at three days. But a situation's row persists across builds under a
# stable canonical_key, and upsert_entity merges metadata, so keys written
# here survive every rebuild untouched. This service folds each build's
# per-day report tallies into that row: a long-running situation accumulates
# weeks of history automatically, a two-day flare-up keeps a two-day one, and
# when a situation leaves the board its history dies with it. That bounds
# replay honestly: the scrubber shows the biography of what is on the board,
# not a record of situations that died before today.
#
# Also the flare recorder. Attention is a state (SituationAttention), but
# replay needs the moments it fired, so a quiet-to-flaring edge is stamped
# into the flares list -- rate-limited by a refractory gap so a story that
# burns for a day reads as a few pulses, not a strobe.
#
# Runs from BuildSituationsJob right after the builder, before the layer warm
# rebuilds the board cache -- so the board a user reads always embeds the
# history this run just wrote.
class SituationHistoryService
  HISTORY_DAYS = 60
  MAX_FLARES = 40
  FLARE_REFRACTORY = 6.hours

  def self.call(now: Time.current)
    new(now: now).call
  end

  def initialize(now: Time.current)
    @now = now
  end

  def call
    flares_recorded = 0

    situations.each do |situation|
      rows = window_rows_for(situation.id)
      history = merged_history(situation, rows)
      observation = SituationAttention.observe(rows, now: now)
      assessment = SituationAttention.assess(
        observation,
        baseline_daily: SituationAttention.baseline_daily(history, today: now.utc.to_date),
        now: now
      )

      flares = situation.metadata["flares"].to_a
      if assessment[:state] == "flaring" && refractory_clear?(flares)
        flares = (flares + [now.utc.iso8601]).last(MAX_FLARES)
        flares_recorded += 1
      end

      situation.update!(metadata: situation.metadata.merge(
        "history" => history,
        "flares" => flares,
        "attention" => {
          "state" => assessment[:state],
          "ratio" => assessment[:ratio],
          "computed_at" => now.utc.iso8601
        }
      ))
    end

    { situations: situations.size, flares_recorded: flares_recorded }
  end

  private

  attr_reader :now

  def situations
    @situations ||= OntologyEntity.where(entity_type: SituationBuilder::ENTITY_TYPE).to_a
  end

  # Window days are recomputed from articles every run -- late-arriving
  # reports amend recent days -- while days that have left the window keep
  # their stored tallies. Oldest days fall off past the cap.
  def merged_history(situation, rows)
    history = situation.metadata["history"].to_h
      .merge(SituationAttention.daily_tallies(rows, now: now))
    history.keys.sort.last(HISTORY_DAYS).to_h { |day| [day, history[day]] }
  end

  def refractory_clear?(flares)
    last = flares.last
    last.nil? || Time.zone.parse(last) < now - FLARE_REFRACTORY
  end

  # The board's join, in miniature: memberships -> events -> clusters ->
  # article stamps, scoped to the builder window like the board timeline --
  # stamps outside it are republication noise.
  def window_rows_for(situation_id)
    cluster_ids = member_cluster_ids[situation_id].to_a
    window_start = now - SituationBuilder::WINDOW_DAYS.days

    cluster_ids.flat_map { |id| article_rows_by_cluster[id] }
      .select { |row| row[:published_at]&.between?(window_start, now) }
  end

  def member_cluster_ids
    @member_cluster_ids ||= begin
      memberships = OntologyEventEntity
        .where(ontology_entity_id: situations.map(&:id), role: SituationBuilder::MEMBERSHIP_ROLE)
        .pluck(:ontology_entity_id, :ontology_event_id)
      events = OntologyEvent.where(id: memberships.map(&:last).uniq)
        .pluck(:id, :primary_story_cluster_id).to_h

      memberships.group_by(&:first)
        .transform_values { |rows| rows.filter_map { |_, event_id| events[event_id] }.uniq }
        .tap { |hash| hash.default = [] }
    end
  end

  def article_rows_by_cluster
    @article_rows_by_cluster ||= NewsStoryMembership
      .where(news_story_cluster_id: member_cluster_ids.values.flatten.uniq)
      .joins(:news_article)
      .pluck(:news_story_cluster_id, Arel.sql("news_articles.published_at"),
             Arel.sql("news_articles.news_source_id"))
      .group_by(&:first)
      .transform_values do |list|
        list.map { |_, at, source_id| { published_at: at, source_id: source_id } }
      end
      .tap { |hash| hash.default = [] }
  end
end
