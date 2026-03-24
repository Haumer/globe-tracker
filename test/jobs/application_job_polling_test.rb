require "test_helper"

class DummySuccessPollingJob < ApplicationJob
  tracks_polling source: ->(_job, args) { "dummy-#{args.first}" }, poll_type: "demo"

  def perform(name, count)
    Array.new(count, name)
  end
end

class DummyErrorPollingJob < ApplicationJob
  tracks_polling source: "dummy-error", poll_type: "demo"

  def perform
    raise "boom"
  end
end

class ApplicationJobPollingTest < ActiveSupport::TestCase
  test "tracked jobs write success polling stats" do
    assert_difference "PollingStat.count", 1 do
      result = DummySuccessPollingJob.perform_now("alpha", 3)
      assert_equal %w[alpha alpha alpha], result
    end

    stat = PollingStat.order(:created_at).last
    assert_equal "dummy-alpha", stat.source
    assert_equal "demo", stat.poll_type
    assert_equal "success", stat.status
    assert_equal 3, stat.records_fetched
    assert_equal 3, stat.records_stored
  end

  test "tracked jobs write error polling stats" do
    assert_difference "PollingStat.count", 1 do
      error = assert_raises(RuntimeError) { DummyErrorPollingJob.perform_now }
      assert_equal "boom", error.message
    end

    stat = PollingStat.order(:created_at).last
    assert_equal "dummy-error", stat.source
    assert_equal "demo", stat.poll_type
    assert_equal "error", stat.status
    assert_match("RuntimeError: boom", stat.error_message)
  end
end
