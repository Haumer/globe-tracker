require "application_system_test_case"

class AreaWorkspacesFlowTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  setup do
    Warden.test_mode!
  end

  teardown do
    Warden.test_reset!
  end

  test "area page opens the globe with the saved regional scope" do
    user = User.create!(email: "area-flow@example.com", password: "password123")
    area = user.area_workspaces.create!(
      name: "Gulf States",
      scope_type: "preset_region",
      profile: "maritime",
      bounds: { lamin: 21.0, lamax: 32.0, lomin: 44.0, lomax: 57.0 },
      scope_metadata: {
        region_key: "gulf-states",
        region_name: "Gulf States",
        camera: { lat: 27.0, lng: 50.0, height: 1_500_000, heading: 0, pitch: -0.85 },
      },
      default_layers: ["ships", "chokepoints", "news"]
    )

    login_as user, scope: :user

    visit area_path(area)
    assert_text "Gulf States"
    click_link "Open On Globe"

    assert_current_path root_path, ignore_query: true
    assert_selector "#globe-container", wait: 10

    fragment = URI.parse(page.current_url).fragment
    assert_includes fragment, "r:gulf-states"
    assert_includes fragment, "l:sh,cp,nw"
  end

  test "region deeplink can be tracked into an area workspace" do
    user = User.create!(email: "area-track@example.com", password: "password123")
    login_as user, scope: :user

    visit "/#25.0000,52.0000,3000000,0.000,-1.120;r:gulf-states"

    assert_selector "#region-indicator .region-badge", text: "GULF STATES", wait: 30
    assert_selector "#region-indicator .region-track-btn", text: "Track Area", wait: 30

    assert_difference("AreaWorkspace.count", 1) do
      click_button "Track Area"
      assert_current_path(/\/areas\/\d+/, wait: 30)
    end

    assert_text "Gulf States"
    assert_text "Preset Region"
    assert_selector "a", text: "Open On Globe"
  end
end
