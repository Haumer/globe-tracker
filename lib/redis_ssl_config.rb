module RedisSslConfig
  module_function

  def params_for(url, ca_file: ENV["REDIS_CA_CERT"], allow_insecure: ENV["ALLOW_INSECURE_REDIS_SSL"])
    return nil unless rediss_url?(url)

    if ca_file.present?
      {
        verify_mode: OpenSSL::SSL::VERIFY_PEER,
        ca_file: ca_file,
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
end
