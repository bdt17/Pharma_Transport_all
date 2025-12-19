require "test_helper"

class DriversControllerTest < ActionDispatch::IntegrationTest
  test "should get dashboard" do
    get drivers_dashboard_url
    assert_response :success
  end
end
