
protect_from_forgery with: :null_session, if: -> { request.format.json? }
after_action :cors_set_access_control_headers

def cors_set_access_control_headers
  headers['Access-Control-Allow-Origin'] = '*'
  headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
  headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
end




class ApplicationController < ActionController::Base
  # No authentication needed for demos
  # Phase 6-8: Public FDA/Pharma endpoints
  
  protect_from_forgery with: :exception
  
  def health
    render plain: "🚚 PHARMA TRANSPORT v8.0 - Phase 6+7+8 LIVE\n✅ GPS WebSockets + FDA Compliance", status: 200
  end
end
