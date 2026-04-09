require "test_helper"

class NewsOntologyBatchJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "is assigned to the background queue" do
    assert_equal "background", NewsOntologyBatchJob.new.queue_name
  end

  test "tracks polling with correct source and poll_type" do
    job = NewsOntologyBatchJob.new
    assert_equal "ontology", job.class.polling_type_resolver
    # source is a lambda that resolves from args
    assert_respond_to job.class.polling_source_resolver, :call
  end

  test "polling source resolves from target argument" do
    resolver = NewsOntologyBatchJob.polling_source_resolver
    assert_equal "news-ontology:flights", resolver.call(nil, ["flights"])
  end

  test "calls NewsOntologySyncService.sync_batch with target and options" do
    called_with = nil
    mock = ->(target, **opts) { called_with = [target, opts]; { records_stored: 5 } }

    NewsOntologySyncService.stub(:sync_batch, mock) do
      NewsOntologyBatchJob.perform_now("news_articles", { "batch_size" => 50 })
    end

    assert_equal "news_articles", called_with[0]
    assert_equal 50, called_with[1][:batch_size]
  end

  test "enqueues next batch when next_cursor is present" do
    result = { next_cursor: 42, batch_size: 50 }

    NewsOntologySyncService.stub(:sync_batch, ->(*_args, **_kw) { result }) do
      assert_enqueued_with(job: NewsOntologyBatchJob) do
        NewsOntologyBatchJob.perform_now("news_articles")
      end
    end
  end

  test "does not enqueue next batch when no next_cursor" do
    result = { records_stored: 5 }

    NewsOntologySyncService.stub(:sync_batch, ->(*_args, **_kw) { result }) do
      assert_no_enqueued_jobs(only: NewsOntologyBatchJob) do
        NewsOntologyBatchJob.perform_now("news_articles")
      end
    end
  end
end
