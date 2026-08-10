require "test_helper"

# Regression cover for the fault that stopped RSS, GDELT and the API providers
# producing map events in April 2026: records that failed normalization were
# skipped by a `next unless ids`, leaving two key shapes in the batch, and
# NewsEvent.upsert_all rejects a batch whose rows do not all carry the same
# keys.
class NewsNormalizationRecorderApplyIdsTest < ActiveSupport::TestCase
  def record(url)
    {
      url: url,
      title: "Headline for #{url}",
      latitude: 51.5,
      longitude: -0.12,
      source: "rss",
      published_at: Time.current,
      fetched_at: Time.current,
      created_at: Time.current,
      updated_at: Time.current,
    }
  end

  test "stamps every record even when some had no normalization id" do
    hit = record("https://example.com/a")
    miss = record("https://news.google.com/rss/articles/OPAQUE")
    ids = { hit[:url] => { news_article_id: 7, news_source_id: 3, content_scope: "world" } }

    NewsNormalizationRecorder.apply_ids!([hit, miss], ids)

    assert_equal hit.keys.sort, miss.keys.sort, "key sets diverged, upsert_all would reject the batch"
    assert_equal 7, hit[:news_article_id]
    assert_nil miss[:news_article_id]
    assert_nil miss[:news_source_id]
  end

  test "upsert_all accepts a batch containing an unnormalizable url" do
    hit = record("https://example.com/accepted")
    miss = record("https://news.google.com/rss/articles/UNMATCHED")
    ids = { hit[:url] => { news_article_id: nil, news_source_id: nil, content_scope: "world" } }

    NewsNormalizationRecorder.apply_ids!([hit, miss], ids)

    assert_difference "NewsEvent.count", 2 do
      NewsEvent.upsert_all([hit, miss], unique_by: :url)
    end
  end

  test "a miss leaves any content_scope the record already carried" do
    r = record("https://example.com/scoped").merge(content_scope: "regional")

    NewsNormalizationRecorder.apply_ids!([r], {})

    assert_equal "regional", r[:content_scope]
  end

  test "harmonizes key sets that diverged before normalization ran" do
    # NewsRefreshService merges GKG features and conflict-query articles into
    # one batch, and their shapes drift apart depending on what came back.
    gkg = record("https://example.com/gkg").merge(tone: -3.2, themes: %w[conflict])
    doc = record("https://example.com/doc").merge(credibility: "tier1/low")

    NewsNormalizationRecorder.apply_ids!([gkg, doc], {})

    assert_equal gkg.keys.sort, doc.keys.sort
    assert_nil doc[:tone]
    assert_nil gkg[:credibility]
    assert_equal(-3.2, gkg[:tone])
  end

  test "upsert_all accepts a batch whose builders disagreed on shape" do
    gkg = record("https://example.com/shape-a").merge(tone: -1.5)
    doc = record("https://example.com/shape-b").merge(credibility: "tier2/medium")

    NewsNormalizationRecorder.apply_ids!([gkg, doc], {})

    assert_difference "NewsEvent.count", 2 do
      NewsEvent.upsert_all([gkg, doc], unique_by: :url)
    end
  end

  # A NOT NULL column with a default is the common case here -- filling nil
  # would just swap a lost batch for a NotNullViolation.
  test "fills a missing NOT NULL column from its database default" do
    with_geo = record("https://example.com/precise").merge(geocode_precision: "point")
    without = record("https://example.com/vague")

    NewsNormalizationRecorder.apply_ids!([with_geo, without], {})

    assert_equal "unknown", without[:geocode_precision]
    assert_equal "point", with_geo[:geocode_precision]

    assert_difference "NewsEvent.count", 2 do
      NewsEvent.upsert_all([with_geo, without], unique_by: :url)
    end
  end

  test "an empty id map still yields one uniform shape" do
    rows = [record("https://example.com/1"), record("https://example.com/2")]

    NewsNormalizationRecorder.apply_ids!(rows, {})

    assert_equal 1, rows.map { |r| r.keys.sort }.uniq.size
    assert_includes rows.first.keys, :news_article_id
  end
end
