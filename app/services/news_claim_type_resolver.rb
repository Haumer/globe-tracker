# The model as a classifier over the taxonomy we already have.
#
# NewsClaimExtractor decides an event family by running 24 regexes and taking the
# first that matches. When none does it falls through to `general` /
# `actor_mention`, and NewsStoryClusterer#build_payload drops both -- once on
# CLUSTERABLE_EVENT_FAMILIES, again on GENERAL_EVENT_TYPES. Measured on the
# clone, that fallthrough holds 6,065 claims against the 5,962 that get through,
# so one unmatched regex costs more than everything downstream keeps.
#
# The list is not the constraint: every family in the data is already on
# CLUSTERABLE_EVENT_FAMILIES. What is missing is a willingness to assign a family
# to text the rules did not anticipate, and that is a reading task.
#
# Shape is RegistryEntityResolver's and NewsClusterAdjudicator's, unchanged: a
# numbered list in, an index out, out-of-range treated as none, never raises,
# client: injectable. The model cannot invent a family or a type -- CATALOG is
# derived from the rules themselves, so anything it picks already has a tuned
# FAMILY_WINDOW and FAMILY_MAX_DISTANCE_KM waiting for it downstream. A model
# free to emit a *new* type would produce claims the clusterer has no constants
# for, which is the NewsEnrichmentService failure (emit a string, then look it up
# in a hardcoded table, drop it when it misses) one table over.
#
# Most of these headlines are genuinely not events. "Iran and the US remain at
# odds" mentions two actors and reports nothing, and the honest answer is none.
# The prompt says so explicitly and the measured none-rate is the first thing to
# look at in a dry run: a resolver that assigns nearly everything has stopped
# classifying and started guessing.
class NewsClaimTypeResolver
  MODEL = ENV.fetch("CLAIM_TYPE_RESOLVER_MODEL", "gpt-4.1-mini").freeze
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze
  OPEN_TIMEOUT = 15
  READ_TIMEOUT = 60

  # Headlines per request. Batched rather than one call per claim because the
  # backfill is ~6,000 items and NewsClusterAdjudicator measured 203 of 1,273
  # single calls failing with ECONNREFUSED purely from opening that many
  # sequential TLS connections to one host. At 25 the same corpus is ~240
  # connections.
  BATCH_SIZE = 25

  # Copied from NewsClusterAdjudicator deliberately. A refused connection is an
  # exception rather than a status code, so retrying on HTTP status alone would
  # have caught none of the failures that actually happened there.
  MAX_ATTEMPTS = 3
  RETRIABLE_STATUSES = [ Net::HTTPTooManyRequests, Net::HTTPServerError ].freeze
  RETRIABLE_ERRORS = [
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, Errno::EHOSTUNREACH,
    Net::OpenTimeout, Net::ReadTimeout, SocketError, IOError,
  ].freeze

  TransientError = Class.new(StandardError)

  Assignment = Struct.new(:event_family, :event_type, :basis, :called, keyword_init: true) do
    def assigned? = event_family.present?
  end

  NONE = Assignment.new(event_family: nil, event_type: nil, basis: "none", called: true).freeze
  # Distinct from NONE: the model was never reached. The caller must leave the
  # claim alone rather than record a decision that was never made.
  UNAVAILABLE = Assignment.new(event_family: nil, event_type: nil, basis: "unavailable", called: false).freeze

  # Kinds the rules never produce, because nobody wrote a regex for them, but
  # which the `general` pile is full of.
  #
  # These exist because the first audit of this resolver measured ~47% precision
  # and the errors were nearly all one shape: a real event with no honest bucket,
  # filed under the nearest wrong one. A tourist drowning became an earthquake, a
  # heatwave became a storm, a house fire became a wildfire, a lawsuit and a
  # revoked licence both became arrest_detention, a near-miss became a crash, a
  # military exercise became an airstrike. Offering null harder does not fix
  # that -- the events are real, so null is also the wrong answer. They needed
  # somewhere to go.
  #
  # Every one sits in a family that already exists, and that is what makes them
  # safe: FAMILY_WINDOWS and FAMILY_MAX_DISTANCE_KM are keyed on family, so each
  # inherits tuned constants, while event_type_score is exact-match-or-zero and
  # COMPATIBLE_EVENT_GROUPS does not mention them, so a new type clusters only
  # with its own kind and cannot widen any existing cluster.
  SUPPLEMENTARY_KINDS = [
    { event_family: "disaster", event_type: "heatwave" },
    { event_family: "security", event_type: "structure_fire" },
    { event_family: "security", event_type: "violent_crime" },
    { event_family: "security", event_type: "armed_threat" },
    { event_family: "conflict", event_type: "military_exercise" },
    { event_family: "justice", event_type: "legal_action" },
    { event_family: "justice", event_type: "regulatory_action" },
    { event_family: "transport", event_type: "transport_incident" },
    { event_family: "humanitarian", event_type: "rescue" },
    { event_family: "politics", event_type: "appointment" },
  ].freeze

  # The (family, type) pairs the rules can already produce, plus the ones above,
  # deduped and held to the families the clusterer accepts. The rule-derived half
  # is read from NewsClaimExtractor rather than hand-listed so a new regex cannot
  # silently fall out of sync with what the model is offered.
  CATALOG = (
    NewsClaimExtractor::EVENT_RULES
      .map { |rule| { event_family: rule[:event_family], event_type: rule[:event_type] } } +
    SUPPLEMENTARY_KINDS
  ).uniq
    .select { |pair| NewsStoryClusterer::CLUSTERABLE_EVENT_FAMILIES.include?(pair[:event_family]) }
    .reject { |pair| NewsStoryClusterer::GENERAL_EVENT_TYPES.include?(pair[:event_type]) }
    .freeze

  class << self
    # headlines: array of strings. Returns an array of Assignments of the same
    # length and order, so the caller can zip it back against its own records.
    def call(headlines:, client: nil)
      headlines = Array(headlines)
      return [] if headlines.empty?

      headlines.each_slice(BATCH_SIZE).flat_map do |slice|
        resolve_slice(slice, client)
      end
    end

    # Items are numbered from 1 and catalog entries from 0. The asymmetry is
    # deliberate rather than sloppy: 0-based candidate lists are what
    # RegistryEntityResolver and NewsClusterAdjudicator already use, so `choice`
    # means the same thing in all three, while `n` reads as an ordinal and a
    # model that echoes it back off-by-one is caught by the range check instead
    # of silently shifting every assignment by one row.
    def prompt_for(headlines)
      listed = CATALOG.each_with_index
        .map { |pair, index| "#{index}. #{pair[:event_family]} / #{pair[:event_type]}" }
        .join("\n")

      items = headlines.each_with_index
        .map { |headline, index| "#{index + 1}. #{headline}" }
        .join("\n")

      <<~PROMPT
        Each numbered headline below mentions at least one country or
        organisation, but our rules could not tell what kind of event, if any, it
        reports.

        For each headline, decide whether it reports a specific real-world event
        of one of the listed kinds, and if so which. Judge the event the headline
        reports, not the topic it touches.

        Choose a kind only if the headline says that event happened. Analysis of
        that kind of event, a plan or proposal for one, a warning or threat that
        one may happen, a shortage of the equipment used in one, or funding for
        something related to one are all null -- the event itself is what counts.

        Many of these headlines report no event at all: commentary, opinion,
        profiles, market chatter, sport, or a standing state of affairs rather
        than something that happened. Those are null too, and null is expected to
        be the most common answer.

        If a headline reports a real event but none of the listed kinds actually
        describes it, answer null rather than the closest one.

        Event kinds:
        #{listed}

        Headlines:
        #{items}

        Reply with JSON only:
        {"answers": [{"n": 1, "choice": <event kind number or null>}, ...]}
        Include one entry per headline, using the same n as above.
      PROMPT
    end

    private

    def resolve_slice(headlines, client)
      reply = (client || method(:chat)).call(prompt_for(headlines))
      return Array.new(headlines.size, UNAVAILABLE) if reply.nil?

      parse(reply, headlines.size)
    end

    def parse(reply, size)
      answers = JSON.parse(reply.to_s[/\{.*\}/m].to_s)["answers"]
      return Array.new(size, NONE) unless answers.is_a?(Array)

      # Keyed on the model's own n rather than read positionally. A reply that is
      # short, reordered, or carries a duplicate would otherwise shift every
      # assignment after it onto the wrong headline -- silently, and in a way no
      # count would show.
      by_position = {}
      answers.each do |answer|
        next unless answer.is_a?(Hash)

        position = Integer(answer["n"], exception: false)
        next if position.nil? || position < 1 || position > size
        next if by_position.key?(position)

        by_position[position] = assignment_for(answer["choice"])
      end

      Array.new(size) { |index| by_position[index + 1] || NONE }
    rescue JSON::ParserError
      Array.new(size, NONE)
    end

    def assignment_for(choice)
      return NONE if choice.nil?

      index = Integer(choice, exception: false)
      # Outside the catalog is the model inventing a kind. There is nothing to
      # assign, so it is none rather than a guess.
      return NONE if index.nil? || index.negative? || index >= CATALOG.size

      pair = CATALOG[index]
      Assignment.new(event_family: pair[:event_family], event_type: pair[:event_type],
                     basis: "resolved", called: true)
    end

    def chat(prompt)
      api_key = ENV["OPENAI_API_KEY"]
      return nil if api_key.blank?

      uri = URI(ENDPOINT)
      body = {
        model: MODEL,
        messages: [ { role: "user", content: prompt } ],
        temperature: 0,
        # ~12 tokens per answer at BATCH_SIZE 25, with room for the model to be
        # verbose about it. A truncated reply is unparseable JSON and lands on
        # NONE, which loses the batch rather than corrupting it.
        max_tokens: 1_200,
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

        Rails.logger.warn("NewsClaimTypeResolver: OpenAI #{response.code} #{response.body.to_s[0..200]}")
        nil
      rescue *RETRIABLE_ERRORS, TransientError => e
        if attempt < MAX_ATTEMPTS
          sleep(attempt * 2)
          retry
        end
        Rails.logger.warn("NewsClaimTypeResolver: gave up after #{attempt} attempts, #{e.class} #{e.message}")
        nil
      end
    rescue StandardError => e
      # A resolver that raises would take the news sync down with it. nil reads
      # as "not reached", which leaves the claim exactly as the rules left it.
      Rails.logger.warn("NewsClaimTypeResolver: #{e.class} #{e.message}")
      nil
    end
  end
end
