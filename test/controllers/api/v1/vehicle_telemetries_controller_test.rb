require "test_helper"

class Api::V1::VehicleTelemetriesControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get api_v1_vehicle_telemetries_create_url
    assert_response :success
  end
end
