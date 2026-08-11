# Phase 1.4: the model as a resolver, not a generator.
#
# RegistryNameIndex leaves a tier it cannot settle. "JAZAN" and "NAGASAKI" are
# both bare toponyms naming real registry assets, and the difference between them
# is not in the string: the Jazan story is about the refinery that was struck,
# the Nagasaki story is about a bombing anniversary and has nothing to do with
# the port. Deciding that is a reading task, so it is the one thing here worth
# spending a model call on.
#
# The model never writes a name. It is handed a numbered list of candidates that
# deterministic matching already found and asked for an index, which maps back to
# a primary key. That is the whole point of the design: NewsEnrichmentService
# asks a model to *emit* a place and then looks the string up in a hardcoded
# table, so anything outside that vocabulary is silently dropped. Choosing from a
# list cannot fail that way -- the worst case is "none", which is a real answer.
class RegistryEntityResolver
  # Overridable because this is a harder judgement than the geocoding pass, which
  # runs on gpt-4.1-nano. Anthropic is deliberately not wired up here (billing).
  MODEL = ENV.fetch("REGISTRY_RESOLVER_MODEL", "gpt-4.1-mini").freeze
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze
  OPEN_TIMEOUT = 15
  READ_TIMEOUT = 30

  Resolution = Struct.new(:entity_id, :basis, keyword_init: true) do
    def resolved? = entity_id.present?
  end

  NONE = Resolution.new(entity_id: nil, basis: "none").freeze

  class << self
    # candidates: RegistryNameIndex::Match values. client: injectable for tests
    # and for the eval task, which counts calls.
    def call(title:, candidates:, client: nil)
      return NONE if title.blank? || candidates.blank?

      # One candidate or many, the question is the same -- is the report about
      # this thing -- so a single candidate is still asked rather than assumed.
      reply = (client || method(:chat)).call(prompt_for(title, candidates))
      parse(reply, candidates)
    end

    def prompt_for(title, candidates)
      listed = candidates.each_with_index.map do |match, index|
        entity = OntologyEntity.find_by(id: match.entity_id)
        details = [
          "type: #{match.entity_type}",
          ("country: #{entity.country_code}" if entity&.country_code.present?),
          ("coords: #{entity.metadata['latitude']},#{entity.metadata['longitude']}" if entity&.metadata&.dig("latitude").present?),
        ].compact.join(", ")
        "#{index}. #{match.entity_name} (#{details})"
      end.join("\n")

      <<~PROMPT
        A news headline matched one or more entries in an infrastructure registry
        because the text contains their name. Registry assets are very often named
        after the town they sit in, so a match may only mean the place was
        mentioned.

        Decide whether the report is about the listed facility itself -- damage to
        it, operations at it, an attack on it, a decision about it. If the text
        merely mentions the place, or is about an unrelated event that happened
        there, the answer is none.

        Headline: #{title}

        Candidates:
        #{listed}

        Reply with JSON only: {"choice": <candidate number>, "reason": "<a few words>"}
        Use {"choice": null} if no candidate is the subject of the report.
      PROMPT
    end

    private

    def parse(reply, candidates)
      return NONE if reply.blank?

      payload = JSON.parse(reply.to_s[/\{.*\}/m].to_s)
      choice = payload["choice"]
      return NONE if choice.nil?

      index = Integer(choice, exception: false)
      # An index outside the list is the model inventing an option; there is
      # nothing to resolve to, so it is treated as none rather than guessed at.
      return NONE if index.nil? || index.negative? || index >= candidates.size

      Resolution.new(entity_id: candidates[index].entity_id, basis: payload["reason"].to_s.presence || "resolved")
    rescue JSON::ParserError
      NONE
    end

    def chat(prompt)
      api_key = ENV["OPENAI_API_KEY"]
      return nil if api_key.blank?

      uri = URI(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = {
        model: MODEL,
        messages: [{ role: "user", content: prompt }],
        temperature: 0,
        max_tokens: 120,
        response_format: { type: "json_object" },
      }.to_json

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("RegistryEntityResolver: OpenAI #{response.code} #{response.body.to_s[0..200]}")
        return nil
      end

      JSON.parse(response.body).dig("choices", 0, "message", "content")
    rescue StandardError => e
      # A resolver that raises would take the sync down with it; a miss just
      # leaves the candidate unresolved, which is the pre-1.4 state.
      Rails.logger.warn("RegistryEntityResolver: #{e.class} #{e.message}")
      nil
    end
  end
end
