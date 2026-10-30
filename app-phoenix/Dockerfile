ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.5
ARG DEBIAN_VERSION=bookworm-20260518-slim

FROM node:22-bookworm-slim AS node

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS builder

RUN apt-get update -y && apt-get install -y build-essential git ca-certificates && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

WORKDIR /app
ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force && mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY rel rel
COPY assets assets
RUN cd assets && npm ci --omit=dev
RUN mix compile

# Build CSS/JS bundles (Tailwind v4 + DaisyUI + esbuild + MapLibre) and
# digest static assets. esbuild_elixir/tailwind_elixir download their
# own native binaries on first install. Node installs the PMTiles style packages.
RUN mix assets.setup && mix assets.deploy

COPY config/runtime.exs config/

RUN mix release

FROM debian:bookworm-20260518-slim AS runner

# docker-ce-cli + docker-compose-plugin from Docker's apt repo: Debian's
# docker.io ships CLI 20.10 without the compose v2 plugin, which breaks every
# `docker compose` call the control plane makes (and pulls in the full daemon).
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 locales ca-certificates \
      osmium-tool curl gnupg util-linux && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin && \
    apt-get purge -y gnupg && apt-get autoremove -y && \
    apt-get clean && rm -f /var/lib/apt/lists/*_* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

# Git SHA of the build, surfaced by Atlas.Version (UI footer, /api/v1/version).
# CI passes --build-arg APP_REVISION=$GITHUB_SHA; local builds leave it empty.
ARG APP_REVISION=""
ENV APP_REVISION=${APP_REVISION}

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PORT=4000 \
    PHX_HOST=localhost \
    DATABASE_PATH=/data/atlas.sqlite3

WORKDIR /app
RUN mkdir -p /data && chown nobody:nogroup /data

COPY --from=builder --chown=nobody:nogroup /app/_build/prod/rel/atlas ./

# Starts as root only long enough to take ownership of the bind-mounted data
# dirs, then drops to PUID:PGID (default 65534:65534, i.e. the previous
# `nobody`) via setpriv. Override `user:` in compose to skip that entirely —
# the entrypoint then just verifies the dirs are writable and reports clearly
# if they are not, instead of looping on "Permission denied".
#
# NOTE: `docker compose exec app <cmd>` bypasses this ENTRYPOINT and therefore
# runs as root. Prefer `docker compose exec -u 65534:65534 app …` (or your
# PUID:PGID) for anything that writes to /data, so it does not leave
# root-owned files the app cannot rewrite until the next restart.
EXPOSE 4000
ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["/app/bin/server"]
