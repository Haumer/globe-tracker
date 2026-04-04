require "csv"
require "net/http"
require "openssl"
require "uri"
require "zlib"

module TabularDatasetLoader
  private

  def csv_rows_from_source(path: nil, url: nil)
    body = source_body(path: path, url: url)
    return [] if body.blank?

    csv_text = decoded_text(body, path: path, url: url)
    CSV.parse(csv_text, headers: true, liberal_parsing: true)
  end

  def source_body(path: nil, url: nil)
    return File.binread(path) if path.present? && File.exist?(path)
    return if url.blank?

    fetch_remote_body(url)
  end

  def fetch_remote_body(url, limit: 3, verify_ssl: true)
    raise ArgumentError, "too many redirects for #{url}" if limit <= 0

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 15
    http.read_timeout = 120
    http.verify_mode = verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE if http.use_ssl?

    response = http.start do |client|
      client.request(Net::HTTP::Get.new(uri))
    end

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      fetch_remote_body(response["location"], limit: limit - 1, verify_ssl: verify_ssl)
    else
      raise "HTTP #{response.code} while fetching #{url}"
    end
  end

  def decoded_text(body, path: nil, url: nil)
    payload = gzip_payload?(body, path: path, url: url) ? Zlib::GzipReader.new(StringIO.new(body)).read : body
    payload.to_s.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  end

  def gzip_payload?(body, path: nil, url: nil)
    source_token = path.to_s.presence || url.to_s
    source_token.end_with?(".gz") || body.to_s.byteslice(0, 2) == "\x1F\x8B".b
  end
end
