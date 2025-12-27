#!/usr/bin/env bash
set -e

bundle config set --local without 'development test'
bundle install

# Rails 8: Use migrate/setup instead of prepare (bug workaround)
bin/rails db:migrate
