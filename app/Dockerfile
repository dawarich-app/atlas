# syntax=docker/dockerfile:1
# check=error=true

# Multi-stage build for Dawarich Atlas Rails app.
# Bump RUBY_VERSION to the current 3.4.x patch when newer releases ship.

ARG RUBY_VERSION=3.4.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        curl \
        libjemalloc2 \
        libvips \
        sqlite3 \
        libpq5 \
        && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="libjemalloc.so.2" \
    MALLOC_CONF="dirty_decay_ms:1000,narenas:2,background_thread:true"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        build-essential \
        git \
        pkg-config \
        libyaml-dev \
        libpq-dev \
        unzip \
        ca-certificates \
        && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

ARG BUN_VERSION=1.3.13
ENV BUN_INSTALL=/usr/local/bun \
    PATH=/usr/local/bun/bin:$PATH

RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" && \
    bun --version

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

COPY . .

RUN bundle exec bootsnap precompile app/ lib/

RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

RUN rm -rf node_modules

FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /data && \
    chown -R rails:rails db log storage tmp /data

VOLUME ["/data"]

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
