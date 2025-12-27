# frozen_string_literal: true

# Phase 5: Security Headers for FDA 21 CFR Part 11 Compliance
# Adds security headers to all responses

Rails.application.config.middleware.insert_before 0, Rack::Headers do
  # HSTS - Force HTTPS for 1 year
  set "Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload"

  # Prevent clickjacking
  set "X-Frame-Options", "DENY"

  # Prevent MIME type sniffing
  set "X-Content-Type-Options", "nosniff"

  # XSS protection (legacy browsers)
  set "X-XSS-Protection", "1; mode=block"

  # Control referrer information
  set "Referrer-Policy", "strict-origin-when-cross-origin"

  # Restrict browser features
  set "Permissions-Policy", "geolocation=(self), microphone=(), camera=(), payment=(self)"
end if defined?(Rack::Headers)

# Fallback for production if Rack::Headers not available
Rails.application.config.action_dispatch.default_headers.merge!(
  "X-Frame-Options" => "DENY",
  "X-Content-Type-Options" => "nosniff",
  "X-XSS-Protection" => "1; mode=block",
  "Referrer-Policy" => "strict-origin-when-cross-origin"
)

# Content Security Policy
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :data
  policy.img_src     :self, :data, :blob
  policy.object_src  :none
  policy.script_src  :self, :unsafe_inline, "https://js.stripe.com"
  policy.style_src   :self, :unsafe_inline
  policy.frame_src   "https://js.stripe.com", "https://hooks.stripe.com"
  policy.connect_src :self, "https://api.stripe.com", "wss://pharmatransport.io", "wss://localhost:*"

  # FDA compliance: report violations
  policy.report_uri "/csp-violation-report" if Rails.env.production?
end

Rails.application.config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
Rails.application.config.content_security_policy_nonce_directives = %w[script-src]
