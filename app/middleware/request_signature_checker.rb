# frozen_string_literal: true

# =============================================================================
# RequestSignatureChecker Middleware
# =============================================================================
# Verifies HMAC-SHA256 signatures for internal API requests
# FDA 21 CFR Part 11 Compliant - Ensures request integrity
#
# Usage:
#   # In config/application.rb:
#   config.middleware.use RequestSignatureChecker
#
# Request Headers Required:
#   X-Request-Signature: HMAC-SHA256 signature
#   X-Request-Timestamp: Unix timestamp (must be within 5 minutes)
#   X-Request-Nonce: Unique nonce to prevent replay attacks
# =============================================================================

class RequestSignatureChecker
  SIGNATURE_HEADER = "HTTP_X_REQUEST_SIGNATURE"
  TIMESTAMP_HEADER = "HTTP_X_REQUEST_TIMESTAMP"
  NONCE_HEADER = "HTTP_X_REQUEST_NONCE"
  MAX_CLOCK_SKEW = 300 # 5 minutes
  NONCE_TTL = 600 # 10 minutes

  def initialize(app, options = {})
    @app = app
    @secret_key = options[:secret_key] || ENV.fetch("INTERNAL_API_SECRET", nil)
    @protected_paths = options[:protected_paths] || ["/api/internal"]
    @skip_paths = options[:skip_paths] || ["/health", "/stripe/webhooks"]
    @nonce_store = {}
    @nonce_mutex = Mutex.new
  end

  def call(env)
    request = Rack::Request.new(env)

    # Skip non-protected paths
    return @app.call(env) if skip_verification?(request.path)

    # Skip if no secret configured (development mode)
    return @app.call(env) if @secret_key.blank?

    # Only check protected paths
    return @app.call(env) unless protected_path?(request.path)

    # Verify signature
    verification_result = verify_request(env, request)

    unless verification_result[:valid]
      return signature_error_response(verification_result[:error])
    end

    # Add verification info to request
    env["pharma.signature_verified"] = true
    env["pharma.signature_timestamp"] = verification_result[:timestamp]

    @app.call(env)
  end

  private

  # =========================================================================
  # PATH CHECKING
  # =========================================================================

  def skip_verification?(path)
    @skip_paths.any? { |skip| path.start_with?(skip) }
  end

  def protected_path?(path)
    @protected_paths.any? { |protected| path.start_with?(protected) }
  end

  # =========================================================================
  # SIGNATURE VERIFICATION
  # =========================================================================

  def verify_request(env, request)
    signature = env[SIGNATURE_HEADER]
    timestamp = env[TIMESTAMP_HEADER]
    nonce = env[NONCE_HEADER]

    # Check required headers
    return { valid: false, error: "missing_signature" } if signature.blank?
    return { valid: false, error: "missing_timestamp" } if timestamp.blank?
    return { valid: false, error: "missing_nonce" } if nonce.blank?

    # Verify timestamp (prevent replay attacks)
    timestamp_int = timestamp.to_i
    current_time = Time.now.to_i

    if (current_time - timestamp_int).abs > MAX_CLOCK_SKEW
      return { valid: false, error: "timestamp_expired" }
    end

    # Check nonce (prevent replay attacks)
    if nonce_used?(nonce)
      return { valid: false, error: "nonce_reused" }
    end

    # Build signature payload
    payload = build_signature_payload(request, timestamp, nonce)

    # Verify HMAC signature
    expected_signature = compute_signature(payload)

    unless secure_compare(signature, expected_signature)
      return { valid: false, error: "invalid_signature" }
    end

    # Store nonce to prevent reuse
    store_nonce(nonce)

    { valid: true, timestamp: timestamp_int }
  end

  def build_signature_payload(request, timestamp, nonce)
    [
      request.request_method,
      request.path,
      request.query_string,
      timestamp,
      nonce,
      request.body.read.tap { request.body.rewind }
    ].join("\n")
  end

  def compute_signature(payload)
    OpenSSL::HMAC.hexdigest("SHA256", @secret_key, payload)
  end

  def secure_compare(a, b)
    return false unless a.bytesize == b.bytesize
    a.bytes.zip(b.bytes).reduce(0) { |acc, (x, y)| acc | (x ^ y) }.zero?
  end

  # =========================================================================
  # NONCE MANAGEMENT
  # =========================================================================

  def nonce_used?(nonce)
    @nonce_mutex.synchronize do
      cleanup_expired_nonces
      @nonce_store.key?(nonce)
    end
  end

  def store_nonce(nonce)
    @nonce_mutex.synchronize do
      @nonce_store[nonce] = Time.now.to_i
    end
  end

  def cleanup_expired_nonces
    cutoff = Time.now.to_i - NONCE_TTL
    @nonce_store.delete_if { |_, timestamp| timestamp < cutoff }
  end

  # =========================================================================
  # ERROR RESPONSES
  # =========================================================================

  def signature_error_response(error_type)
    error_messages = {
      "missing_signature" => "X-Request-Signature header required",
      "missing_timestamp" => "X-Request-Timestamp header required",
      "missing_nonce" => "X-Request-Nonce header required",
      "timestamp_expired" => "Request timestamp expired (max #{MAX_CLOCK_SKEW}s)",
      "nonce_reused" => "Request nonce already used",
      "invalid_signature" => "Invalid request signature"
    }

    body = {
      error: "signature_verification_failed",
      code: error_type,
      message: error_messages[error_type] || "Signature verification failed"
    }.to_json

    [
      401,
      {
        "Content-Type" => "application/json",
        "X-Signature-Error" => error_type
      },
      [body]
    ]
  end
end
