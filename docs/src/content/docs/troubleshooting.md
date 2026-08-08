---
title: Troubleshooting
description: "Common issues: missing speedtest binary, database connection, ping reading 100% loss, and CI-vs-local test gates."
section: Operate
order: 60
---

## Baudflow won't start

**`DATABASE_URL` missing or unreachable.** The release won't boot without it.
Confirm the URL is correct and Postgres is reachable, then run migrations:

```bash
mix ecto.migrate
```

Under Docker, check that the Postgres container is up and on the same network as
Baudflow. If `ECTO_IPV6=true` is set, Postgres must actually listen on IPv6.

**`SECRET_KEY_BASE` missing.** Required for a production release. Generate one
and set it in the environment:

```bash
mix phx.gen.secret
```

**Port 4000 already in use.** Stop the conflicting process, or set a different
`PORT`.

## Speed tests aren't running

Walk the pipeline in order. The scheduler dispatches both speed tests and pings,
so "nothing running at all" and "speed tests only" point to different stages.

**Nothing running (no speed tests, no pings)?** The scheduler is the first thing
to check:

- A schedule is **enabled** and its `cron` is valid. A bad cron on one row is
  logged and skipped, not fatal — check the logs for a parse error on that row.
- The scheduler is enqueueing. It runs every minute; look for `SchedulerWorker`
  jobs in Oban.
- A stuck Oban queue in one stage won't surface in another — the stages are
  decoupled. Check queue state directly.

**Pings run but speed tests don't?** The Ookla runner can't find the `speedtest`
binary. A run that fails immediately with `speedtest binary not found: ...` is
this.

The Docker image bundles the Ookla CLI at `/usr/local/bin/speedtest`, so this
only affects source builds. Install the [Speedtest
CLI](https://www.speedtest.net/apps/cli) and put `speedtest` on the `$PATH` of
the environment running the app, or point `SPEEDTEST_BIN` at it. (The TCP-connect
ping runner needs no binary.)

## Ping shows 100% packet loss

The ping runner opens TCP connections to `host:port` and treats each completed
handshake as a latency sample; a failed connect reads as loss. It is not ICMP and
needs no `CAP_NET_RAW`.

If the target doesn't accept TCP on the configured port, every connect fails and
reads as 100% loss. Defaults target `1.1.1.1:443` (Cloudflare), which always
speaks TCP. Point a schedule at a different `target_host` / `target_port`
(per-row override), or `ping_target` / `ping_port` globally (Settings), at
something that accepts the connection.

## Tests pass locally but fail in CI

CI runs the full gate: `mix lint` (format check, unused deps, warnings-as-errors,
credo, sobelow, dialyzer), the assets gate (typecheck, lint, format check), then
the suite against a fresh Postgres service container. `just precommit` is a **fast
loop that skips `mix lint`**, so it can be green locally while CI is red.

Run the CI-equivalent gate before pushing:

```bash
just check
```

## Disk filling up

Measurements store the full raw result JSON. Lower `retention_days` (Settings,
default `365`) if history is growing faster than you want. `CleanupWorker` prunes
daily at 03:00.
