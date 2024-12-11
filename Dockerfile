# https://hub.docker.com/r/hexpm/elixir
ARG ELIXIR_VERSION=1.17.3
ARG ERLANG_VERSION=27.2

# https://hub.docker.com/_/node
ARG NODE_VERSION=20.16.0

# https://hub.docker.com/_/debian
ARG DEBIAN_RELEASE=bookworm
ARG DEBIAN_VERSION=${DEBIAN_RELEASE}-20241202

FROM hexpm/elixir:$ELIXIR_VERSION-erlang-$ERLANG_VERSION-debian-$DEBIAN_VERSION AS elixir-builder

ENV LANG=C.UTF-8 \
  MIX_ENV=prod

RUN apt-get update --allow-releaseinfo-change && \
  apt-get install -y --no-install-recommends ca-certificates curl git gnupg \
    build-essential make cmake gcc g++ libgomp1

RUN mix local.hex --force && \
  mix local.rebar --force

WORKDIR /app

COPY mix.exs mix.exs
COPY mix.lock mix.lock

RUN mix do deps.get --only prod

COPY config/config.exs config/
COPY config/prod.exs config/

RUN <<EOT
mix deps.compile
mix eval "Application.ensure_all_started(:tzdata); Tzdata.DataBuilder.load_and_save_table()"
EOT

FROM node:${NODE_VERSION}-${DEBIAN_RELEASE} AS assets-builder

WORKDIR /app

COPY assets assets
COPY --from=elixir-builder /app/deps deps
RUN npm ci --prefix assets

FROM elixir-builder AS app-builder
ARG SENTRY_DSN=""
COPY lib lib
COPY priv priv
COPY --from=assets-builder /app/assets assets

RUN mix assets.deploy
RUN mix phx.digest
RUN mix compile

COPY config/runtime.exs config
COPY rel rel

RUN mix release

FROM debian:${DEBIAN_VERSION}-slim

RUN apt-get update --allow-releaseinfo-change && \
  apt-get upgrade -y --no-install-recommends && \
  apt-get install -y --no-install-recommends \
    ca-certificates curl dumb-init jq libgomp1 && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN chown nobody /app

EXPOSE 4000 4369 54965
ENV MIX_ENV=prod TERM=xterm LANG="C.UTF-8" PORT=4000

COPY --from=app-builder --chown=nobody:root /app/_build/prod/rel/ride_along .

# Ensure SSL support is enabled
RUN env SECRET_KEY_BASE=fake ORS_BASE_URL=fake \
  sh -c ' \
     /app/bin/ride_along eval ":crypto.supports()" && \
     /app/bin/ride_along eval ":ok = :public_key.cacerts_load" && \
     /app/bin/ride_along eval "%{} = RideAlong.EtaCalculator.Model.read_model()"'

USER nobody

HEALTHCHECK CMD ["/app/bin/ride_along", "rpc", "true = (RideAlong.Adept.all_trips_count() > 0)"]
ENTRYPOINT ["/usr/bin/dumb-init", "/app/bin/ride_along"]
CMD ["start"]
