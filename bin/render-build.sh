#!/usr/bin/env bash
set -e
bundle install
bin/rails assets:precompile
bin/rails db:migrate
