module HttpClient
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
          raise StandardError, last_error
        end

        parsed = JSON.parse(response.body)

        # Cache successful response for fallback
        if cache_key
          Rails.cache.write(cache_key, parsed, expires_in: cache_ttl)
        end

        return parsed
      rescue StandardError => e
        last_error = e.message

        if attempts <= retries
          delay = retry_delay * (2**(attempts - 1))
          Rails.logger.info("#{name} HTTP GET retry #{attempts}/#{retries} after #{delay}s: #{e.message}")
          sleep(delay)
        else
          Rails.logger.error("#{name} HTTP GET failed after #{attempts} attempts: #{e.message}")
          break
        end
      end
    end

    # Fallback to cached data if available
    if cache_key
      cached = Rails.cache.read(cache_key)
      if cached
        Rails.logger.info("#{name} HTTP GET serving stale cache for #{uri.host}")
        return cached
      end
    end

    nil
  end

  # Perform an HTTP POST with automatic retry.
  def http_post(uri, form_data:, headers: {}, open_timeout: 5, read_timeout: 10,
                retries: 1, retry_delay: 1)
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

        return JSON.parse(response.body)
      rescue StandardError => e
        if attempts <= retries
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
end
