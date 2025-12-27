# frozen_string_literal: true

# =============================================================================
# Stripe Configuration - Pharma Transport
# =============================================================================
# FDA 21 CFR Part 11 Compliant Billing Integration
# Live Mode Ready for Render.com Production
#
# Required Environment Variables:
#   STRIPE_SECRET_KEY       - sk_live_xxx (set in Render dashboard)
#   STRIPE_PUBLISHABLE_KEY  - pk_live_xxx (set in Render dashboard)
#   STRIPE_WEBHOOK_SECRET   - whsec_xxx (from Stripe Dashboard → Webhooks)
# =============================================================================

Rails.application.config.to_prepare do
  # API Key Configuration
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

  # API Version - Lock to prevent breaking changes
  Stripe.api_version = "2024-12-18.acacia"

  # Timeouts for production reliability
  Stripe.open_timeout = 30
  Stripe.read_timeout = 80

  # Enable telemetry for better Stripe support
  Stripe.enable_telemetry = Rails.env.production?

  # Log level (errors only in production)
  Stripe.log_level = Rails.env.production? ? Stripe::LEVEL_ERROR : Stripe::LEVEL_INFO

  # Verify configuration on boot
  if Rails.env.production?
    if ENV["STRIPE_SECRET_KEY"].blank?
      Rails.logger.warn "[Stripe] WARNING: STRIPE_SECRET_KEY not configured"
    elsif !ENV["STRIPE_SECRET_KEY"].start_with?("sk_live_")
      Rails.logger.warn "[Stripe] WARNING: Using test mode key in production"
    end

    if ENV["STRIPE_WEBHOOK_SECRET"].blank?
      Rails.logger.error "[Stripe] CRITICAL: STRIPE_WEBHOOK_SECRET not configured - webhooks will fail!"
    end
  end
end

# =============================================================================
# STRIPE PRICE IDS - Configure in Render Environment Variables
# =============================================================================
# Set these in Render dashboard or render.yaml:
#
#   STRIPE_PRICE_SMB=price_xxx        # $299/mo SMB plan
#   STRIPE_PRICE_ENTERPRISE=price_xxx # $999/mo Enterprise plan
#   STRIPE_PRICE_PFIZER=price_xxx     # Custom Pfizer plan
# =============================================================================
