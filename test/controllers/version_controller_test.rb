require "test_helper"

class VersionControllerTest < ActionDispatch::IntegrationTest
  test "returns the current app revision without caching" do
    get "/version"

    assert_response :success
    assert_equal "application/json; charset=utf-8", response.headers["Content-Type"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "no-cache", response.headers["Pragma"]
    assert_equal "0", response.headers["Expires"]

    body = JSON.parse(response.body)
    assert_match(/\A[a-f0-9]{40}\z/, body.fetch("revision"))
  end

  test "matches the revision embedded in the home page" do
    get "/"
    assert_response :success

    html_revision = response.body[/<meta name="app-revision" content="([^"]+)"/, 1]
    assert_predicate html_revision, :present?

    get "/version"
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal html_revision, body.fetch("revision")
  end
end
