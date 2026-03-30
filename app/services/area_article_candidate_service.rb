class AreaArticleCandidateService
  SOURCE_WEIGHTS = {
    "wire" => 1.0,
    "publisher" => 0.78,
    "aggregator" => 0.42,
    "platform" => 0.25,
  }.freeze

  AREA_TERM_ALIASES = {
    /hormuz/i => ["hormuz", "strait of hormuz"],
    /bab el[- ]mandeb|bab al[- ]mandab/i => ["bab el-mandeb", "bab al-mandab", "red sea chokepoint"],
    /bosporus/i => ["bosporus", "bosphorus"],
    /suez/i => ["suez canal", "suez"],
    /malacca/i => ["strait of malacca", "malacca"],
  }.freeze

  PROFILE_KEYWORDS = {
    "maritime" => %w[ship ships vessel vessels tanker tankers maritime transit passage toll tolls fee fees reroute rerouting corridor chokepoint convoy navy mine mines insurance]
  }.freeze

  FORCE_HYDRATION_LIMIT = 6

  def initialize(area_workspace, bounds:, limit: 12)
    @area_workspace = area_workspace
    @bounds = bounds
    @limit = limit
  end

  def call
    @call ||= ranked_candidates.first(@limit)
  end

  def enqueue_hydration!
    RssArticleHydrationService.enqueue_area_candidates(
      call.map { |candidate| candidate[:event] }.first(FORCE_HYDRATION_LIMIT),
      reason: "area_candidate:#{@area_workspace.profile}"
    )
  end

  def area_terms
    @area_terms ||= begin
      base_terms = [@area_workspace.name, @area_workspace.region_name].compact.map { |value| clean_text(value).downcase }.reject(&:blank?)
      alias_terms = AREA_TERM_ALIASES.each_with_object([]) do |(matcher, terms), memo|
        memo.concat(terms) if base_terms.any? { |value| value.match?(matcher) }
      end

      (base_terms + alias_terms).uniq
    end
  end

  private

  def ranked_candidates
    merged_events.values.map do |event|
      text = candidate_text(event)
      named_match_terms = area_terms.select { |term| text.include?(term) }
      profile_hits = profile_keywords.select { |keyword| text.include?(keyword) }

      {
        event: event,
        text: text,
        named_match_terms: named_match_terms,
        profile_hits: profile_hits,
        score: candidate_score(event, named_match_terms: named_match_terms, profile_hits: profile_hits),
      }
    end.sort_by { |candidate| [-candidate[:score], -(candidate[:event].published_at&.to_i || 0)] }
  end

  def merged_events
    @merged_events ||= begin
      merged = {}
      scoped_news_scope.each { |event| merged[event.id] = event }
      named_news_scope.each { |event| merged[event.id] = event }
      merged
    end
  end

  def scoped_news_scope
    @scoped_news_scope ||= NewsEvent
      .within_bounds(@bounds)
      .where("published_at > ?", 36.hours.ago)
      .where.not(content_scope: "out_of_scope")
      .includes(:news_article, :news_source)
      .order(published_at: :desc)
      .limit(40)
  end

  def named_news_scope
    return NewsEvent.none if area_terms.empty?

    fragments = []
    bindings = {}
    area_terms.each_with_index do |term, index|
      key = :"term_#{index}"
      bindings[key] = "%#{term.downcase}%"
      fragments << "(lower(news_events.title) LIKE :#{key} OR lower(coalesce(news_articles.summary, '')) LIKE :#{key})"
    end

    NewsEvent
      .left_outer_joins(:news_article)
      .where("news_events.published_at > ?", 48.hours.ago)
      .where.not(content_scope: "out_of_scope")
      .where(fragments.join(" OR "), bindings)
      .includes(:news_article, :news_source)
      .order(published_at: :desc)
      .limit(40)
  end

  def candidate_score(event, named_match_terms:, profile_hits:)
    article = event.news_article
    source_weight = SOURCE_WEIGHTS.fetch(event.news_source&.source_kind.to_s, 0.5)
    named_bonus = named_match_terms.any? ? 0.55 : 0.0
    profile_bonus = [profile_hits.size, 3].min * 0.15
    scope_bonus = case event.content_scope
    when "core" then 0.25
    when "adjacent" then 0.1
    else 0.0
    end
    hydration_bonus = article&.hydration_status == "hydrated" ? 0.15 : 0.0
    summary_bonus = usable_summary?(article&.summary) ? 0.15 : 0.0
    recency_bonus = recency_bonus_for(event.published_at)

    source_weight + named_bonus + profile_bonus + scope_bonus + hydration_bonus + summary_bonus + recency_bonus
  end

  def recency_bonus_for(published_at)
    return 0.0 unless published_at.present?
    return 0.45 if published_at > 6.hours.ago
    return 0.25 if published_at > 24.hours.ago

    0.1
  end

  def profile_keywords
    Array(PROFILE_KEYWORDS[@area_workspace.profile])
  end

  def candidate_text(event)
    clean_text([event.title, event.news_article&.summary].compact.join(" ")).downcase
  end

  def usable_summary?(summary)
    text = clean_text(summary)
    return false if text.blank?
    return false if text.start_with?("http")

    text.length >= 140
  end

  def clean_text(value)
    ActionController::Base.helpers.strip_tags(value.to_s).squish
  end
end
