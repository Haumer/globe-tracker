require "test_helper"

class TabularDatasetLoaderTest < ActiveSupport::TestCase
  class TestLoader
    include TabularDatasetLoader
    public :csv_rows_from_source, :source_body, :decoded_text, :gzip_payload?, :fetch_remote_body
  end

  setup do
    @loader = TestLoader.new
  end

  test "csv_rows_from_source parses CSV from local file" do
    path = Rails.root.join("tmp", "test_dataset.csv")
    File.write(path, "name,value\nalpha,1\nbeta,2\n")

    rows = @loader.csv_rows_from_source(path: path.to_s)

    assert_equal 2, rows.size
    assert_equal "alpha", rows[0]["name"]
    assert_equal "1", rows[0]["value"]
    assert_equal "beta", rows[1]["name"]
  ensure
    File.delete(path) if File.exist?(path)
  end

  test "csv_rows_from_source returns empty array when file does not exist" do
    rows = @loader.csv_rows_from_source(path: "/tmp/nonexistent_dataset_xyz.csv")

    assert_equal [], rows
  end

  test "csv_rows_from_source returns empty array when both path and url are nil" do
    rows = @loader.csv_rows_from_source(path: nil, url: nil)

    assert_equal [], rows
  end

  test "csv_rows_from_source fetches from URL" do
    csv_body = "col_a,col_b\nx,1\ny,2\n"
    stub_request(:get, "https://example.com/data.csv")
      .to_return(status: 200, body: csv_body)

    rows = @loader.csv_rows_from_source(url: "https://example.com/data.csv")

    assert_equal 2, rows.size
    assert_equal "x", rows[0]["col_a"]
  end

  test "csv_rows_from_source handles gzip file" do
    csv_text = "a,b\n1,2\n"
    gz_body = StringIO.new.tap do |io|
      gz = Zlib::GzipWriter.new(io)
      gz.write(csv_text)
      gz.close
    end.string

    path = Rails.root.join("tmp", "test_dataset.csv.gz")
    File.binwrite(path, gz_body)

    rows = @loader.csv_rows_from_source(path: path.to_s)

    assert_equal 1, rows.size
    assert_equal "1", rows[0]["a"]
    assert_equal "2", rows[0]["b"]
  ensure
    File.delete(path) if File.exist?(path)
  end

  test "source_body reads local file" do
    path = Rails.root.join("tmp", "test_source_body.csv")
    File.write(path, "hello")

    result = @loader.source_body(path: path.to_s)

    assert_equal "hello", result
  ensure
    File.delete(path) if File.exist?(path)
  end

  test "source_body returns nil when no path and no url" do
    result = @loader.source_body(path: nil, url: nil)

    assert_nil result
  end

  test "gzip_payload? detects gz extension" do
    assert @loader.gzip_payload?("anything", path: "data.csv.gz")
  end

  test "gzip_payload? detects gzip magic bytes" do
    gz_header = "\x1F\x8B".b + "rest of data"
    assert @loader.gzip_payload?(gz_header, path: "data.csv")
  end

  test "gzip_payload? returns false for plain text" do
    refute @loader.gzip_payload?("name,value\n", path: "data.csv")
  end

  test "decoded_text forces UTF-8 encoding" do
    result = @loader.decoded_text("hello world", path: "data.csv")

    assert_equal Encoding::UTF_8, result.encoding
    assert_equal "hello world", result
  end

  test "decoded_text replaces invalid UTF-8 chars" do
    bad_bytes = "hello\xFF\xFEworld"
    result = @loader.decoded_text(bad_bytes, path: "data.csv")

    assert_equal Encoding::UTF_8, result.encoding
    refute result.include?("\xFF")
  end

  test "fetch_remote_body follows redirects" do
    stub_request(:get, "https://example.com/redirect")
      .to_return(status: 302, headers: { "Location" => "https://example.com/final" })
    stub_request(:get, "https://example.com/final")
      .to_return(status: 200, body: "final content")

    result = @loader.fetch_remote_body("https://example.com/redirect")

    assert_equal "final content", result
  end

  test "fetch_remote_body raises on too many redirects" do
    stub_request(:get, "https://example.com/loop")
      .to_return(status: 302, headers: { "Location" => "https://example.com/loop" })

    assert_raises(ArgumentError) do
      @loader.fetch_remote_body("https://example.com/loop", limit: 1)
    end
  end

  test "fetch_remote_body raises on HTTP error" do
    stub_request(:get, "https://example.com/error")
      .to_return(status: 500, body: "Server Error")

    assert_raises(RuntimeError) do
      @loader.fetch_remote_body("https://example.com/error")
    end
  end
end
