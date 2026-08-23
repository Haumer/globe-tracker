# Whether a story currently carries more than its normal attention.
#
# "Normal" is the situation's own trailing rate, not a global constant: Ukraine
# filing thirty reports today is routine, a quiet border town filing eight is
# an alarm. The same arithmetic runs in two places -- SituationHistoryService
# persists the verdict at build time (so flare moments survive for replay) and
# SituationBoardService recomputes it live per payload (so the state on screen
# is current between builds) -- which is why it lives in a module both call
# rather than in either.
#
# A state, not an event: recomputed from current rates every time, so a story
# that flares, cools and rekindles reads flaring / active / flaring again with
# no memory needed beyond its history.
module SituationAttention
  RECENT_HOURS = 6
  BASELINE_DAYS = 7
  # A situation too young to have a baseline gets this stand-in daily rate.
  # It keeps the ratio finite; the absolute floors below are what actually
  # gate a young story's first flare.
  BASELINE_FLOOR_PER_DAY = 2.0
  FLARE_RATIO = 3.0
  # One wire echoing ten times is volume, not attention. A flare needs both
  # enough reports and corroboration -- outlets filing their FIRST report on
  # the story inside the recent window.
  FLARE_MIN_ARTICLES = 3
  FLARE_MIN_SOURCES = 2
  ACTIVE_HOURS = 12

  module_function

  # rows: [{published_at:, source_id:}], already scoped to the situation
  # window. new-source counting matches the board timeline's semantics: a
  # source is "new" when its earliest in-window report falls in the recent
  # cut, so both readers of the payload agree on what corroboration means.
  def observe(rows, now:)
    stamped = rows.select { |row| row[:published_at] }
    recent_cut = now - RECENT_HOURS.hours

    {
      recent_articles: stamped.count { |row| row[:published_at] > recent_cut },
      recent_sources: stamped.group_by { |row| row[:source_id] }
        .count { |_, list| list.map { |row| row[:published_at] }.min > recent_cut },
      last_seen_at: stamped.map { |row| row[:published_at] }.max
    }
  end

  # {"2026-08-23" => {"a" => articles, "s" => new_sources}} for each day a row
  # landed in. Days are UTC dates of published_at.
  def daily_tallies(rows, now:)
    stamped = rows.select { |row| row[:published_at] }
    days = Hash.new { |hash, key| hash[key] = { "a" => 0, "s" => 0 } }
    stamped.each { |row| days[row[:published_at].utc.to_date.iso8601]["a"] += 1 }
    stamped.group_by { |row| row[:source_id] }.each_value do |list|
      days[list.map { |row| row[:published_at] }.min.utc.to_date.iso8601]["s"] += 1
    end
    days.default = nil
    days
  end

  # Mean daily reports over the trailing week of recorded history, today
  # excluded -- today is what is being judged against it.
  def baseline_daily(history, today:)
    past = history.to_h.keys.select { |day| day < today.iso8601 }.sort.last(BASELINE_DAYS)
    return BASELINE_FLOOR_PER_DAY if past.empty?

    mean = past.sum { |day| history[day]["a"].to_i } / past.size.to_f
    [mean, BASELINE_FLOOR_PER_DAY].max
  end

  def assess(observation, baseline_daily:, now:)
    expected_recent = baseline_daily * RECENT_HOURS / 24.0
    ratio = observation[:recent_articles] / expected_recent

    flaring = ratio >= FLARE_RATIO &&
      observation[:recent_articles] >= FLARE_MIN_ARTICLES &&
      observation[:recent_sources] >= FLARE_MIN_SOURCES
    active = observation[:last_seen_at] &&
      observation[:last_seen_at] > now - ACTIVE_HOURS.hours

    { state: flaring ? "flaring" : active ? "active" : "quiet", ratio: ratio.round(2) }
  end
end
