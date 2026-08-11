require "test_helper"

class BatchRotationTest < ActiveSupport::TestCase
  class Rotator
    include BatchRotation
  end

  setup do
    @rotator = Rotator.new
    @start = Time.utc(2026, 1, 1)
  end

  test "advances exactly one step per period" do
    idxs = 6.times.map do |i|
      @rotator.rotation_index(6, period: 5.minutes, now: @start + i * 5.minutes)
    end

    steps = idxs.each_cons(2).map { |a, b| (b - a) % 6 }
    assert_equal [1], steps.uniq
    assert_equal 6, idxs.uniq.size
  end

  test "wraps at the batch count" do
    first = @rotator.rotation_index(4, period: 5.minutes, now: @start)
    wrapped = @rotator.rotation_index(4, period: 5.minutes, now: @start + 20.minutes)

    assert_equal first, wrapped
  end

  test "holds steady inside a single period" do
    a = @rotator.rotation_index(6, period: 5.minutes, now: @start)
    b = @rotator.rotation_index(6, period: 5.minutes, now: @start + 4.minutes)

    assert_equal a, b
  end

  test "a full cycle covers every item exactly once" do
    items = (1..253).to_a

    seen = 6.times.flat_map do |i|
      @rotator.rotation_slice(items, 6, period: 5.minutes, now: @start + i * 5.minutes)
    end

    assert_equal items.sort, seen.sort
  end

  test "slices an uneven list without dropping the tail" do
    items = (1..10).to_a

    seen = 3.times.flat_map do |i|
      @rotator.rotation_slice(items, 3, period: 1.minute, now: @start + i * 1.minute)
    end

    assert_equal items.sort, seen.sort
  end

  test "does not consult the cache store" do
    # The whole point: the old counter read back nil under a NullStore and
    # pinned every poller to batch zero.
    Rails.cache.stub(:read, ->(*) { flunk("rotation read from Rails.cache") }) do
      Rails.cache.stub(:write, ->(*) { flunk("rotation wrote to Rails.cache") }) do
        assert_equal 3, @rotator.rotation_index(6, period: 5.minutes, now: @start + 15.minutes)
      end
    end
  end

  test "degenerate counts are safe" do
    assert_equal 0, @rotator.rotation_index(0, period: 5.minutes, now: @start)
    assert_equal 0, @rotator.rotation_index(1, period: 5.minutes, now: @start)
    assert_equal [], @rotator.rotation_slice([], 6, period: 5.minutes, now: @start)
    assert_equal [1, 2], @rotator.rotation_slice([1, 2], 1, period: 5.minutes, now: @start)
  end
end
