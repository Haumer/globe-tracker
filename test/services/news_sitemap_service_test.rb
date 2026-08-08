require "test_helper"

class NewsSitemapServiceTest < ActiveSupport::TestCase
  # The test env runs :null_store, so every cache read returns nil and both
  # batch rotation and the publication-date watermark would silently no-op.
  # Swap in a real store so those paths are actually exercised.
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @service = NewsSitemapService.new
  end

  teardown do
    Rails.cache = @original_cache
  end

  def sitemap_xml(entries)
    body = entries.map do |e|
      <<~ENTRY
        <url>
          <loc>#{e[:loc]}</loc>
          <news:news>
            <news:publication>
              <news:name>#{e[:name] || 'Example News'}</news:name>
              <news:language>en</news:language>
            </news:publication>
            <news:publication_date>#{e[:date]}</news:publication_date>
            <news:title>#{e[:title]}</news:title>
          </news:news>
        </url>
      ENTRY
    end.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
              xmlns:news="http://www.google.com/schemas/sitemap-news/0.9">
        #{body}
      </urlset>
    XML
  end

  test "parse_entries extracts loc, title, publication and date" do
    xml = sitemap_xml([
      { loc: "https://example.com/a", title: "Strike hits depot",
        date: "2026-08-08T10:00:00Z", name: "Example News" },
    ])
    entries = @service.send(:parse_entries, xml)

    assert_equal 1, entries.size
    assert_equal "https://example.com/a", entries.first[:url]
    assert_equal "Strike hits depot", entries.first[:title]
    assert_equal "Example News", entries.first[:publication]
    assert_equal Time.utc(2026, 8, 8, 10), entries.first[:published_at]
  end

  test "parse_entries skips <url> nodes with no news metadata" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url><loc>https://example.com/plain</loc><lastmod>2026-08-08</lastmod></url>
      </urlset>
    XML
    assert_empty @service.send(:parse_entries, xml)
  end

  test "parse_entries drops undated entries" do
    xml = sitemap_xml([{ loc: "https://example.com/a", title: "T", date: "" }])
    assert_empty @service.send(:parse_entries, xml)
  end

  test "parse_entries tolerates an unexpected namespace prefix" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
              xmlns:n="http://www.google.com/schemas/sitemap-news/0.9">
        <url>
          <loc>https://example.com/a</loc>
          <n:news>
            <n:publication><n:name>X</n:name></n:publication>
            <n:publication_date>2026-08-08T10:00:00Z</n:publication_date>
            <n:title>Headline</n:title>
          </n:news>
        </url>
      </urlset>
    XML
    entries = @service.send(:parse_entries, xml)
    assert_equal 1, entries.size
    assert_equal "Headline", entries.first[:title]
  end

  test "select_fresh honours the cold-start age floor" do
    now = Time.current
    entries = [
      { url: "u1", published_at: now - 2.hours },
      { url: "u2", published_at: now - 40.hours },
    ]
    fresh = @service.send(:select_fresh, "example.com", entries, now: now)

    assert_equal [ "u1" ], fresh.map { |e| e[:url] }
  end

  test "select_fresh rejects entries dated beyond the future slack" do
    now = Time.current
    entries = [
      { url: "skew", published_at: now + 1.hour },     # plausible clock skew
      { url: "broken", published_at: now + 40.days },  # observed in the wild
    ]
    fresh = @service.send(:select_fresh, "example.com", entries, now: now)

    assert_equal [ "skew" ], fresh.map { |e| e[:url] }
  end

  test "select_fresh returns only entries newer than the stored watermark" do
    now = Time.current
    Rails.cache.write("news_sitemap_watermark:example.com", now - 3.hours)
    entries = [
      { url: "old", published_at: now - 5.hours },
      { url: "new", published_at: now - 1.hour },
    ]
    fresh = @service.send(:select_fresh, "example.com", entries, now: now)

    assert_equal [ "new" ], fresh.map { |e| e[:url] }
  end

  test "select_fresh caps a cold watermark at MAX_ITEMS_PER_POLL" do
    now = Time.current
    entries = Array.new(400) { |i| { url: "u#{i}", published_at: now - i.minutes } }
    fresh = @service.send(:select_fresh, "example.com", entries, now: now)

    assert_equal NewsSitemapService::MAX_ITEMS_PER_POLL, fresh.size
    # Newest first, so the cap keeps the most recent items.
    assert_equal "u0", fresh.first[:url]
  end

  test "advance_watermark stores the newest publication date" do
    now = Time.current
    entries = [
      { url: "a", published_at: now - 2.hours },
      { url: "b", published_at: now - 30.minutes },
    ]
    @service.send(:advance_watermark, "example.com", entries)

    stored = Rails.cache.read("news_sitemap_watermark:example.com")
    assert_in_delta (now - 30.minutes).to_f, stored.to_f, 1.0
  end

  test "advance_watermark never moves backwards" do
    now = Time.current
    Rails.cache.write("news_sitemap_watermark:example.com", now)
    @service.send(:advance_watermark, "example.com",
                  [ { url: "a", published_at: now - 5.hours } ])

    assert_in_delta now.to_f, Rails.cache.read("news_sitemap_watermark:example.com").to_f, 1.0
  end

  test "advance_watermark is a no-op for an empty batch" do
    @service.send(:advance_watermark, "example.com", [])
    assert_nil Rails.cache.read("news_sitemap_watermark:example.com")
  end

  test "registry loads and every row carries the fields the service reads" do
    sources = NewsSitemapService.reload_sources!
    assert_operator sources.size, :>, 100

    sources.each do |source|
      assert source["domain"].present?, "missing domain: #{source.inspect}"
      assert source["url"].to_s.start_with?("http"), "bad url: #{source.inspect}"
      assert_equal "sitemap", source["transport"]
      assert_includes 1..4, source["tier"]
      assert_includes %w[low medium high], source["risk"]
      assert_includes %w[us europe asia africa latam oceania global], source["region"]
    end
  end

  test "registry contains no duplicate domains" do
    domains = NewsSitemapService.reload_sources!.map { |s| s["domain"] }
    assert_equal domains.uniq.size, domains.size
  end

  test "current_batch rotates and covers every source across a full cycle" do
    sources = Array.new(42) { |i| { "domain" => "d#{i}" } }
    seen = []
    NewsSitemapService::BATCH_COUNT.times do
      seen.concat(@service.send(:current_batch, sources))
    end

    assert_equal sources.size, seen.uniq.size
  end
end
