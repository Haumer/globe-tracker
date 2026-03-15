require "test_helper"

class PipelineTest < ActiveSupport::TestCase
  test "creation with basic fields" do
    pipeline = Pipeline.create!(
      pipeline_id: "pipe-001",
      name: "Nord Stream 1",
      pipeline_type: "gas",
      status: "active",
      length_km: 1224.0,
      country: "DE"
    )
    assert pipeline.persisted?
    assert_equal "Nord Stream 1", pipeline.name
  end

  test "coordinates stored as JSONB" do
    coords = [[10.0, 54.0], [11.0, 54.5], [12.0, 55.0]]
    pipeline = Pipeline.create!(
      pipeline_id: "pipe-002",
      name: "Test Pipeline",
      coordinates: coords
    )
    pipeline.reload
    assert_equal coords, pipeline.coordinates
  end

  test "unique constraint on pipeline_id" do
    Pipeline.create!(pipeline_id: "pipe-unique", name: "First")
    assert_raises(ActiveRecord::RecordNotUnique) do
      Pipeline.create!(pipeline_id: "pipe-unique", name: "Duplicate")
    end
  end

  test "creation without coordinates" do
    pipeline = Pipeline.create!(pipeline_id: "pipe-003", name: "No coords")
    assert_nil pipeline.coordinates
  end
end
