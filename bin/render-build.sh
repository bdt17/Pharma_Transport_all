#!/usr/bin/env bash
set -e

echo "🚀 Installing gems..."
bundle config set without 'development test'
bundle install

echo "🔧 Precompiling assets..."
rm -rf public/assets tmp/cache
mkdir -p public/assets tmp/cache

RAILS_ENV=production bundle exec rails assets:precompile
echo "✅ Pharma dashboards ready!"
