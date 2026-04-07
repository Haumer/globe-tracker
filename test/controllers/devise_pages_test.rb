require "test_helper"

class DevisePagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "sign in page renders the auth shell" do
    get new_user_session_path

    assert_response :success
    assert_includes response.body, "Welcome back"
    assert_includes response.body, "auth-shell"
    assert_includes response.body, "auth-links"
  end

  test "edit registration page renders styled account settings" do
    user = User.create!(email: "devise-edit@example.com", password: "password123")
    sign_in user

    get edit_user_registration_path

    assert_response :success
    assert_includes response.body, "Update operator profile"
    assert_includes response.body, "Danger zone"
    assert_includes response.body, "auth-danger-zone"
  end
end
