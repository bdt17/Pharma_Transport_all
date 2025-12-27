#!/usr/bin/env bash
bundle config set without 'development test'
bundle install
mkdir -p public
cp *.html public/ 2>/dev/null || true
