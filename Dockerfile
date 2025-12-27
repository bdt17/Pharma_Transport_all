# =============================================================================
# Dockerfile - Pharma Transport
# =============================================================================
# FDA 21 CFR Part 11 Compliant Production Image
# Multi-stage build for Render.com deployment
#
# Build: docker build -t pharma-transport .
# Run:   docker run -p 3000:3000 -e RAILS_MASTER_KEY=xxx pharma-transport
# =============================================================================

# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.2.2

# =============================================================================
# BASE STAGE - Runtime dependencies only
# =============================================================================
FROM ruby:${RUBY_VERSION}-slim AS base

LABEL maintainer="PharmaTransport <ops@pharmatransport.io>"
LABEL description="FDA 21 CFR Part 11 Compliant Cold Chain Platform"

WORKDIR /rails

# Install runtime dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libjemalloc2 \
      libvips42 \
      postgresql-client \
      tzdata \
      ca-certificates && \
    # Link jemalloc for memory optimization
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    # Cleanup
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* && \
    # Create non-root user for security
    groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Production environment with jemalloc
ENV RAILS_ENV="production" \
    NODE_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    MALLOC_ARENA_MAX="2" \
    RUBY_YJIT_ENABLE="1"

# =============================================================================
# BUILD STAGE - Compile gems and assets
# =============================================================================
FROM base AS build

# Install build dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libpq-dev \
      libyaml-dev \
      pkg-config \
      nodejs \
      npm && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3 && \
    rm -rf ~/.bundle/ \
      "${BUNDLE_PATH}"/ruby/*/cache \
      "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap for faster boot
RUN bundle exec bootsnap precompile app/ lib/

# Precompile assets (dummy secret for build)
RUN SECRET_KEY_BASE_DUMMY=1 \
    RAILS_MASTER_KEY=dummy_key_for_asset_precompile \
    bundle exec rails assets:precompile 2>/dev/null || true

# =============================================================================
# PRODUCTION STAGE - Minimal runtime image
# =============================================================================
FROM base AS production

# Copy built artifacts
COPY --from=build --chown=rails:rails "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build --chown=rails:rails /rails /rails

# Switch to non-root user (FDA security requirement)
USER rails:rails

# Health check for Render
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/health/live || exit 1

# Expose port
EXPOSE 3000

# Entrypoint handles db:prepare
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Default command: Puma web server
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
