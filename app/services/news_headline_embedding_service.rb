require "digest"

# Headlines as vectors, for the one question the clusterer keeps getting wrong:
# are these two reports the same story?
#
# The lexical stem in NewsStoryClusterer answers it by counting shared word
# stems, and that is close to exhausted: a full rebuild of the prod clone
# asserts 7,875 same-story pairs and 56.0% of them are really the same story.
# The errors that remain are semantic, not lexical.
#
# Vectors are L2-normalised at write time so every consumer can use a plain dot
# product and never has to remember to divide by the magnitudes.
#
#   metric                same-story   different   Cohen's d    AUC
#   lexical stem (shipped)     0.437       0.321        0.85   0.721
#   embedding cosine           0.703       0.475        1.87   0.916
#
# AUC is the probability that a random same-story pair scores above a random
# different-story pair, which is the property the gate actually needs.
class NewsHeadlineEmbeddingService
  MODEL = ENV.fetch("HEADLINE_EMBEDDING_MODEL", "text-embedding-3-small").freeze
  # text-embedding-3-small is trained so that a truncated prefix of the vector
  # is still a usable embedding, which makes the width a storage/quality dial
  # rather than a fixed cost. The default is measured, not assumed -- see
  # DIMENSION_CHOICE below.
  DIMENSIONS = Integer(ENV.fetch("HEADLINE_EMBEDDING_DIMENSIONS", "256"))
  ENDPOINT = "https://api.openai.com/v1/embeddings".freeze
  # The API caps a single request well above this; 256 keeps one failed request
  # cheap to retry and the JSON response inside a sane memory footprint.
  BATCH_SIZE = 256
  OPEN_TIMEOUT = 15
  READ_TIMEOUT = 60
  MAX_ATTEMPTS = 3

  # Why 256 rather than the model's native 1536, measured on the same 300
  # labelled pairs as everything else:
  #
  #   width   same-story   different   Cohen's d   AUC
  #   1536         0.681       0.450        1.89   0.914
  #    512         0.696       0.468        1.88   0.914
  #    256         0.703       0.475        1.87   0.916
  #
  # Ranking power is flat -- truncation costs nothing a gate can see -- while
  # the width is a real cost, carried per article and dot-producted against
  # every member of every candidate cluster. 256 is 6x less of both.
  #
  # What truncation does move is the *absolute* cosine: both means rise about
  # 0.02 as the width falls, because a shorter vector concentrates the shared
  # leading components. A threshold measured at one width therefore does not
  # transfer to another. Every bound in NewsStoryClusterer was tuned at 256 and
  # changing DIMENSIONS invalidates them -- which is why the width is part of
  # the stored digest.
  DIMENSION_CHOICE = 256

  class << self
    # texts: array of strings. Returns an array of the same length holding a
    # normalised Array(Float) per input, or nil where the text was blank or the
    # API could not be reached. Never raises: an embedding that is missing
    # leaves the caller in its pre-embedding state, which is a working state.
    def embed(texts, client: nil)
      inputs = Array(texts)
      return [] if inputs.empty?

      results = Array.new(inputs.size)
      pending = inputs.each_with_index.reject { |text, _index| prepare(text).blank? }

      pending.each_slice(BATCH_SIZE) do |slice|
        vectors = (client || method(:request)).call(slice.map { |text, _index| prepare(text) })
        next if vectors.blank?

        slice.each_with_index do |(_text, index), position|
          vector = vectors[position]
          results[index] = normalize_vector(vector) if vector.present?
        end
      end

      results
    end

    def embed_one(text, client: nil)
      embed([ text ], client: client).first
    end

    # The text actually sent to the API. Titles carry a trailing " - Publisher"
    # on most rows, and leaving it in embeds the masthead: two unrelated Reuters
    # stories share a phrase that two newsrooms covering one strike do not.
    # Measured on the 300 labelled pairs at 256 dimensions, stripping it moves
    # the different-story mean 0.508 -> 0.475 while leaving the same-story mean
    # alone (0.694 -> 0.703), for AUC 0.911 -> 0.916. Small, and free.
    def prepare(text)
      RegistryNameIndex.strip_publisher(text.to_s).strip
    end

    # Identifies the exact text *and* vector space a stored embedding came from,
    # so changing the model or the width invalidates the corpus instead of
    # silently mixing two spaces that are not comparable.
    def digest_for(text)
      Digest::SHA1.hexdigest("#{MODEL}:#{DIMENSIONS}:#{prepare(text)}")
    end

    def model_tag
      "#{MODEL}@#{DIMENSIONS}"
    end

    # Cosine similarity of two vectors that are already normalised, i.e. a dot
    # product. Returns nil when either side is missing or the widths disagree,
    # which callers must read as "no measurement" rather than "no similarity".
    def cosine(left, right)
      return nil if left.blank? || right.blank?
      return nil if left.size != right.size

      sum = 0.0
      index = 0
      size = left.size
      while index < size
        sum += left[index] * right[index]
        index += 1
      end
      sum
    end

    def normalize_vector(vector)
      values = Array(vector).map(&:to_f)
      return nil if values.empty?

      magnitude = Math.sqrt(values.sum { |value| value * value })
      return nil if magnitude.zero?

      values.map { |value| value / magnitude }
    end

    private

    def request(inputs)
      api_key = ENV["OPENAI_API_KEY"]
      if api_key.blank?
        Rails.logger.warn("NewsHeadlineEmbeddingService: OPENAI_API_KEY missing")
        return nil
      end

      uri = URI(ENDPOINT)
      body = { model: MODEL, input: inputs, dimensions: DIMENSIONS }.to_json

      attempt = 0
      begin
        attempt += 1
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        post = Net::HTTP::Post.new(uri)
        post["Authorization"] = "Bearer #{api_key}"
        post["Content-Type"] = "application/json"
        post.body = body

        response = http.request(post)
        unless response.is_a?(Net::HTTPSuccess)
          raise "OpenAI #{response.code} #{response.body.to_s[0..200]}"
        end

        parsed = JSON.parse(response.body)
        # The API documents that data comes back in input order, but it also
        # carries the index, so ordering is asserted here rather than assumed.
        parsed.fetch("data").sort_by { |row| row["index"].to_i }.map { |row| row["embedding"] }
      rescue StandardError => e
        if attempt < MAX_ATTEMPTS
          sleep(attempt * 2)
          retry
        end
        Rails.logger.warn("NewsHeadlineEmbeddingService: #{e.class} #{e.message}")
        nil
      end
    end
  end
end
