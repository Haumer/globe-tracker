require "test_helper"

class Api::BriefsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = User.create!(email: "admin-brief@example.com", password: "password123", admin: true)
    @user = User.create!(email: "user-brief@example.com", password: "password123", admin: false)
    @original_cache = Rails.cache
    Rails.application.config.cache_store = :memory_store
    @memory_cache = ActiveSupport::Cache::MemoryStore.new
    Rails.instance_variable_set(:@cache, @memory_cache)
  end

  teardown do
    Rails.instance_variable_set(:@cache, @original_cache)
    Rails.application.config.cache_store = :null_store
  end

  test "returns forbidden for non-admin user" do
    sign_in @user
    get "/api/brief"
    assert_response :forbidden

    body = JSON.parse(response.body)
    assert_equal "Not authorized", body["error"]
  end

  test "returns forbidden for anonymous user" do
    get "/api/brief"
    assert_response :forbidden

    body = JSON.parse(response.body)
    assert_equal "Not authorized", body["error"]
  end

  test "returns cached brief when available" do
    brief_data = { "headline" => "Test Brief", "sections" => [] }
    Rails.cache.write(IntelligenceBriefService::CACHE_KEY, brief_data)

    sign_in @admin
    get "/api/brief"
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "Test Brief", body["headline"]
  end

  test "returns generating status when no brief cached" do
    sign_in @admin

    assert_enqueued_with(job: GenerateBriefJob) do
      get "/api/brief"
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "generating", body["status"]
    assert body["message"].include?("being generated")
  end

  test "does not enqueue duplicate brief generation" do
    Rails.cache.write("brief_generating", true, expires_in: 2.minutes)

    sign_in @admin

    assert_no_enqueued_jobs(only: GenerateBriefJob) do
      get "/api/brief"
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "generating", body["status"]
  end
end
