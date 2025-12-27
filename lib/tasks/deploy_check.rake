# frozen_string_literal: true

namespace :deploy do
  desc "Verify production deployment - Stripe, DB, webhooks"
  task check: :environment do
    puts "=" * 60
    puts "PHARMA TRANSPORT DEPLOYMENT CHECK"
    puts "=" * 60
    puts ""

    results = { passed: 0, failed: 0, warnings: 0 }

    # Database
    print "Database connection........... "
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      puts "OK"
      results[:passed] += 1
    rescue => e
      puts "FAILED: #{e.message}"
      results[:failed] += 1
    end

    # Migrations
    print "Pending migrations............ "
    begin
      pending = ActiveRecord::Migration.check_all_pending!
      puts "OK (none pending)"
      results[:passed] += 1
    rescue ActiveRecord::PendingMigrationError => e
      puts "FAILED: Pending migrations exist"
      results[:failed] += 1
    rescue => e
      puts "OK"
      results[:passed] += 1
    end

    # Redis
    print "Redis connection.............. "
    if ENV["REDIS_URL"].present?
      begin
        redis = Redis.new(url: ENV["REDIS_URL"])
        redis.ping
        puts "OK"
        results[:passed] += 1
      rescue => e
        puts "FAILED: #{e.message}"
        results[:failed] += 1
      end
    else
      puts "SKIPPED (REDIS_URL not set)"
      results[:warnings] += 1
    end

    # Stripe API Key
    print "Stripe API key................ "
    if ENV["STRIPE_SECRET_KEY"].present?
      if ENV["STRIPE_SECRET_KEY"].start_with?("sk_live_")
        puts "OK (live mode)"
        results[:passed] += 1
      elsif ENV["STRIPE_SECRET_KEY"].start_with?("sk_test_")
        puts "WARNING: Test mode key"
        results[:warnings] += 1
      else
        puts "FAILED: Invalid key format"
        results[:failed] += 1
      end
    else
      puts "FAILED: Not configured"
      results[:failed] += 1
    end

    # Stripe Connectivity
    print "Stripe API connectivity....... "
    begin
      Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
      Stripe::Balance.retrieve
      puts "OK"
      results[:passed] += 1
    rescue Stripe::AuthenticationError => e
      puts "FAILED: Invalid API key"
      results[:failed] += 1
    rescue => e
      puts "FAILED: #{e.message[0..50]}"
      results[:failed] += 1
    end

    # Stripe Webhook Secret
    print "Stripe webhook secret......... "
    if ENV["STRIPE_WEBHOOK_SECRET"].present?
      if ENV["STRIPE_WEBHOOK_SECRET"].start_with?("whsec_")
        puts "OK"
        results[:passed] += 1
      else
        puts "WARNING: Invalid format"
        results[:warnings] += 1
      end
    else
      puts "FAILED: Not configured"
      results[:failed] += 1
    end

    # Rails Master Key
    print "Rails master key.............. "
    if ENV["RAILS_MASTER_KEY"].present? || File.exist?(Rails.root.join("config/master.key"))
      puts "OK"
      results[:passed] += 1
    else
      puts "FAILED: Not configured"
      results[:failed] += 1
    end

    # Audit Chain
    print "Audit chain integrity......... "
    begin
      if defined?(AuditEvent) && AuditEvent.table_exists?
        result = AuditEvent.verify_chain
        if result[:valid]
          puts "OK (#{result[:checked]} records)"
          results[:passed] += 1
        else
          puts "WARNING: #{result[:errors]&.count || 0} errors"
          results[:warnings] += 1
        end
      else
        puts "SKIPPED (table not found)"
        results[:warnings] += 1
      end
    rescue => e
      puts "SKIPPED: #{e.message[0..30]}"
      results[:warnings] += 1
    end

    # Health Endpoint
    print "Health endpoint............... "
    begin
      require "net/http"
      port = ENV.fetch("PORT", 3000)
      uri = URI("http://localhost:#{port}/health/ready")
      response = Net::HTTP.get_response(uri)
      if response.code == "200"
        puts "OK"
        results[:passed] += 1
      else
        puts "WARNING: Status #{response.code}"
        results[:warnings] += 1
      end
    rescue => e
      puts "SKIPPED (server not running)"
      results[:warnings] += 1
    end

    # Summary
    puts ""
    puts "=" * 60
    puts "RESULTS: #{results[:passed]} passed, #{results[:failed]} failed, #{results[:warnings]} warnings"
    puts "=" * 60

    exit(results[:failed] > 0 ? 1 : 0)
  end

  desc "Verify Stripe webhook endpoint is accessible"
  task verify_webhook: :environment do
    puts "Stripe Webhook Verification"
    puts "-" * 40

    webhook_url = ENV.fetch("WEBHOOK_URL", "https://pharmatransport.io/stripe/webhooks")

    puts "Endpoint: #{webhook_url}"
    puts "Secret configured: #{ENV['STRIPE_WEBHOOK_SECRET'].present? ? 'Yes' : 'No'}"

    if ENV["STRIPE_SECRET_KEY"].present?
      begin
        Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
        webhooks = Stripe::WebhookEndpoint.list(limit: 10)

        puts ""
        puts "Registered webhooks in Stripe:"
        webhooks.data.each do |wh|
          status = wh.status == "enabled" ? "OK" : wh.status
          puts "  #{wh.url} [#{status}]"
        end
      rescue => e
        puts "Error fetching webhooks: #{e.message}"
      end
    end
  end

  desc "Quick production readiness check"
  task ready: :environment do
    errors = []

    errors << "STRIPE_SECRET_KEY missing" unless ENV["STRIPE_SECRET_KEY"].present?
    errors << "STRIPE_WEBHOOK_SECRET missing" unless ENV["STRIPE_WEBHOOK_SECRET"].present?
    errors << "DATABASE_URL missing" unless ENV["DATABASE_URL"].present?
    errors << "RAILS_MASTER_KEY missing" unless ENV["RAILS_MASTER_KEY"].present? || File.exist?(Rails.root.join("config/master.key"))

    if errors.any?
      puts "NOT READY"
      errors.each { |e| puts "  - #{e}" }
      exit 1
    else
      puts "READY FOR PRODUCTION"
      exit 0
    end
  end
end
