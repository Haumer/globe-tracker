require "test_helper"

class NewsHeadlineEmbeddingServiceTest < ActiveSupport::TestCase
  def stub(*batches)
    calls = batches.dup
    ->(_inputs) { calls.shift }
  end

  test "normalises to unit length so cosine is a plain dot product" do
    vector = NewsHeadlineEmbeddingService.normalize_vector([ 3.0, 4.0 ])

    assert_in_delta 0.6, vector[0], 1e-9
    assert_in_delta 0.8, vector[1], 1e-9
    assert_in_delta 1.0, NewsHeadlineEmbeddingService.cosine(vector, vector), 1e-9
  end

  test "cosine of orthogonal headlines is zero" do
    assert_in_delta 0.0, NewsHeadlineEmbeddingService.cosine([ 1.0, 0.0 ], [ 0.0, 1.0 ]), 1e-9
  end

  # nil is "not measured", not "not similar". A caller that read a width
  # mismatch as 0.0 would veto every merge the moment the corpus held two
  # vector spaces at once.
  test "cosine returns nil rather than zero when there is nothing to compare" do
    assert_nil NewsHeadlineEmbeddingService.cosine([ 1.0, 0.0 ], [ 1.0, 0.0, 0.0 ])
    assert_nil NewsHeadlineEmbeddingService.cosine(nil, [ 1.0 ])
    assert_nil NewsHeadlineEmbeddingService.cosine([], [])
  end

  test "a zero vector has no direction and cannot be normalised" do
    assert_nil NewsHeadlineEmbeddingService.normalize_vector([ 0.0, 0.0 ])
  end

  test "strips the publisher before embedding" do
    assert_equal "Aramco refinery erupts in flames in Jizan",
      NewsHeadlineEmbeddingService.prepare("Aramco refinery erupts in flames in Jizan - Reuters")
  end

  # The digest is what makes the backfill idempotent, so it has to change when
  # any input to the vector changes -- including the width, because a 256-wide
  # vector is not comparable with a 1536-wide one.
  test "digest covers the text, the model and the width" do
    a = NewsHeadlineEmbeddingService.digest_for("Strike hits depot")
    b = NewsHeadlineEmbeddingService.digest_for("Strike hits depot - BBC")
    c = NewsHeadlineEmbeddingService.digest_for("Strike hits港")

    assert_equal a, b, "the publisher is not part of the embedded text"
    assert_not_equal a, c
    assert_includes NewsHeadlineEmbeddingService.model_tag, NewsHeadlineEmbeddingService::DIMENSIONS.to_s
  end

  test "maps vectors back to the position of their input" do
    result = NewsHeadlineEmbeddingService.embed(
      [ "first headline", "second headline" ],
      client: stub([ [ 3.0, 4.0 ], [ 0.0, 5.0 ] ])
    )

    assert_in_delta 0.6, result[0][0], 1e-9
    assert_in_delta 1.0, result[1][1], 1e-9
  end

  # A blank title must not consume a slot in the request, or every vector after
  # it comes back attached to the wrong article.
  test "blank inputs are skipped without shifting the others" do
    sent = nil
    client = ->(inputs) { sent = inputs; [ [ 1.0, 0.0 ], [ 0.0, 1.0 ] ] }

    result = NewsHeadlineEmbeddingService.embed([ "alpha", "", "beta" ], client: client)

    assert_equal [ "alpha", "beta" ], sent
    assert_nil result[1]
    assert_in_delta 1.0, result[0][0], 1e-9
    assert_in_delta 1.0, result[2][1], 1e-9
  end

  # An embedding that cannot be fetched leaves the clusterer on its lexical
  # floor, which is a working state. Raising here would take the news sync down.
  test "survives a dead client" do
    result = NewsHeadlineEmbeddingService.embed([ "alpha" ], client: ->(_) { nil })

    assert_equal [ nil ], result
  end

  test "asks nothing when there is nothing to embed" do
    called = false
    NewsHeadlineEmbeddingService.embed([ "", nil ], client: ->(_) { called = true })

    assert_not called
    assert_equal [], NewsHeadlineEmbeddingService.embed([])
  end
end
