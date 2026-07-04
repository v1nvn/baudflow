---
title: Troubleshooting
description: "Common issues: missing speedtest binary, database connection, ping reading 100% loss, and CI-vs-local test gates."
section: Resources
order: 10
---

## `speedtest` binary not found

The Docker image bundles the Ookla CLI at `/usr/local/bin/speedtest`, so this
only affects source builds. Install the
[Speedtest CLI](https://www.speedtest.net/apps/cli) and make sure `speedtest` is
on the `$PATH` of the environment running the app. Binary resolution happens only
inside the runner. A run that fails immediately with a not-found error is this.
(The TCP-connect ping runner needs no binary.)

## Database connection errors

Confirm `DATABASE_URL` is correct and reachable, and that migrations have run:

```bash
mix ecto.migrate
```

Under Docker, check that the Postgres container is up and on the same network as
Baudflow. If `ECTO_IPV6=true` is set, make sure Postgres actually listens on IPv6.

## A ping schedule reads 100% packet loss

The ping runner opens TCP connections to `host:port` and treats a completed
handshake as a latency sample. If the target doesn't accept TCP on the configured
port, every connect fails and reads as 100% loss. Defaults target `1.1.1.1:443`
(Cloudflare), which always speaks TCP. Point a schedule at a different
`target_host` / `target_port` (or `ping_target` / `ping_port` globally) at
something that accepts the connection.

## Tests pass locally but fail in CI

CI runs the full gate: `mix lint` plus the suite against a fresh Postgres
service container. `just precommit` is a **fast loop that skips lint**, so it can
be green locally while CI is red. Run the CI-equivalent gate before pushing:
`just check`.

## Port 4000 already in use

Stop the conflicting process, or set a different `PORT`.

## No data flowing

- Verify a schedule is enabled and its cron is valid; a bad cron on one row is
  logged and skipped, not fatal.
- Check the Oban queues. Workers stay decoupled, so a stuck queue in one stage
  won't surface in another.
- Make sure the scheduler is enqueueing: look for `SchedulerWorker` jobs.

## Disk filling up

Measurements store the full raw result JSON. Lower `retention_days` if history is
growing faster than you want; the `CleanupWorker` prunes daily at 03:00.
