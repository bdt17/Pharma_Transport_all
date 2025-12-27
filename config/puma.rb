# frozen_string_literal: true

# =============================================================================
# Puma Configuration - Pharma Transport
# =============================================================================
# FDA 21 CFR Part 11 Compliant Web Server
# Optimized for Render.com deployment
#
# Render Standard: 1GB RAM, 1 CPU
# Recommended: WEB_CONCURRENCY=2, RAILS_MAX_THREADS=5
# =============================================================================

# Thread pool configuration
# Minimum and maximum threads per worker
max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }.to_i
threads min_threads_count, max_threads_count

# Worker processes (clustered mode)
# Each worker uses ~150-200MB RAM
# Render Standard (1GB): Use 2 workers
# Render Pro (2GB): Use 4 workers
worker_count = ENV.fetch("WEB_CONCURRENCY", 2).to_i
workers worker_count if worker_count > 1

# Bind to PORT (Render provides this)
port ENV.fetch("PORT", 3000)

# Environment
environment ENV.fetch("RAILS_ENV", "development")

# =============================================================================
# PRODUCTION OPTIMIZATIONS
# =============================================================================

if ENV.fetch("RAILS_ENV", "development") == "production"
  # Preload application for Copy-on-Write memory savings
  preload_app!

  # Fork worker timeout (longer for complex boot)
  worker_timeout 60

  # Reduce memory fragmentation
  nakayoshi_fork if respond_to?(:nakayoshi_fork)

  # Worker lifecycle hooks
  before_fork do
    # Close parent connections before forking
    ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
  end

#  on_worker_boot do
    # Re-establish connections in each worker
 #   ActiveRecord::Base.establish_connection if defined?(ActiveRecord)

on_worker_boot do
  (Rails.logger || Logger.new($stdout)).info "[Puma] Worker #{Process.pid} booted"
end

on_worker_shutdown do
  (Rails.logger || Logger.new($stdout)).info "[Puma] Worker #{Process.pid} shutting down"
end

on_restart do
  (Rails.logger || Logger.new($stdout)).info "[Puma] Master process restarting"
end



    # Reconnect to Redis
    if defined?(Redis) && ENV["REDIS_URL"]
      Redis.current.disconnect! rescue nil
    end


    # Log worker boot for FDA audit
#    Rails.logger.info "[Puma] Worker #{Process.pid} booted"
 # end

(logger = Rails.logger || Logger.new($stdout)).info "[Puma] Worker #{Process.pid} booted"
(logger = Rails.logger || Logger.new($stdout)).info "[Puma] Worker #{Process.pid} shutting down"
  


#on_worker_shutdown do
 #   Rails.logger.info "[Puma] Worker #{Process.pid} shutting down"
  #end

  # Phased restarts for zero-downtime deploys
 
# on_restart do
 #   Rails.logger.info "[Puma] Master process restarting"
  #end

on_restart do
  (Rails.logger || Logger.new($stdout)).info "[Puma] Master process restarting"
end



end

# =============================================================================
# PLUGIN CONFIGURATION
# =============================================================================

# Allow puma to be restarted by `bin/rails restart`
plugin :tmp_restart

# =============================================================================
# LOGGING
# =============================================================================

# Quiet mode - reduce startup noise
quiet if ENV["RAILS_LOG_TO_STDOUT"].present?

# Log requests (useful for debugging, disable in high-traffic production)
# set_remote_address header: "X-Forwarded-For"

# =============================================================================
# LOWLEVEL ERROR HANDLER
# =============================================================================

lowlevel_error_handler do |e, env, status|
  Rails.logger.error "[Puma] Lowlevel error: #{e.class} - #{e.message}"
  Rails.logger.error e.backtrace.first(10).join("\n") if e.backtrace

  # Return a generic error response
  [
    status,
    { "Content-Type" => "application/json" },
    [{ error: "Internal server error", request_id: env["action_dispatch.request_id"] }.to_json]
  ]
end

# =============================================================================
# RENDER.COM SPECIFIC
# =============================================================================

# Render handles SSL termination at load balancer
# Trust X-Forwarded-* headers from Render
set_remote_address header: "X-Forwarded-For"

# Graceful shutdown timeout (Render sends SIGTERM)
force_shutdown_after 30
