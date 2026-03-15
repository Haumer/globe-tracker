require "test_helper"

class Api::TrainsControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/trains returns json" do
    original_method = HafasTrainService.method(:fetch)
    HafasTrainService.define_singleton_method(:fetch) { |**_args| [] }
    get "/api/trains"
    assert_response :success
    data = JSON.parse(response.body)
    assert_kind_of Array, data
  ensure
    HafasTrainService.define_singleton_method(:fetch, original_method)
  end
end
