require "test_helper"

class AcledServiceTest < ActiveSupport::TestCase
  test "constants are defined" do
    assert_equal "https://acleddata.com/oauth/token", AcledService::AUTH_URL
    assert_equal "https://acleddata.com/api/acled/read", AcledService::API_URL
    assert_equal 5000, AcledService::PAGE_LIMIT
    assert_equal "acled_access_token", AcledService::TOKEN_CACHE_KEY
  end

  test "credentials_configured? returns false when env vars missing" do
    original_email = ENV["ACLED_EMAIL"]
    original_pass = ENV["ACLED_PASSWORD"]
    begin
      ENV["ACLED_EMAIL"] = nil
      ENV["ACLED_PASSWORD"] = nil
      assert_not AcledService.credentials_configured?
    ensure
      ENV["ACLED_EMAIL"] = original_email
      ENV["ACLED_PASSWORD"] = original_pass
    end
  end

  test "acled_violence_type maps event types correctly" do
    assert_equal 1, AcledService.send(:acled_violence_type, "Battles - armed clash")
    assert_equal 1, AcledService.send(:acled_violence_type, "Explosions/Remote violence")
    assert_equal 2, AcledService.send(:acled_violence_type, "Riots/Mob violence")
    assert_equal 2, AcledService.send(:acled_violence_type, "Protests")
    assert_equal 3, AcledService.send(:acled_violence_type, "Violence against civilians")
    assert_equal 2, AcledService.send(:acled_violence_type, "Strategic developments")
  end

  test "refresh_if_stale returns 0 when credentials not configured" do
    original_email = ENV["ACLED_EMAIL"]
    original_pass = ENV["ACLED_PASSWORD"]
    begin
      ENV["ACLED_EMAIL"] = nil
      ENV["ACLED_PASSWORD"] = nil
      assert_equal 0, AcledService.refresh_if_stale
    ensure
      ENV["ACLED_EMAIL"] = original_email
      ENV["ACLED_PASSWORD"] = original_pass
    end
  end
end
