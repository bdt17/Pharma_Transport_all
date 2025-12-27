# Production Render deployment - NO DEMO MODE
environment ENV.fetch("RAILS_ENV", "production")

workers ENV.fetch("WEB_CONCURRENCY", 2)
threads 5, 5
port ENV.fetch("PORT", 10000)
bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 10000)}"

preload_app!
worker_timeout 60
force_shutdown_after 30

def safe_logger
  Rails.logger || Logger.new($stdout)
end

before_fork do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end

on_worker_boot do
  safe_logger.info "[Puma] Worker #{Process.pid} booted"
end

on_worker_shutdown do
  safe_logger.info "[Puma] Worker #{Process.pid} shutting down"
end

on_restart do
  safe_logger.info "[Puma] Master process restarting"
end

plugin :tmp_restart
