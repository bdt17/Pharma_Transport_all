#!/usr/bin/env bash
bundle install --without development test
mkdir -p public
cp *.html public/ 2>/dev/null || true
