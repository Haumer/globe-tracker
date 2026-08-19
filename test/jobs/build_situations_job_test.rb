require "test_helper"

class BuildSituationsJobTest < ActiveJob::TestCase
  test "runs occurrence links before the builder" do
    order = []

    HazardOccurrenceLinkService.stub(:sync_recent, -> { order << :links; {} }) do
      SituationBuilder.stub(:call, -> { order << :build; {} }) do
        BuildSituationsJob.perform_now
      end
    end

    assert_equal [ :links, :build ], order,
      "the builder keys hazard members off the edges the link step writes"
  end

  test "records a failed poll when the chain raises" do
    PollingStat.where(source: "situations:build").delete_all

    HazardOccurrenceLinkService.stub(:sync_recent, -> { raise "boom" }) do
      assert_raises(RuntimeError) { BuildSituationsJob.perform_now }
    end

    stat = PollingStat.where(source: "situations:build").order(created_at: :desc).first
    assert_equal "error", stat.status, "a failing build must not report success"
  end

  test "is scheduled behind the relationship syncs it reads from" do
    schedules = GlobalPollerService::JOB_SCHEDULES.index_by { |entry| entry[:job] }
    build = schedules.fetch(BuildSituationsJob)
    hazards = schedules.fetch(SyncHazardRelationshipsJob)

    assert_equal 15.minutes, build.fetch(:every)
    assert_operator build.fetch(:offset), :>, hazards.fetch(:offset)
  end
end
