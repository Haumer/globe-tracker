require "net/http"
require "nokogiri"

# Ingests Google-News sitemaps directly from publishers.
#
# Why this exists: the `site:` Google News proxies in RssNewsService return
# opaque news.google.com redirect URLs and a shallow, Google-mediated view of
# each publisher. A publisher's own news sitemap is deeper (hundreds of items
# vs ~20), carries a real publication timestamp per entry, and links straight
# to the article. Measured against the same publishers, sitemaps returned
# roughly 13x the items RSS did.
#
# Depth is the operational win: an RSS feed holds a rolling window (one
# publisher's held 2.7 hours), so any poller gap loses articles permanently.
# A news sitemap spans hours-to-days, so a missed cycle costs nothing.
#
# Because sitemaps are deep, this service is *incremental*: each source keeps a
# publication-date watermark and only emits entries newer than it. Without
# that, every cycle would re-ingest a few hundred items per publisher.
class NewsSitemapService
  extend Refreshable
  include TimelineRecorder
  include NewsDedupable
  include NewsGeocodable

  REGISTRY_PATH = Rails.root.join("config", "news_publishers.yml")

  # 253 sitemap sources / 6 batches = ~42 per cycle, each polled every 30 min.
  # Deep sitemaps make a slower rotation safe -- nothing is lost between polls.
  BATCH_COUNT = 6
  BATCH_INTERVAL = 5
  THREAD_POOL_SIZE = 8

  # Ceiling per source per poll. Only reachable on a cold watermark; steady
  # state is a handful of items. Guards against a cache flush pulling a
  # publisher's entire sitemap in one cycle.
  MAX_ITEMS_PER_POLL = 150
  # With no watermark yet, ignore anything older than this rather than
  # backfilling a sitemap's full depth on first sight. Watermarks live in
  # Rails.cache, so an eviction resets every source to a cold start at once --
  # at ~950 articles/hour across these sources, 24h would replay ~38k items
  # through geocoding before URL dedup could drop them. Six hours keeps a
  # full-flush recovery to roughly one normal cycle's worth of work.
  COLD_START_MAX_AGE = 6.hours
  # Publishers do post slightly ahead, and some stamp local time as UTC. Beyond
  # this the date is simply wrong -- one probed sitemap was 52 days ahead.
  FUTURE_PUB_DATE_SLACK = 3.hours

  OPEN_TIMEOUT = 8
  READ_TIMEOUT = 20
  USER_AGENT = "GlobeTracker/1.0 (+news sitemap ingest)".freeze

  class << self
    def refresh_if_stale(force: false)
      return 0 if !force && !stale?
      new.refresh
    end

    def stale?
      last = Rails.cache.read("news_sitemap_last_fetch")
      last.nil? || last < BATCH_INTERVAL.minutes.ago
    end

    # Publisher registry, memoized per process. Only sitemap-transport rows are
    # this service's concern; RSS-transport rows stay with RssNewsService.
    def sources
      @sources ||= begin
        rows = YAML.load_file(REGISTRY_PATH)
        rows.select { |row| row["transport"] == "sitemap" }
      rescue Errno::ENOENT
        Rails.logger.warn("NewsSitemapService: #{REGISTRY_PATH} missing")
        []
      end
    end

    def reload_sources!
      @sources = nil
      sources
    end
  end

  def refresh
    sources = self.class.sources
    return 0 if sources.empty?

    batch = current_batch(sources)
    all_records = []
    ingest_items = []
    mutex = Mutex.new

    batch.shuffle.each_slice(THREAD_POOL_SIZE) do |group|
      threads = group.map do |source|
        Thread.new do
          sleep(rand * 3) # stagger within the group
          fetch_sitemap(source)
        end
      end
      threads.each do |thread|
        result = begin
          thread.value
        rescue => e
          Rails.logger.warn("NewsSitemapService thread: #{e.message}")
          { records: [], ingest_items: [] }
        end
        mutex.synchronize do
          all_records.concat(result[:records])
          ingest_items.concat(result[:ingest_items])
        end
      end
    end

    stored = persist(all_records, ingest_items)
    Rails.cache.write("news_sitemap_last_fetch", Time.current)
    Rails.logger.info(
      "NewsSitemapService: #{stored} new from #{batch.size} sources (#{all_records.size} parsed)"
    )
    stored
  rescue => e
    Rails.logger.error("NewsSitemapService: #{e.message}")
    0
  end

  private

  def current_batch(sources)
    idx = (Rails.cache.read("news_sitemap_batch_idx") || 0) % BATCH_COUNT
    Rails.cache.write("news_sitemap_batch_idx", idx + 1)
    size = (sources.size.to_f / BATCH_COUNT).ceil
    sources.each_slice(size).to_a[idx] || []
  end

  # Mirrors RssNewsService#refresh's tail. Deliberately duplicated rather than
  # extracted: rss_news_service.rb has uncommitted changes on main and pulling
  # a shared module out of it now would guarantee a conflict. Consolidate once
  # that work lands.
  def persist(all_records, ingest_items)
    return 0 if all_records.empty?

    existing_urls = NewsEvent.where(url: all_records.map { |r| r[:url] }).pluck(:url).to_set
    candidates = all_records.reject { |r| existing_urls.include?(r[:url]) }

    existing_titles = NewsEvent.where("published_at > ?", 48.hours.ago)
      .pluck(:title).compact
      .map { |t| normalize_title(t) }

    new_records = dedup_by_title(candidates, existing_titles: existing_titles)
    return 0 if new_records.empty?

    ingest_ids = NewsIngestRecorder.record_all(ingest_items)
    new_records.each { |record| record[:news_ingest_id] = ingest_ids[record[:url]] }
    normalized_ids = NewsNormalizationRecorder.record_all(new_records)
    new_records.each do |record|
      ids = normalized_ids[record[:url]]
      next unless ids

      record[:news_source_id] = ids[:news_source_id]
      record[:news_article_id] = ids[:news_article_id]
      record[:content_scope] = ids[:content_scope]
    end
    NewsClaimRecorder.record_all(new_records)
    RssArticleHydrationService.enqueue_candidates(new_records)
    assign_clusters(new_records)
    NewsOntologySyncService.enqueue_for_records(new_records)

    NewsEvent.upsert_all(new_records, unique_by: :url)
    record_timeline_events(
      event_type: "news", model_class: NewsEvent,
      unique_key: :url, unique_values: new_records.map { |r| r[:url] },
      time_column: :published_at
    )
    TrendingKeywordTracker.ingest(new_records) if defined?(TrendingKeywordTracker)
    new_records.size
  end

  def fetch_sitemap(source)
    now = Time.current
    domain = source["domain"]
    url = source["url"]
    response = conditional_get(url)

    # 304 is the happy path for a polite crawler -- nothing republished since
    # our last poll, so there is nothing to parse.
    if response.is_a?(Net::HTTPNotModified)
      record_status(source, status: "success", http_status: 304, now: now)
      return { records: [], ingest_items: [] }
    end

    unless response.is_a?(Net::HTTPSuccess)
      record_status(source, status: "error", http_status: response.code.to_i,
                    error: "HTTP #{response.code}", now: now)
      return { records: [], ingest_items: [] }
    end

    store_validators(url, response)
    entries = parse_entries(response.body)
    if entries.empty?
      record_status(source, status: "error", http_status: 200,
                    error: "no <news:> entries", now: now)
      return { records: [], ingest_items: [] }
    end

    fresh = select_fresh(domain, entries, now: now)
    result = build_payloads(source, fresh, response: response, now: now)
    advance_watermark(domain, fresh)

    record_status(source, status: "success", http_status: 200, now: now,
                  fetched: entries.size, stored: result[:records].size)
    result
  rescue => e
    Rails.logger.warn("NewsSitemapService[#{source['domain']}]: #{e.message}")
    record_status(source, status: "error", error: e.message, now: Time.current)
    { records: [], ingest_items: [] }
  end

  def conditional_get(url)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "application/xml,text/xml"
    validators = Rails.cache.read(validator_key(url)) || {}
    request["If-None-Match"] = validators["etag"] if validators["etag"].present?
    request["If-Modified-Since"] = validators["last_modified"] if validators["last_modified"].present?
    http.request(request)
  end

  def store_validators(url, response)
    validators = {
      "etag" => response["ETag"],
      "last_modified" => response["Last-Modified"],
    }.compact
    return if validators.empty?

    Rails.cache.write(validator_key(url), validators, expires_in: 7.days)
  end

  def validator_key(url)
    "news_sitemap_validators:#{Digest::SHA256.hexdigest(url)}"
  end

  # Namespaces are stripped so that publishers who bind the news schema to an
  # unexpected prefix still parse. Entries without a publication_date are
  # dropped -- an undated entry cannot be placed on a timeline.
  def parse_entries(body)
    doc = Nokogiri::XML(body)
    doc.remove_namespaces!
    doc.xpath("//url").filter_map do |node|
      news = node.at_xpath("news")
      next if news.nil?

      loc = node.at_xpath("loc")&.text.to_s.strip
      published_raw = news.at_xpath("publication_date")&.text
      next if loc.blank? || published_raw.blank?

      published_at = begin
        Time.zone.parse(published_raw)
      rescue ArgumentError
        nil
      end
      next if published_at.nil?

      {
        url: loc,
        title: news.at_xpath("title")&.text.to_s.strip,
        publication: news.at_xpath("publication/name")&.text.to_s.strip,
        keywords: news.at_xpath("keywords")&.text.to_s.strip,
        published_at: published_at,
      }
    end
  end

  def select_fresh(domain, entries, now:)
    mark = Rails.cache.read(watermark_key(domain))
    floor = mark.presence || (now - COLD_START_MAX_AGE)
    ceiling = now + FUTURE_PUB_DATE_SLACK

    entries
      .select { |e| e[:published_at] > floor && e[:published_at] <= ceiling }
      .sort_by { |e| -e[:published_at].to_i }
      .first(MAX_ITEMS_PER_POLL)
  end

  def advance_watermark(domain, entries)
    return if entries.empty?

    newest = entries.map { |e| e[:published_at] }.max
    current = Rails.cache.read(watermark_key(domain))
    return if current.present? && current >= newest

    Rails.cache.write(watermark_key(domain), newest, expires_in: 30.days)
  end

  def watermark_key(domain)
    "news_sitemap_watermark:#{domain}"
  end

  def build_payloads(source, entries, response:, now:)
    records = []
    ingest_items = []
    display = display_name(source)

    entries.each_with_index do |entry, idx|
      next if entry[:title].blank?

      adapted = NewsSourceAdapter.normalize!(
        source_adapter: "sitemap:#{source['domain']}",
        attrs: {
          url: entry[:url],
          title: entry[:title],
          summary: entry[:keywords].presence,
          name: entry[:publication].presence || display,
          published_at: entry[:published_at],
          source: "sitemap",
        }
      )

      ingest_items << {
        item_key: adapted[:url].presence || "#{source['domain']}-#{idx}",
        source_feed: display,
        source_endpoint_url: source["url"],
        external_id: entry[:url],
        raw_url: entry[:url],
        raw_title: adapted[:title],
        raw_summary: adapted[:summary],
        raw_published_at: entry[:published_at],
        fetched_at: now,
        payload_format: "sitemap",
        raw_payload: {
          "loc" => entry[:url],
          "title" => entry[:title],
          "publication" => entry[:publication],
          "keywords" => entry[:keywords],
          "publication_date" => entry[:published_at].iso8601,
        },
        http_status: response.code.to_i,
      }

      # Sitemaps carry no summary, so the resolver sees title + URL only. That
      # is measurably less signal than an RSS description gives it; expect a
      # lower pass rate here than for the RSS transport.
      location = LocationResolver.resolve_event(
        title: adapted[:title],
        summary: adapted[:summary],
        url: adapted[:url]
      )
      next unless location&.coordinates

      threat = ThreatClassifier.classify([ adapted[:title], adapted[:summary] ].compact.join(" "))
      credibility = [ "tier#{source['tier']}", source["risk"] ].compact.join("/")

      records << LocationResolver.news_event_attributes(location).merge(
        url: adapted[:url],
        title: adapted[:title],
        name: adapted[:name],
        tone: threat[:tone],
        level: threat[:level],
        category: threat[:category],
        threat_level: threat[:threat],
        credibility: credibility,
        themes: threat[:keywords].first(5),
        published_at: adapted[:published_at] || now,
        fetched_at: now,
        source: "sitemap",
        created_at: now,
        updated_at: now,
      )
    end

    { records: records, ingest_items: ingest_items }
  end

  def display_name(source)
    "SM: #{source['domain']}"
  end

  def record_status(source, status:, now:, http_status: nil, error: nil,
                    fetched: 0, stored: 0)
    SourceFeedStatusRecorder.record(
      provider: "sitemap",
      display_name: display_name(source),
      feed_kind: "sitemap",
      endpoint_url: source["url"],
      status: status,
      records_fetched: fetched,
      records_stored: stored,
      http_status: http_status,
      error_message: error,
      metadata: {
        tier: source["tier"], region: source["region"], risk: source["risk"],
        country: source["country"], domain: source["domain"],
      }.compact,
      occurred_at: now
    )
  end
end
