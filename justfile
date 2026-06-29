# baudflow - internet speed tracking
#
# Common workflows:
#   just setup          - first-time bootstrap
#   just dev            - local dev server
#   just docker-up      - build & run in Docker
#   just docker-rebuild - rebuild after code changes
#   just check          - full CI gate before pushing (lint + tests)
#   just precommit      - fast loop gate (not CI-equivalent)

set dotenv-load

setup:
    mix setup
    npm --prefix assets ci

dev: (db-up) (speedtest-up) (migrate-dev)
    SPEEDTEST_BIN="docker exec baudflow-speedtest speedtest" mix phx.server

dev-iex: (db-up)
    iex -S mix phx.server

[private]
db-up:
    docker compose up -d db --wait

[private]
speedtest-up:
    docker compose up -d speedtest --wait

[private]
migrate-dev:
    mix ecto.migrate


docker-up:
    docker build -t baudflow:latest .
    docker compose up -d

docker-down:
    docker compose down

docker-logs:
    docker compose logs -f app

docker-rebuild:
    docker build -t baudflow:latest .
    docker compose up -d --force-recreate app

console:
    docker compose exec app /app/bin/baudflow remote

migrate:
    docker compose exec app /app/bin/baudflow eval "Baudflow.Release.migrate()"

db-reset:
    docker compose down -v
    docker compose up -d

test *ARGS:
    just with-tmp-db {{ARGS}}

[private]
with-tmp-db *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=baudflow-test-pg
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run --rm -d --name "$NAME" -e POSTGRES_PASSWORD=postgres -p 0:5432 postgres:18 >/dev/null
    trap 'docker stop "$NAME" >/dev/null 2>&1 || true' EXIT
    i=0
    until docker exec "$NAME" pg_isready -U postgres >/dev/null 2>&1; do
      i=$((i+1))
      [ "$i" -lt 60 ] || { echo "postgres did not become ready" >&2; exit 1; }
      sleep 0.2
    done
    PORT=$(docker port "$NAME" 5432/tcp | awk -F: '{print $NF}' | head -n1)
    [ -n "$PORT" ] || { echo "could not resolve postgres port" >&2; exit 1; }
    DATABASE_URL="ecto://postgres:postgres@localhost:${PORT}/baudflow_test" mix test {{ARGS}}

check:
    mix lint
    just assets-check
    just test

precommit:
    mix precommit
    just test

# JS/TS static gate (mirrors CI): clean install + typecheck/lint/format-check.
[private]
assets-check:
    npm --prefix assets ci
    npm --prefix assets run typecheck
    npm --prefix assets run lint
    npm --prefix assets run format:check

lint:
    mix lint
    just assets-check

format *ARGS:
    mix format {{ARGS}}
