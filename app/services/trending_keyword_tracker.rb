class TrendingKeywordTracker
  CACHE_KEY = "trending_keywords".freeze
  WINDOW = 6.hours
  MIN_COUNT = 3
  STOP_WORDS = %w[
    the and for that with from this have been has are was were will not but
    about after also can could into just its more new than them their there
    these they this what when where which while will would been being does
    during each from have having some such than that the them then there
    these they this those through very what which while will with would
    says said told report reports according sources officials government
    people country world state states year years
  ].to_set.freeze

  class << self
    # Ingest a batch of news records and update keyword counts
    def ingest(records)
      counts = current_counts
      now = Time.current.to_i

      records.each do |record|
        title = record[:title].to_s
        category = record[:category].to_s
        words = extract_words(title)
        words.each do |word|
          counts[word] ||= { timestamps: [], total: 0, categories: [] }
          counts[word][:categories] ||= []
          counts[word][:timestamps] << now
          counts[word][:categories] << category if category.present?
          counts[word][:total] += 1
        end
      end

      # Prune old timestamps
      cutoff = (Time.current - WINDOW).to_i
      counts.each do |word, data|
        keep_indices = data[:timestamps].each_index.select { |i| data[:timestamps][i] > cutoff }
        data[:timestamps] = keep_indices.map { |i| data[:timestamps][i] }
        data[:categories] = (data[:categories] || []).last(data[:timestamps].size)
        data[:total] = data[:timestamps].size
      end
      counts.reject! { |_, data| data[:total] == 0 }

      Rails.cache.write(CACHE_KEY, counts, expires_in: WINDOW + 1.hour)
    end

    # Return trending keywords sorted by velocity (recent count / baseline)
    def trending(limit: 20)
      counts = current_counts
      now = Time.current.to_i
      cutoff_recent = now - 1.hour.to_i
      cutoff_baseline = now - WINDOW.to_i

      trends = counts.filter_map do |word, data|
        recent = data[:timestamps].count { |t| t > cutoff_recent }
        total = data[:total]
        next if total < MIN_COUNT || recent == 0

        # Velocity: how much faster is this keyword appearing vs baseline
        baseline_rate = total.to_f / (WINDOW / 1.hour)
        velocity = recent / [baseline_rate, 0.5].max

        # Dominant category: most frequent category for this keyword
        categories = data[:categories] || []
        dominant_category = categories.tally.max_by { |_, v| v }&.first || "other"

        { keyword: word, recent: recent, total: total, velocity: velocity.round(2), category: dominant_category }
      end

      trends.sort_by { |t| -t[:velocity] }.first(limit)
    end

    private

    def current_counts
      Rails.cache.read(CACHE_KEY) || {}
    end

    def extract_words(title)
      title.downcase
           .gsub(/[^a-z0-9\s-]/, "")
           .split
           .reject { |w| w.length < 4 || STOP_WORDS.include?(w) }
           .uniq
    end
  end
end
