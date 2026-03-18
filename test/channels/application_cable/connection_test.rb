require "test_helper"

module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    test "connects anonymously without a user" do
      connect
      assert_nil connection.current_user
    end

    test "connects with a signed-in user via warden" do
      user = User.create!(
        email: "cable-test@example.com",
        password: "password123"
      )

      connect env: { "warden" => OpenStruct.new(user: user) }
      assert_equal user, connection.current_user

      user.destroy!
    end
  end
end
