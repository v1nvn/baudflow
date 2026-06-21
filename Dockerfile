# ---- Build stage ----
FROM hexpm/elixir:1.20-erlang-29.0.1-debian-trixie-20260610-slim AS builder

# nodejs + npm are needed so esbuild can resolve the chart.js / date-fns imports
# from node_modules. (esbuild itself is a standalone binary, but it bundles FROM
# node_modules, which only npm can populate.)
RUN apt-get update -y && apt-get install -y build-essential git nodejs npm && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/runtime.exs config/
RUN mix deps.compile

# Build assets
# Install npm deps first (own layer) so they're cached unless package*.json changes.
# Without this, esbuild can't resolve `chart.js/auto` and the build fails - and the
# image would silently diverge from local builds.
COPY assets/package.json assets/package-lock.json assets/
RUN npm --prefix assets ci
COPY assets assets
COPY priv priv
# lib must be present before assets.deploy so the phoenix-colocated compiler can
# generate the virtual module that esbuild resolves.
COPY lib lib
RUN mix assets.setup && mix assets.deploy

# Compile and build release
RUN mix compile

# Changes to config/runtime.exs don't require a rebuild
COPY config/runtime.exs config/

# Release overlays (rel/overlays/bin/{server,migrate}) must be present for
# `mix release` to bake them into the release. Without this the CMD below
# (/app/bin/server) is missing from the image and the container fails to start.
COPY rel rel

# Build release
RUN mix release

# ---- Runtime stage ----
FROM debian:trixie-slim AS final

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Install Ookla Speedtest CLI
# NOTE: TARGETARCH gives amd64/arm64 but Ookla expects x86_64/aarch64
ARG TARGETARCH
ARG SPEEDTEST_VERSION=1.2.0
RUN case "$TARGETARCH" in \
      amd64) ARCH=x86_64 ;; \
      arm64) ARCH=aarch64 ;; \
      *) ARCH=x86_64 ;; \
    esac && \
    curl -sL "https://install.speedtest.net/app/cli/ookla-speedtest-${SPEEDTEST_VERSION}-linux-${ARCH}.tgz" \
    | tar xz -C /usr/local/bin speedtest \
    && chmod +x /usr/local/bin/speedtest

# Expose the CLI version to the running app so each measurement records it.
ENV SPEEDTEST_VERSION=${SPEEDTEST_VERSION}

WORKDIR /app
RUN mkdir -p /home/appuser && chown 1000:1000 /home/appuser
RUN chown -R 1000:1000 /app

ENV MIX_ENV=prod
ENV HOME=/home/appuser

COPY --from=builder --chown=1000:1000 /app/_build/prod/rel/baudflow ./

USER 1000:1000

CMD ["/app/bin/server"]
