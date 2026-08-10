module NewsDedupable
  extend ActiveSupport::Concern

  private

  # Collapse records sharing a URL before they reach upsert_all.
  #
  # Postgres rejects a batch that names the same conflict target twice with
  # "ON CONFLICT DO UPDATE command cannot affect row a second time", and the
  # whole batch is lost. Feeds overlap constantly -- several Google News topic
  # queries return the same article, and syndicated wire copy shows up under
  # more than one publisher -- so this is routine rather than an edge case.
  # Title dedup does not cover it: two feeds can carry one URL under headlines
  # too different to match.
  def dedup_by_url(records)
    records.uniq { |record| record[:url] }
  end

  # Collapse near-identical headlines *within a single publisher*.
  #
  # This used to suppress a matching headline no matter who published it,
  # against every NewsEvent title from the previous 48 hours. That deleted the
  # one signal this whole pipeline is built to measure. Forty outlets running
  # one wire story, or two newsrooms covering the same bombing, is not noise --
  # it is corroboration, and NewsStoryClusterer already knows what to do with
  # it: syndication_groups partitions a cluster's articles into near-verbatim
  # headline groups so that forty copies count as one independent newsroom
  # while still contributing to article_count. None of that machinery could
  # ever fire, because the copies were thrown away hours before clustering saw
  # them. Hence 597 of 727 clusters sitting at "single_source".
  #
  # Within one publisher a repeated headline really is a duplicate -- a feed
  # re-running a story, or the same piece surfacing under both an RSS entry and
  # a sitemap URL -- so suppression still applies there.
  #
  # `existing` is [url, title] pairs from already-persisted events.
  def dedup_by_title(records, existing: [])
    seen = Hash.new { |hash, key| hash[key] = [] }
    Array(existing).each do |url, title|
      next if title.blank?

      seen[publisher_key(url)] << normalize_title(title)
    end

    records.select do |record|
      title = record[:title]
      next true if title.blank?

      key = publisher_key(record[:url])
      words = normalize_title(title)
      duplicate = seen[key].any? { |candidate| similar?(candidate, words) }
      seen[key] << words unless duplicate
      !duplicate
    end
  end

  # Host, not registrable domain: two URLs on the same host are the same feed.
  # A blank host groups everything unattributable together, which is the safe
  # side -- those records get the old stricter behaviour among themselves.
  def publisher_key(url)
    return "" if url.blank?

    URI(url.to_s).host.to_s.downcase.sub(/\Awww\./, "")
  rescue StandardError
    ""
  end

  def normalize_title(title)
    title.downcase.gsub(/[^a-z0-9\s]/, "").split.reject { |w| w.length < 2 }.to_set
  end

  def assign_clusters(records)
    NewsStoryClusterer.assign_records(records)
  end

  # Two-pronged similarity: Jaccard for general overlap, containment for subset detection.
  # Short titles (< 5 words) use a stricter Jaccard threshold since small word sets
  # produce inflated scores from minor overlaps.
  def similar?(set_a, set_b)
    similarity_scores(set_a, set_b, jaccard_base: 0.5, jaccard_short: 0.65, containment_min: 0.8)
  end

  def similarity_scores(set_a, set_b, jaccard_base:, jaccard_short:, containment_min:)
    return false if set_a.empty? || set_b.empty?

    intersection = (set_a & set_b).size.to_f
    union = (set_a | set_b).size.to_f
    smaller = [set_a.size, set_b.size].min.to_f

    jaccard = intersection / union
    containment = intersection / smaller

    return true if containment >= containment_min && intersection >= 3

    threshold = smaller < 5 ? jaccard_short : jaccard_base
    jaccard > threshold
  end
end
