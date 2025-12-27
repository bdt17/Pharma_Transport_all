# frozen_string_literal: true

# =============================================================================
# Api::V1::StatusController
# =============================================================================
# Public health/status endpoint for uptime monitoring
# FDA 21 CFR Part 11 Compliant - Returns system health without sensitive data
#
# Endpoints:
#   GET /api/v1/status         - Basic status (public)
#   GET /api/v1/status/health  - Detailed health check
#   GET /api/v1/status/metrics - Prometheus-compatible metrics
# =============================================================================

module Api
  module V1
    class StatusController < ApplicationController
      skip_before_action :verify_authenticity_token
      skip_before_action :require_active_subscription!, if: -> { respond_to?(:require_active_subscription!, true) }

      # =========================================================================
      # GET /api/v1/status
      # Basic status endpoint for uptime monitoring
      # =========================================================================
      def index
        render json: {
          status: "ok",
          service: "pharma-transport",
          version: app_version,
          timestamp: Time.current.utc.iso8601,
          environment: Rails.env
        }
      end

      # =========================================================================
      # GET /api/v1/status/health
      # Detailed health check with component status
      # =========================================================================
      def health
        checks = {
          database: check_database,
          redis: check_redis,
          sidekiq: check_sidekiq,
          stripe: check_stripe,
          audit_chain: check_audit_chain
        }

        overall_status = checks.values.all? { |c| c[:status] == "ok" } ? "healthy" : "degraded"
        http_status = overall_status == "healthy" ? :ok : :service_unavailable

        render json: {
          status: overall_status,
          timestamp: Time.current.utc.iso8601,
          version: app_version,
          uptime_seconds: process_uptime,
          checks: checks
        }, status: http_status
      end

      # =========================================================================
      # GET /api/v1/status/metrics
      # Prometheus-compatible metrics endpoint
      # =========================================================================
      def metrics
        metrics_data = generate_prometheus_metrics
        render plain: metrics_data, content_type: "text/plain; version=0.0.4"
      end

      # =========================================================================
      # GET /api/v1/status/ready
      # Kubernetes readiness probe
      # =========================================================================
      def ready
        if database_ready? && redis_ready?
          render json: { status: "ready" }, status: :ok
        else
          render json: { status: "not_ready" }, status: :service_unavailable
        end
      end

      # =========================================================================
      # GET /api/v1/status/live
      # Kubernetes liveness probe
      # =========================================================================
      def live
        render json: { status: "alive", pid: Process.pid }, status: :ok
      end

      private

      # =========================================================================
      # COMPONENT CHECKS
      # =========================================================================

      def check_database
        start = Time.current
        ActiveRecord::Base.connection.execute("SELECT 1")
        latency = ((Time.current - start) * 1000).round(2)

        {
          status: "ok",
          latency_ms: latency,
          adapter: ActiveRecord::Base.connection.adapter_name
        }
      rescue StandardError => e
        { status: "error", error: e.message }
      end

      def check_redis
        return { status: "skipped", reason: "not_configured" } unless ENV["REDIS_URL"]

        start = Time.current
        redis = Redis.new(url: ENV["REDIS_URL"])
        redis.ping
        latency = ((Time.current - start) * 1000).round(2)

        { status: "ok", latency_ms: latency }
      rescue StandardError => e
        { status: "error", error: e.message }
      end

      def check_sidekiq
        return { status: "skipped", reason: "not_configured" } unless defined?(Sidekiq)

        stats = Sidekiq::Stats.new
        {
          status: "ok",
          processed: stats.processed,
          failed: stats.failed,
          enqueued: stats.enqueued,
          workers: stats.workers_size,
          queues: stats.queues
        }
      rescue StandardError => e
        { status: "error", error: e.message }
      end

      def check_stripe
        return { status: "skipped", reason: "not_configured" } unless ENV["STRIPE_SECRET_KEY"]

        start = Time.current
        Stripe::Balance.retrieve
        latency = ((Time.current - start) * 1000).round(2)

        {
          status: "ok",
          latency_ms: latency,
          mode: ENV["STRIPE_SECRET_KEY"]&.start_with?("sk_live") ? "live" : "test"
        }
      rescue StandardError => e
        { status: "error", error: e.message.truncate(100) }
      end

      def check_audit_chain
        result = AuditEvent.verify_chain rescue { valid: "unknown", error: "verification_failed" }

        {
          status: result[:valid] == true ? "ok" : "warning",
          valid: result[:valid],
          records_checked: result[:checked] || 0,
          last_sequence: result[:last_sequence]
        }
      rescue StandardError => e
        { status: "error", error: e.message }
      end

      # =========================================================================
      # READINESS HELPERS
      # =========================================================================

      def database_ready?
        ActiveRecord::Base.connection.execute("SELECT 1")
        true
      rescue StandardError
        false
      end

      def redis_ready?
        return true unless ENV["REDIS_URL"]
        Redis.new(url: ENV["REDIS_URL"]).ping == "PONG"
      rescue StandardError
        false
      end

      # =========================================================================
      # PROMETHEUS METRICS
      # =========================================================================

      def generate_prometheus_metrics
        metrics = []

        # Application info
        metrics << "# HELP pharma_transport_info Application info"
        metrics << "# TYPE pharma_transport_info gauge"
        metrics << "pharma_transport_info{version=\"#{app_version}\",environment=\"#{Rails.env}\"} 1"

        # Uptime
        metrics << "# HELP pharma_transport_uptime_seconds Process uptime in seconds"
        metrics << "# TYPE pharma_transport_uptime_seconds gauge"
        metrics << "pharma_transport_uptime_seconds #{process_uptime}"

        # Tenant counts
        metrics << "# HELP pharma_transport_tenants_total Total tenants by status"
        metrics << "# TYPE pharma_transport_tenants_total gauge"
        Tenant.group(:subscription_status).count.each do |status, count|
          metrics << "pharma_transport_tenants_total{status=\"#{status}\"} #{count}"
        end

        # Audit events
        metrics << "# HELP pharma_transport_audit_events_total Total audit events"
        metrics << "# TYPE pharma_transport_audit_events_total counter"
        metrics << "pharma_transport_audit_events_total #{AuditEvent.count rescue 0}"

        # MRR
        metrics << "# HELP pharma_transport_mrr_cents Monthly recurring revenue in cents"
        metrics << "# TYPE pharma_transport_mrr_cents gauge"
        mrr = Tenant.where(subscription_status: "active").sum { |t| t.monthly_price_cents || 0 } rescue 0
        metrics << "pharma_transport_mrr_cents #{mrr}"

        # Sidekiq stats
        if defined?(Sidekiq)
          stats = Sidekiq::Stats.new rescue nil
          if stats
            metrics << "# HELP sidekiq_processed_total Total processed jobs"
            metrics << "# TYPE sidekiq_processed_total counter"
            metrics << "sidekiq_processed_total #{stats.processed}"

            metrics << "# HELP sidekiq_failed_total Total failed jobs"
            metrics << "# TYPE sidekiq_failed_total counter"
            metrics << "sidekiq_failed_total #{stats.failed}"

            metrics << "# HELP sidekiq_enqueued_total Jobs currently enqueued"
            metrics << "# TYPE sidekiq_enqueued_total gauge"
            metrics << "sidekiq_enqueued_total #{stats.enqueued}"
          end
        end

        metrics.join("\n") + "\n"
      end

      # =========================================================================
      # HELPERS
      # =========================================================================

      def app_version
        ENV.fetch("APP_VERSION", "1.0.0")
      end

      def process_uptime
        (Time.current - Rails.application.config.boot_time).to_i rescue 0
      end
    end
  end
end
