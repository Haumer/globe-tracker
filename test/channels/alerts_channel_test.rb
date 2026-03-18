require "test_helper"

class AlertsChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = User.create!(
      email: "test-channel@example.com",
      password: "password123"
    )
  end

  teardown do
    @user.destroy!
  end

  test "subscribes for authenticated user" do
    stub_connection current_user: @user
    subscribe
    assert subscription.confirmed?
    assert_has_stream_for @user
  end

  test "rejects anonymous connection" do
    stub_connection current_user: nil
    subscribe
    assert subscription.rejected?
  end

  test "broadcasts new alert to specific user" do
    watch = @user.watches.create!(
      name: "Test Watch",
      watch_type: "entity",
      conditions: {}
    )
    alert = @user.alerts.create!(
      title: "Tracked aircraft detected",
      entity_type: "flight",
      entity_id: "ABC123",
      lat: 51.5,
      lng: -0.1,
      details: { callsign: "BAW123" },
      watch: watch
    )

    assert_broadcast_on(@user, {
      type: "new_alert",
      alert: {
        id: alert.id,
        title: "Tracked aircraft detected",
        entity_type: "flight",
        entity_id: "ABC123",
        lat: 51.5,
        lng: -0.1,
        details: { callsign: "BAW123" },
        watch_name: "Test Watch",
        created_at: alert.created_at.iso8601,
      },
    }) do
      AlertsChannel.notify(@user, alert)
    end
  end

  test "broadcasts badge update" do
    # Create some unseen alerts
    watch = @user.watches.create!(name: "W", watch_type: "entity", conditions: {})
    2.times do |i|
      @user.alerts.create!(
        title: "Alert #{i}",
        entity_type: "flight",
        entity_id: "F#{i}",
        watch: watch,
        seen: false
      )
    end

    assert_broadcast_on(@user, {
      type: "badge_update",
      unseen_count: 2,
    }) do
      AlertsChannel.update_badge(@user)
    end
  end
end
