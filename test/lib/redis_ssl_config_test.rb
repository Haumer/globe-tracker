require "test_helper"
require Rails.root.join("lib/redis_ssl_config")

class RedisSslConfigTest < ActiveSupport::TestCase
  test "returns nil for non-tls redis urls" do
    assert_nil RedisSslConfig.params_for("redis://localhost:6379/1")
  end

  test "prefers peer verification with a ca file" do
    params = RedisSslConfig.params_for("rediss://example.com", ca_file: "/tmp/redis-ca.pem", allow_insecure: "1")

    assert_equal OpenSSL::SSL::VERIFY_PEER, params[:verify_mode]
    assert_equal "/tmp/redis-ca.pem", params[:ca_file]
  end

  test "only allows verify none when explicitly opted in" do
    params = RedisSslConfig.params_for("rediss://example.com", ca_file: nil, allow_insecure: "1")

    assert_equal OpenSSL::SSL::VERIFY_NONE, params[:verify_mode]
  end

  test "defaults to peer verification without a ca file" do
    params = RedisSslConfig.params_for("rediss://example.com", ca_file: nil, allow_insecure: nil)

    assert_equal OpenSSL::SSL::VERIFY_PEER, params[:verify_mode]
    assert_nil params[:ca_file]
  end
end
