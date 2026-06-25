---
title: Troubleshooting
description: Common issues — missing speedtest binary, database connection, and port conflicts.
order: 50
---

## `speedtest` binary not found

Baudflow shells out to the Ookla CLI. Install the
[Speedtest CLI](https://www.speedtest.net/apps/cli) and ensure `speedtest` is on
the `$PATH` of the environment running the app. Binary resolution happens only
inside `SpeedtestWorker` — if a run fails immediately with a not-found error,
this is the cause.

## Database connection errors

Confirm `DATABASE_URL` is correct and reachable, and that migrations have run:

```bash
mix ecto.migrate
```

For Docker, check that the Postgres container is up and that Baudflow's network
can reach it.

## Tests fail in CI but pass locally

CI runs the full gate (`mix lint` + the test suite in a throwaway testcontainers
Postgres). `mix precommit` is a **fast loop that skips lint** — it can be green
locally while CI is red. Run the CI-equivalent gate before pushing.

## Port 4000 already in use

Either stop the conflicting process or set a different port in your runtime
config / `PORT` environment variable.

## No data flowing

- Verify the cron schedule is set and the scheduler is enqueuing jobs.
- Check Oban queues — workers stay decoupled, so a stuck queue in one stage
  won't surface in another.
- Ensure a terminal event is being emitted for each run.
