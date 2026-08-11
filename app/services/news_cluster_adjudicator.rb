# Step 2: the model as an adjudicator in the band where the embedding is
# undecided.
#
# A cosine floor alone has to buy precision with recall, and the exchange rate
# is bad at the top: measured on 300 labelled pairs, a floor at 0.65 reaches
# 88.9% precision but keeps only 73.8% of the true merges. The distribution is
# why -- same-story and different-story pairs overlap between roughly 0.50 and
# 0.70, and no constant placed inside an overlap can separate it. Above 0.70 the
# embedding is right on its own; below 0.50 it is right on its own; in between
# it is genuinely undecided, and that is the only place worth spending a model
# call. It is about 400 articles a day, cents at gpt-4.1-mini.
#
# The question asked is deliberately not "are these two the same story?", which
# forces a binary on a fuzzy boundary and gets the judge-agreement ceiling of
# 87.7% as its best case. It is "which of these clusters does this article
# belong to, or none?" -- the question the clusterer is actually trying to
# answer, with the alternatives visible so the model can compare them against
# each other rather than against a threshold it cannot see.
#
# The shape is RegistryEntityResolver's, deliberately unchanged: a numbered list
# in, an index or null out, out-of-range treated as none, never raises,
# client: injectable. That resolver measures 92% precision in-pipeline. There is
# no reason for a second pattern.
class NewsClusterAdjudicator
  MODEL = ENV.fetch("CLUSTER_ADJUDICATOR_MODEL", "gpt-4.1-mini").freeze
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze
  OPEN_TIMEOUT = 15
  READ_TIMEOUT = 30
  # Retried because "not reached" is not a neutral outcome here: the caller
  # falls back to merging the band, so a run of failures quietly restores the
  # pre-model precision on exactly the pairs the model exists to judge, and
  # nothing downstream shows it.
  #
  # Measured, on the rebuild that established this: 203 of 1,273 adjudications
  # -- 16% -- never reached the model, every one of them ECONNREFUSED from
  # opening 1,273 sequential TLS connections to the same host. A refused
  # connection is transient and is the failure mode that actually happens here,
  # so retrying only on HTTP status codes would have caught none of them.
  MAX_ATTEMPTS = 3
  RETRIABLE_STATUSES = [ Net::HTTPTooManyRequests, Net::HTTPServerError ].freeze
  RETRIABLE_ERRORS = [
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, Errno::EHOSTUNREACH,
    Net::OpenTimeout, Net::ReadTimeout, SocketError, IOError,
  ].freeze
  # How many member headlines of a candidate to show. The point of showing more
  # than the lead is that a cluster's identity is the set, not its first row.
  MEMBER_PREVIEW = 6

  # Lets a retriable HTTP status take the same path as a retriable connection
  # error, so there is one retry policy rather than two that can drift apart.
  TransientError = Class.new(StandardError)

  Verdict = Struct.new(:index, :basis, :called, keyword_init: true) do
    def chose? = !index.nil?
  end

  NONE = Verdict.new(index: nil, basis: "none", called: true).freeze
  # Distinct from NONE: the model was never reached, so the caller must fall
  # back rather than treat this as a decision.
  UNAVAILABLE = Verdict.new(index: nil, basis: "unavailable", called: false).freeze

  class << self
    # candidates: array of hashes, each { title:, titles:, location_name:,
    # actors:, first_seen_at:, last_seen_at: }, ranked best-first by the
    # deterministic score. Returns a Verdict whose index points into that array.
    def call(title:, candidates:, client: nil)
      return NONE if title.blank? || candidates.blank?

      reply = (client || method(:chat)).call(prompt_for(title, candidates))
      return UNAVAILABLE if reply.nil?

      parse(reply, candidates)
    end

    def prompt_for(title, candidates)
      listed = candidates.each_with_index.map do |candidate, index|
        headlines = Array(candidate[:titles]).first(MEMBER_PREVIEW)
          .map { |member| "     - #{member}" }.join("\n")
        more = Array(candidate[:titles]).size - MEMBER_PREVIEW
        headlines += "\n     - (#{more} more)" if more.positive?

        details = [
          ("place: #{candidate[:location_name]}" if candidate[:location_name].present?),
          ("actors: #{Array(candidate[:actors]).first(6).join(', ')}" if Array(candidate[:actors]).any?),
          ("span: #{span_for(candidate)}" if candidate[:first_seen_at]),
        ].compact.join(" | ")

        "#{index}. #{details.presence || 'no place or actors resolved'}\n#{headlines}"
      end.join("\n\n")

      <<~PROMPT
        A news article has to be filed against existing story clusters. Each
        cluster below is a group of reports that have already been judged to be
        about one specific news story; the headlines under each are its current
        members.

        Decide which cluster, if any, reports THE SAME specific news event or
        story as the article. Same story = the same incident, announcement, or
        continuing episode. An article about the same broad topic, country or
        actor but a different incident does NOT belong -- it is a new story, and
        the correct answer is then none.

        Article: #{title}

        Clusters:
        #{listed}

        Reply with JSON only: {"choice": <cluster number>, "reason": "<a few words>"}
        Use {"choice": null} if the article is not the same story as any of them.
      PROMPT
    end

    private

    def span_for(candidate)
      first = candidate[:first_seen_at]
      last = candidate[:last_seen_at] || first
      hours = ((last - first) / 3600.0).round
      "#{first.utc.strftime('%b %-d %H:%M')} UTC#{" +#{hours}h" if hours.positive?}"
    end

    def parse(reply, candidates)
      return NONE if reply.blank?

      payload = JSON.parse(reply.to_s[/\{.*\}/m].to_s)
      choice = payload["choice"]
      return NONE if choice.nil?

      index = Integer(choice, exception: false)
      # An index outside the list is the model inventing an option. There is
      # nothing to file against, so it is none rather than a guess.
      return NONE if index.nil? || index.negative? || index >= candidates.size

      Verdict.new(index: index, basis: payload["reason"].to_s.presence || "adjudicated", called: true)
    rescue JSON::ParserError
      NONE
    end

    def chat(prompt)
      api_key = ENV["OPENAI_API_KEY"]
      return nil if api_key.blank?

      uri = URI(ENDPOINT)
      body = {
        model: MODEL,
        messages: [ { role: "user", content: prompt } ],
        temperature: 0,
        max_tokens: 120,
        response_format: { type: "json_object" },
      }.to_json

      attempt = 0
      begin
        attempt += 1
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_key}"
        request["Content-Type"] = "application/json"
        request.body = body

        response = http.request(request)
        return JSON.parse(response.body).dig("choices", 0, "message", "content") if response.is_a?(Net::HTTPSuccess)
        raise TransientError, "OpenAI #{response.code} #{response.body.to_s[0..200]}" if
          RETRIABLE_STATUSES.any? { |kind| response.is_a?(kind) }

        Rails.logger.warn("NewsClusterAdjudicator: OpenAI #{response.code} #{response.body.to_s[0..200]}")
        nil
      rescue *RETRIABLE_ERRORS, TransientError => e
        if attempt < MAX_ATTEMPTS
          sleep(attempt * 2)
          retry
        end
        Rails.logger.warn("NewsClusterAdjudicator: gave up after #{attempt} attempts, #{e.class} #{e.message}")
        nil
      end
    rescue StandardError => e
      # An adjudicator that raises would take the news sync down with it. nil is
      # read by the caller as "not reached", which falls back to the pre-model
      # behaviour rather than to an arbitrary answer.
      Rails.logger.warn("NewsClusterAdjudicator: #{e.class} #{e.message}")
      nil
    end
  end
end
