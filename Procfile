# =============================================================================
# Procfile - Pharma Transport
# =============================================================================
# FDA 21 CFR Part 11 Compliant Process Definitions
# For Render.com (uses render.yaml for service definitions)
#
# Local dev: foreman start
# Production: Render uses Docker commands from render.yaml
# =============================================================================

# Web server - Puma
web: bundle exec puma -C config/puma.rb

# Background jobs - Sidekiq
worker: bundle exec sidekiq -C config/sidekiq.yml

# Release phase - Database migrations (Render specific)
release: bundle exec rails db:migrate
