ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.5
ARG DEBIAN_VERSION=bookworm-20260518-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS builder

RUN apt-get update -y && apt-get install -y build-essential git ca-certificates && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

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
RUN mix compile

# Build CSS/JS bundles (Tailwind v4 + DaisyUI + esbuild + MapLibre) and
# digest static assets. esbuild_elixir/tailwind_elixir download their
# own native binaries on first install — no Node runtime needed.
RUN mix assets.setup && mix assets.deploy

COPY config/runtime.exs config/

RUN mix release

FROM debian:bookworm-20260518-slim AS runner

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 locales ca-certificates \
      docker.io osmium-tool curl && \
    apt-get clean && rm -f /var/lib/apt/lists/*_* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PORT=4000 \
    PHX_HOST=localhost \
    DATABASE_PATH=/data/atlas.sqlite3

WORKDIR /app
RUN mkdir -p /data && chown nobody:nogroup /data
USER nobody:nogroup

COPY --from=builder --chown=nobody:nogroup /app/_build/prod/rel/atlas ./

EXPOSE 4000
CMD ["/app/bin/server"]
