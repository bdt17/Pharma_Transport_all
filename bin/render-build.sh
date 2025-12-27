#!/usr/bin/env bash
# exit on error
set -o errexit

# Install production gems only
bundle config set --local without 'development test'
bundle install

# Precompile assets for production and clean old ones
bundle exec rails assets:precompile
bundle exec rails assets:clean

# Run database migrations (safe for idempotent schema)
bundle exec rails db:migrate
