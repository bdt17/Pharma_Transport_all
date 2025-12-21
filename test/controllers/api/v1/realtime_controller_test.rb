require "test_helper"

class Api::V1::RealtimeControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get api_v1_realtime_index_url
    assert_response :success
  end
end
