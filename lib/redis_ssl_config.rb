require "base64"
require "digest"
require "fileutils"
require "tmpdir"

module RedisSslConfig
  module_function

  def params_for(
    url,
    ca_file: ENV["REDIS_CA_CERT"],
    ca_pem: ENV["REDIS_CA_CERT_PEM"],
    ca_base64: ENV["REDIS_CA_CERT_BASE64"],
    allow_insecure: ENV["ALLOW_INSECURE_REDIS_SSL"]
  )
    return nil unless rediss_url?(url)

    materialized_ca_file = ca_file.presence || materialized_ca_file_for(ca_pem: ca_pem, ca_base64: ca_base64)

    if materialized_ca_file.present?
      {
        verify_mode: OpenSSL::SSL::VERIFY_PEER,
        ca_file: materialized_ca_file,
      }
    elsif truthy?(allow_insecure)
      {
        verify_mode: OpenSSL::SSL::VERIFY_NONE,
      }
    else
      {
        verify_mode: OpenSSL::SSL::VERIFY_PEER,
      }
    end
  end

  def rediss_url?(url)
    url.to_s.start_with?("rediss://")
  end

  def truthy?(value)
    value.to_s.match?(/\A(1|true|yes|on)\z/i)
  end

  def materialized_ca_file_for(ca_pem:, ca_base64:)
    pem = normalized_pem(ca_pem, ca_base64)
    return nil if pem.blank?

    fingerprint = Digest::SHA256.hexdigest(pem)
    path = File.join(Dir.tmpdir, "globe-tracker-redis-ca-#{fingerprint}.pem")
    return path if File.exist?(path) && File.read(path) == pem

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, pem)
    path
  end

  def normalized_pem(ca_pem, ca_base64)
    return ca_pem if ca_pem.to_s.include?("BEGIN CERTIFICATE")
    return nil if ca_base64.blank?

    decoded = Base64.strict_decode64(ca_base64.to_s)
    decoded if decoded.include?("BEGIN CERTIFICATE")
  rescue ArgumentError
    nil
  end
end
