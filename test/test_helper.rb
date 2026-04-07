ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "ostruct"
require "webmock/minitest"
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

# Block all external HTTP requests in tests — forces proper stubbing
WebMock.disable_net_connect!(allow_localhost: true)
WebMock.stub_request(:get, %r{\Ahttps://query1\.finance\.yahoo\.com/v8/finance/chart/})
  .to_return(
    status: 200,
    body: { chart: { result: [], error: nil } }.to_json,
    headers: { "Content-Type" => "application/json" }
  )

module Rails
  module LineFiltering
    # Rails 7.1 expects the older Minitest run signature; Minitest 6 passes 3 args.
    def run(*args)
      return super(*args) if args.length == 3 && !args.last.is_a?(Hash)

      options = args.last.is_a?(Hash) ? args.last : {}
      options = options.merge(filter: Rails::TestUnit::Runner.compose_filter(self, options[:filter]))

      if args.last.is_a?(Hash)
        args[-1] = options
      else
        args << options
      end

      super(*args)
    end
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
