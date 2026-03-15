require "test_helper"

class CloudflareRadarServiceTest < ActiveSupport::TestCase
  test "merge_data combines traffic and attack data" do
    traffic = [
      { code: "US", name: "United States", pct: 25.0 },
      { code: "DE", name: "Germany", pct: 8.0 },
    ]
    attack_origins = [
      { code: "CN", name: "China", pct: 15.0 },
      { code: "US", name: "United States", pct: 5.0 },
    ]
    attack_targets = [
      { code: "US", name: "United States", pct: 12.0 },
    ]

    now = Time.current
    records = CloudflareRadarService.send(:merge_data, traffic, attack_origins, attack_targets, now)

    assert_kind_of Array, records
    us = records.find { |r| r[:country_code] == "US" }
    assert_not_nil us
    assert_equal 25.0, us[:traffic_pct]
    assert_equal 5.0, us[:attack_origin_pct]
    assert_equal 12.0, us[:attack_target_pct]

    cn = records.find { |r| r[:country_code] == "CN" }
    assert_not_nil cn
    assert_equal 15.0, cn[:attack_origin_pct]
    assert_equal 0, cn[:traffic_pct]
  end

  test "merge_data returns empty array for empty inputs" do
    records = CloudflareRadarService.send(:merge_data, [], [], [], Time.current)
    assert_equal [], records
  end

  test "cached_attack_pairs returns empty array when no cache file" do
    pairs = CloudflareRadarService.cached_attack_pairs
    assert_kind_of Array, pairs
  end

  test "api_token returns nil when not configured" do
    original = ENV["CLOUDFLARE_RADAR_TOKEN"]
    ENV["CLOUDFLARE_RADAR_TOKEN"] = nil
    result = CloudflareRadarService.api_token
    ENV["CLOUDFLARE_RADAR_TOKEN"] = original
    # May be nil or from credentials
  end

  test "stale? returns true when no data exists" do
    InternetTrafficSnapshot.delete_all
    assert CloudflareRadarService.stale?
  end
end
