#!/usr/bin/env bash
set -o errexit

bundle install
# Rails 8+ Propshaft - NO assets:precompile needed
bin/rails db:prepare
