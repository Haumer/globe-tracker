# What a saga hides in a flat member list: its threads. A rich situation is
# rarely one event -- Hormuz is a negotiation spine, a series of tanker
# attacks, economic fallout and diplomatic periphery -- and a newest-first
# list interleaves all of it into noise. Members group by what their claims
# say the event IS (the extraction already typed every cluster); the closed
# set of thread kinds keeps the grouping explainable, the client's color
# legend finite, and the curator's dek anchorable (one sentence per thread).
#
# Duplicates are folded here too: the clusterer sometimes fails to merge
# republications of one story (".iran Makes New Strait Hormuz Demands"
# appeared as four separate clusters), so members with identical normalized
# headlines collapse -- the strongest row survives and carries the count,
# the rest are tagged duplicate_of and hidden by the client. Report totals
# keep every article: the articles are real, it is the story rows that were
# inflated.
class SituationThreads
  KINDS = {
    "kinetic" => { label: "Attacks & operations",
      types: %w[missile_attack airstrike drone_strike strike ground_operation
                shelling explosion attack raid clash offensive naval_incident
                sabotage ambush bombing] },
    "talks" => { label: "Talks & diplomacy",
      types: %w[negotiation agreement ceasefire summit mediation statement
                prisoner_exchange treaty] },
    "pressure" => { label: "Pressure & sanctions",
      types: %w[sanction_action blockade mobilization threat protest ultimatum] },
    "human" => { label: "Human cost & aid",
      types: %w[aid_delivery evacuation displacement casualty rescue] },
    "hazard" => { label: "Hazard & response",
      types: %w[earthquake flood wildfire storm eruption landslide outbreak] },
  }.freeze

  # A type the closed set does not know falls back to its claim family; a
  # member with no claim at all is context, not a guess.
  FAMILY_FALLBACK = {
    "conflict" => "kinetic",
    "diplomacy" => "talks",
    "disaster" => "hazard",
    "aid" => "human",
    "unrest" => "pressure",
  }.freeze

  CONTEXT = "context".freeze
  CONTEXT_LABEL = "Context & commentary".freeze

  # Below five live members, or without at least two threads that have two
  # members each, the grouping is a taxonomy in search of a story -- the
  # flat list serves better and the payload says so with nil.
  MIN_MEMBERS = 5
  MIN_POPULATED_THREADS = 2

  # Tags each member in place (:thread, :duplicate_of, :duplicates) and
  # returns the thread summary rows, or nil when the situation is
  # single-thread or too thin to group.
  def self.call(members)
    new(members).call
  end

  def initialize(members)
    @members = members
  end

  def call
    fold_duplicates
    live = @members.reject { |member| member[:duplicate_of] }
    live.each { |member| member[:thread] = thread_for(member) }
    return nil if live.size < MIN_MEMBERS

    groups = live.group_by { |member| member[:thread] }
    return nil if groups.count { |_, list| list.size >= 2 } < MIN_POPULATED_THREADS

    rows = groups.map do |key, list|
      { key: key,
        label: key == CONTEXT ? CONTEXT_LABEL : KINDS[key][:label],
        story_count: list.size,
        article_count: list.sum { |member| member[:article_count].to_i },
        last_seen_at: list.filter_map { |member| member[:last_seen_at] }.max }
    end

    # Context trails regardless of size: it is the periphery by definition.
    rows.sort_by { |row| [ row[:key] == CONTEXT ? 1 : 0, -row[:story_count] ] }
  end

  private

  def fold_duplicates
    @members.group_by { |member| normalize(member[:headline]) }.each_value do |list|
      next if list.size < 2 || list.first[:headline].blank?

      survivor = list.max_by { |member| member[:article_count].to_i }
      folded = list - [ survivor ]
      folded.each { |member| member[:duplicate_of] = survivor[:cluster_id] }
      survivor[:duplicates] = folded.size
    end
  end

  def normalize(headline)
    headline.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def thread_for(member)
    type = member.dig(:claim, :type) || member[:event_type]
    family = member.dig(:claim, :family) || member[:event_family]

    KINDS.each { |key, kind| return key if kind[:types].include?(type.to_s) }
    FAMILY_FALLBACK[family.to_s] || CONTEXT
  end
end
