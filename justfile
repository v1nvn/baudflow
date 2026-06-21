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

# ── Setup ──────────────────────────────────────────────────────────────

# First-time project bootstrap
setup:
    mix setup
    npm --prefix assets ci

# ── Local development ──────────────────────────────────────────────────

# Start local dev server (auto-starts Postgres + speedtest from compose if needed)
dev: (db-up) (speedtest-up) (migrate-dev)
    SPEEDTEST_BIN="docker exec baudflow-speedtest speedtest" mix phx.server

# Start dev server with IEx shell
dev-iex: (db-up)
    iex -S mix phx.server

# Ensure the compose db service is running
[private]
db-up:
    docker compose up -d db --wait

# Ensure the speedtest sidecar is running
[private]
speedtest-up:
    docker compose up -d speedtest --wait

# Run pending migrations locally
[private]
migrate-dev:
    mix ecto.migrate

# ── Docker ─────────────────────────────────────────────────────────────

# Build image and start compose stack
docker-up:
    docker build -t baudflow:latest .
    docker compose up -d

# Stop compose stack
docker-down:
    docker compose down

# Tail app container logs
docker-logs:
    docker compose logs -f app

# Rebuild image and restart just the app service
docker-rebuild:
    docker build -t baudflow:latest .
    docker compose up -d --force-recreate app

# Attach remote console to running container
console:
    docker compose exec app /app/bin/baudflow remote

# Run pending migrations in the container
migrate:
    docker compose exec app /app/bin/baudflow eval "Baudflow.Release.migrate()"

# Wipe DB volume and start fresh
db-reset:
    docker compose down -v
    docker compose up -d

# ── Quality ────────────────────────────────────────────────────────────

# Run the test suite (args forwarded: `just test test/foo.exs`, `just test --failed`)
test *ARGS:
    mix test {{ARGS}}

# Full CI gate locally: `mix lint` (dev) + tests in a throwaway Postgres
# (testcontainers, MIX_ENV=test) — the two steps ci.yml runs. Run before pushing.
check:
    mix lint
    MIX_ENV=test mix testcontainers.run --database postgres test

# Fast loop gate (compile warnings, deps.unlock --unused, format, test). NOT CI-equivalent:
# it skips the static gate (format-check, credo, sobelow, dialyzer) — pair with `just lint`.
precommit: (db-up)
    mix precommit

# No-DB static gate (format-check, deps.audit, warnings-as-errors, credo --strict, sobelow, dialyzer)
lint:
    mix lint

# Apply the formatter (writes) — fixer for `just lint`'s format-check. `just format` (all) or `just format path.ex`.
format *ARGS:
    mix format {{ARGS}}
