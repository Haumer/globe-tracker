module HttpClient
  def http_get(uri, headers: {}, open_timeout: 10, read_timeout: 30)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout

    request = Net::HTTP::Get.new(uri)
    headers.each { |k, v| request[k] = v }

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("#{name} HTTP GET #{uri.host}: #{response.code} #{response.body[0..100]}")
      return nil
    end

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("#{name} HTTP GET error: #{e.message}")
    nil
  end

  def http_post(uri, form_data:, headers: {}, open_timeout: 5, read_timeout: 10)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout

    request = Net::HTTP::Post.new(uri)
    request.set_form_data(form_data)
    headers.each { |k, v| request[k] = v }

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("#{name} HTTP POST #{uri.host}: #{response.code} #{response.body[0..200]}")
      return nil
    end

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("#{name} HTTP POST error: #{e.message}")
    nil
  end
end
