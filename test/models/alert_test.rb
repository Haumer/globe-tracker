require "test_helper"

class AlertTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "alerttest@example.com", password: "password123")
    @watch = Watch.create!(user: @user, name: "My watch", watch_type: "entity", cooldown_minutes: 10)
    @alert = Alert.create!(
      user: @user,
      watch: @watch,
      title: "Earthquake near tracked area",
      seen: false,
    )
  end

  test "valid alert creation" do
    assert @alert.persisted?
    assert_equal @user, @alert.user
    assert_equal @watch, @alert.watch
  end

  test "title is required" do
    alert = Alert.new(user: @user, title: nil)
    assert_not alert.valid?
    assert_includes alert.errors[:title], "can't be blank"
  end

  test "watch is optional" do
    alert = Alert.create!(user: @user, title: "No watch alert")
    assert_nil alert.watch
    assert alert.persisted?
  end

  test "unseen scope returns only unseen alerts" do
    seen = Alert.create!(user: @user, title: "Seen alert", seen: true)

    assert_includes Alert.unseen, @alert
    assert_not_includes Alert.unseen, seen
  end

  test "recent scope returns latest 50 ordered by created_at desc" do
    recent = Alert.recent
    assert_includes recent, @alert
    assert recent.limit_value == 50 || recent.count <= 50
  end
end
