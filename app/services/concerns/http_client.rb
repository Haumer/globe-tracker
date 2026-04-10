module HttpClient
  include CircuitBreaker

  # Perform an HTTP GET with automatic retry and cache fallback.
  #
  # Options:
  #   retries:       number of retry attempts (default: 2)
  #   retry_delay:   base delay in seconds between retries, doubled each attempt (default: 1)
  #   cache_key:     if provided, caches successful responses and returns cached data on failure
  #   cache_ttl:     how long to cache successful responses (default: 10.minutes)
  #
  def http_get(uri, headers: {}, open_timeout: 10, read_timeout: 30,
               retries: 2, retry_delay: 1, cache_key: nil, cache_ttl: 10.minutes)
    cb_key = circuit_key_for(uri)

    # Short-circuit when the breaker is open
    if CircuitBreaker.state_for(cb_key) == CircuitBreaker::OPEN
      Rails.logger.info("#{name} HTTP GET skipped (circuit open) for #{uri.host}")
      return _cache_fallback(cache_key)
    end

    attempts = 0
    last_error = nil

    loop do
      attempts += 1
      begin
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout

        request = Net::HTTP::Get.new(uri)
        headers.each { |k, v| request[k] = v }

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          last_error = "HTTP #{response.code}"
          Rails.logger.warn("#{name} HTTP GET #{uri.host}: #{response.code} #{response.body&.slice(0, 100)}")
          # 429 = rate limited — don't retry or trip circuit breaker, just back off
          if response.code == "429"
            Rails.logger.info("#{name} HTTP GET rate limited (429) — skipping retries")
            return _cache_fallback(cache_key)
          end
          raise StandardError, last_error
        end

        parsed = JSON.parse(response.body)

        # Cache successful response for fallback
        if cache_key
          Rails.cache.write(cache_key, parsed, expires_in: cache_ttl)
        end

        CircuitBreaker.record_success(cb_key)
        return parsed
      rescue StandardError => e
        last_error = e.message
        CircuitBreaker.record_failure(cb_key)

        if attempts <= retries
          # If the breaker just tripped open, stop retrying
          if CircuitBreaker.state_for(cb_key) == CircuitBreaker::OPEN
            Rails.logger.info("#{name} HTTP GET circuit opened — aborting retries for #{uri.host}")
            break
          end

          delay = retry_delay * (2**(attempts - 1))
          Rails.logger.info("#{name} HTTP GET retry #{attempts}/#{retries} after #{delay}s: #{e.message}")
          sleep(delay)
        else
          Rails.logger.error("#{name} HTTP GET failed after #{attempts} attempts: #{e.message}")
          break
        end
      end
    end

    _cache_fallback(cache_key)
  end

  # Perform an HTTP POST with automatic retry.
  def http_post(uri, form_data:, headers: {}, open_timeout: 5, read_timeout: 10,
                retries: 1, retry_delay: 1)
    cb_key = circuit_key_for(uri)

    if CircuitBreaker.state_for(cb_key) == CircuitBreaker::OPEN
      Rails.logger.info("#{name} HTTP POST skipped (circuit open) for #{uri.host}")
      return nil
    end

    attempts = 0

    loop do
      attempts += 1
      begin
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout

        request = Net::HTTP::Post.new(uri)
        request.set_form_data(form_data)
        headers.each { |k, v| request[k] = v }

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("#{name} HTTP POST #{uri.host}: #{response.code} #{response.body&.slice(0, 200)}")
          raise StandardError, "HTTP #{response.code}"
        end

        CircuitBreaker.record_success(cb_key)
        return JSON.parse(response.body)
      rescue StandardError => e
        CircuitBreaker.record_failure(cb_key)

        if attempts <= retries
          if CircuitBreaker.state_for(cb_key) == CircuitBreaker::OPEN
            Rails.logger.info("#{name} HTTP POST circuit opened — aborting retries for #{uri.host}")
            return nil
          end

          delay = retry_delay * (2**(attempts - 1))
          Rails.logger.info("#{name} HTTP POST retry #{attempts}/#{retries} after #{delay}s: #{e.message}")
          sleep(delay)
        else
          Rails.logger.error("#{name} HTTP POST failed after #{attempts} attempts: #{e.message}")
          return nil
        end
      end
    end
  end

  private

  def _cache_fallback(cache_key)
    if cache_key
      cached = Rails.cache.read(cache_key)
      if cached
        Rails.logger.info("#{name} serving stale cache fallback")
        return cached
      end
    end
    nil
  end
end
