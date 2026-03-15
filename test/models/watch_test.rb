require "test_helper"

class WatchTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "watchtest@example.com", password: "password123")
    @watch = Watch.create!(
      user: @user,
      name: "Track earthquakes",
      watch_type: "event",
      cooldown_minutes: 15,
      active: true,
    )
  end

  test "valid watch creation" do
    assert @watch.persisted?
    assert_equal "event", @watch.watch_type
  end

  test "name is required" do
    watch = Watch.new(user: @user, watch_type: "entity", cooldown_minutes: 10)
    assert_not watch.valid?
    assert_includes watch.errors[:name], "can't be blank"
  end

  test "watch_type must be entity, area, or event" do
    watch = Watch.new(user: @user, name: "Test", watch_type: "invalid", cooldown_minutes: 10)
    assert_not watch.valid?
    assert watch.errors[:watch_type].any?
  end

  test "cooldown_minutes must be positive" do
    watch = Watch.new(user: @user, name: "Test", watch_type: "entity", cooldown_minutes: 0)
    assert_not watch.valid?
    assert watch.errors[:cooldown_minutes].any?
  end

  test "active scope returns only active watches" do
    inactive = Watch.create!(user: @user, name: "Inactive", watch_type: "area", cooldown_minutes: 10, active: false)

    assert_includes Watch.active, @watch
    assert_not_includes Watch.active, inactive
  end

  test "cooled_down? returns true when never triggered" do
    assert @watch.cooled_down?
  end

  test "cooled_down? returns false when recently triggered" do
    @watch.update!(last_triggered_at: 5.minutes.ago)
    assert_not @watch.cooled_down?
  end

  test "cooled_down? returns true when cooldown elapsed" do
    @watch.update!(last_triggered_at: 20.minutes.ago)
    assert @watch.cooled_down?
  end
end
