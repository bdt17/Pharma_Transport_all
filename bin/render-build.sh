#!/usr/bin/env bash
set -e

bundle config set --local without 'development test'
bundle install

# Rails 8 + Render: Safe DB setup
bin/rails db:create db:migrate
