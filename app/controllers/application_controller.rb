class ApplicationController < ActionController::Base
  # No authentication needed for demos
  # Phase 6-8: Public FDA/Pharma endpoints
  
  protect_from_forgery with: :exception
  
  def health
    render plain: "🚚 PHARMA TRANSPORT v8.0 - Phase 6+7+8 LIVE\n✅ GPS WebSockets + FDA Compliance", status: 200
  end
end
