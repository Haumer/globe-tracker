require "test_helper"

class BackgroundRefreshableTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    BackgroundRefreshScheduler.reset!
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    BackgroundRefreshScheduler.reset!
  end

  test "enqueue_background_refresh enqueues job and sets header" do
    controller = build_controller
    result = controller.send(:enqueue_background_refresh,
      GenerateBriefJob,
      key: "test_refresh",
      debounce: 60
    )
    assert result
    assert_equal "queued", controller.response_headers["X-Background-Refresh"]
  end

  test "enqueue_background_refresh returns false when debounced" do
    controller = build_controller
    controller.send(:enqueue_background_refresh,
      GenerateBriefJob,
      key: "test_debounce",
      debounce: 60
    )

    # Second call should be debounced
    controller2 = build_controller
    result = controller2.send(:enqueue_background_refresh,
      GenerateBriefJob,
      key: "test_debounce",
      debounce: 60
    )
    assert_not result
    assert_nil controller2.response_headers["X-Background-Refresh"]
  end

  private

  def build_controller
    klass = Class.new do
      include BackgroundRefreshable
      attr_reader :response_headers

      def initialize
        @response_headers = {}
      end

      def response
        @_response ||= build_fake_response
      end

      private

      def build_fake_response
        headers = @response_headers
        obj = Object.new
        obj.define_singleton_method(:set_header) { |k, v| headers[k] = v }
        obj
      end
    end
    klass.new
  end
end
