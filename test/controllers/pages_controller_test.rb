require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home page renders the selected context pane" do
    get "/"

    assert_response :success
    assert_match(/selected context/i, response.body)
    assert_includes response.body, "Live Context"
    refute_includes response.body, "aria-label=\"Data panels\""
    assert_includes response.body, "data-rp-pane=\"context\""
    assert_includes response.body, "id=\"mobile-hud\""
    assert_includes response.body, "data-mobile-scene=\"2d\""
    assert_includes response.body, "id=\"mobile-sheet-scrim\""
  end

  test "home page includes social metadata and favicon links" do
    get "/"

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "no-cache", response.headers["Pragma"]
    assert_equal "0", response.headers["Expires"]
    assert_match(/name="app-revision" content="[a-f0-9]+"/, response.body)
    assert_match(/property="og:title" content="GlobeTracker \| Live Global Tracking"/, response.body)
    assert_match(/property="og:image" content="http:\/\/www\.example\.com\/og-card\.png"/, response.body)
    assert_match(/name="twitter:card" content="summary_large_image"/, response.body)
    assert_match(/rel="icon" href="\/favicon\.ico" sizes="any"/, response.body)
    assert_match(/href="\/favicon-32x32\.png"/, response.body)
    assert_match(/href="\/favicon-16x16\.png"/, response.body)
  end

  test "sources page lists active source inventory entries without removed placeholders" do
    get "/sources"

    assert_response :success
    assert_includes response.body, "Curated RSS Mesh"
    assert_includes response.body, "Multi-source News APIs"
    refute_includes response.body, "ReliefWeb"
    refute_includes response.body, "Media Cloud"
    refute_includes response.body, "Legacy Reuters RSS"
  end
end
