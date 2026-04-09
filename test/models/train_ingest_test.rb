require "test_helper"

class TrainIngestTest < ActiveSupport::TestCase
  setup do
    @ingest = TrainIngest.create!(
      source_key: "hafas_de",
      source_name: "HAFAS Germany",
      status: "fetched",
      fetched_at: Time.current
    )
  end

  test "valid creation" do
    assert @ingest.persisted?
  end

  test "source_key is required" do
    r = TrainIngest.new(source_name: "Test", status: "fetched", fetched_at: Time.current)
    assert_not r.valid?
    assert_includes r.errors[:source_key], "can't be blank"
  end

  test "source_name is required" do
    r = TrainIngest.new(source_key: "test", status: "fetched", fetched_at: Time.current)
    assert_not r.valid?
    assert_includes r.errors[:source_name], "can't be blank"
  end

  test "fetched_at is required" do
    r = TrainIngest.new(source_key: "test", source_name: "Test", status: "fetched")
    assert_not r.valid?
    assert_includes r.errors[:fetched_at], "can't be blank"
  end

  test "status must be valid" do
    r = TrainIngest.new(source_key: "test", source_name: "Test", status: "invalid", fetched_at: Time.current)
    assert_not r.valid?
    assert r.errors[:status].any?
  end

  test "all valid statuses accepted" do
    %w[fetched failed].each do |s|
      r = TrainIngest.new(source_key: "test", source_name: "Test", status: s, fetched_at: Time.current)
      assert r.valid?, "status '#{s}' should be valid"
    end
  end

  test "has_many train_observations" do
    assert_respond_to @ingest, :train_observations
  end
end
