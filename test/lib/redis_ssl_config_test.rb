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

  test "materializes a ca file from pem content" do
    pem = <<~PEM
      -----BEGIN CERTIFICATE-----
      MIIBhTCCASugAwIBAgIBADAKBggqhkjOPQQDAjASMRAwDgYDVQQDDAdUZXN0IENB
      MB4XDTI2MDQwMzE4MDAwMFoXDTM2MDQwMTE4MDAwMFowEjEQMA4GA1UEAwwHVGVz
      dCBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABKzt0C8fVWAdQY2vK7dcx5XO
      JeY6Lz3fK4L3CHV7nM3h3e5m3qjY6F1R3T0sq8Zk4wN1k0C7adQxqBwoM7exE/6j
      UzBRMB0GA1UdDgQWBBRz9faZrS0QJw7n8i9Q8S9Y2fYI1TAfBgNVHSMEGDAWgBRz
      9faZrS0QJw7n8i9Q8S9Y2fYI1TAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMC
      A0gAMEUCIQCrZq0l0x1bLkL9n5c3QY4+6XxP0Q2F0S1W4fQpE1Q7JQIgYs0aW5mQ
      7B0sWnWq8X+8v9D6zYX4LQ7bQ2u+v9w0JzA=
      -----END CERTIFICATE-----
    PEM

    params = RedisSslConfig.params_for("rediss://example.com", ca_pem: pem, allow_insecure: nil)

    assert_equal OpenSSL::SSL::VERIFY_PEER, params[:verify_mode]
    assert File.exist?(params[:ca_file])
    assert_equal pem, File.read(params[:ca_file])
  end

  test "materializes a ca file from base64 content" do
    pem = <<~PEM
      -----BEGIN CERTIFICATE-----
      MIIBhTCCASugAwIBAgIBADAKBggqhkjOPQQDAjASMRAwDgYDVQQDDAdUZXN0IENB
      MB4XDTI2MDQwMzE4MDAwMFoXDTM2MDQwMTE4MDAwMFowEjEQMA4GA1UEAwwHVGVz
      dCBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABKzt0C8fVWAdQY2vK7dcx5XO
      JeY6Lz3fK4L3CHV7nM3h3e5m3qjY6F1R3T0sq8Zk4wN1k0C7adQxqBwoM7exE/6j
      UzBRMB0GA1UdDgQWBBRz9faZrS0QJw7n8i9Q8S9Y2fYI1TAfBgNVHSMEGDAWgBRz
      9faZrS0QJw7n8i9Q8S9Y2fYI1TAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMC
      A0gAMEUCIQCrZq0l0x1bLkL9n5c3QY4+6XxP0Q2F0S1W4fQpE1Q7JQIgYs0aW5mQ
      7B0sWnWq8X+8v9D6zYX4LQ7bQ2u+v9w0JzA=
      -----END CERTIFICATE-----
    PEM

    params = RedisSslConfig.params_for("rediss://example.com", ca_base64: Base64.strict_encode64(pem), allow_insecure: nil)

    assert_equal OpenSSL::SSL::VERIFY_PEER, params[:verify_mode]
    assert File.exist?(params[:ca_file])
    assert_equal pem, File.read(params[:ca_file])
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
