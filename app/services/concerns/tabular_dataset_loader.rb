require "csv"
require "net/http"
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

  def fetch_remote_body(url, limit: 3)
    raise ArgumentError, "too many redirects for #{url}" if limit <= 0

    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 120) do |http|
      http.request(Net::HTTP::Get.new(uri))
    end

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      fetch_remote_body(response["location"], limit: limit - 1)
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
