# Lightweight image with the Ookla Speedtest CLI.
# Intended as a long-running sidecar that the app execs into:
#   docker exec baudflow-speedtest speedtest --format=json
#
# Building:
#   docker build -t baudflow-speedtest docker/speedtest

FROM debian:bookworm-slim

ARG TARGETARCH
ARG SPEEDTEST_VERSION=1.2.0

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && case "$TARGETARCH" in \
         amd64) ARCH=x86_64 ;; \
         arm64) ARCH=aarch64 ;; \
         *) ARCH=x86_64 ;; \
       esac \
    && curl -sL "https://install.speedtest.net/app/cli/ookla-speedtest-${SPEEDTEST_VERSION}-linux-${ARCH}.tgz" \
       | tar xz -C /usr/local/bin speedtest \
    && chmod +x /usr/local/bin/speedtest

# Keep container alive so the app can `docker exec` into it.
CMD ["sleep", "infinity"]
