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

  test "an empty id map still yields one uniform shape" do
    rows = [record("https://example.com/1"), record("https://example.com/2")]

    NewsNormalizationRecorder.apply_ids!(rows, {})

    assert_equal 1, rows.map { |r| r.keys.sort }.uniq.size
    assert_includes rows.first.keys, :news_article_id
  end
end
