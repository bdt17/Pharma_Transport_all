require "test_helper"

class AuditEventsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get audit_events_index_url
    assert_response :success
  end
end
