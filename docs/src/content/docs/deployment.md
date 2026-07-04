---
title: Deployment
description: "Run Baudflow in production: container image, environment, health, metrics, and backups."
section: Getting started
order: 20
---

## Container image

A multi-arch image (`linux/amd64`, `linux/arm64`) is built for every release tag
and published to the GitHub Container Registry:

```
ghcr.io/v1nvn/baudflow:<version>
```

It's a two-stage Elixir release: a self-contained BEAM bundle that runs as
**non-root UID 1000**, with the Ookla CLI pre-installed at
`/usr/local/bin/speedtest`. The fastest path is the repo's `docker-compose.yml`,
which brings up Baudflow with Postgres in one command. Pin a `:%VERSION%`-style tag
for stability; `:latest` follows `main`.

## Environment

Only `DATABASE_URL` and `SECRET_KEY_BASE` are required for a production release;
see [Environment variables](../environment-variables/) for the full list,
including `PHX_HOST`, `PORT`, `POOL_SIZE`, and clustering options.

On boot the release runs `Baudflow.Release.migrate/0`, so migrations apply
automatically. No separate step is needed unless you run from source (`mix ecto.migrate`).

Notification transport wiring (for example the ntfy endpoint) is set through
application env, not these process env vars. See [Notifications](../notifications/).

## Why PostgreSQL?

baudflow leans on Postgres for the workload it is good at: typed columns, JSON
storage for the full raw result of every test, and window queries for baselines
and SLA. The container ships with everything else; you just provide the
database. There is no SQLite or MySQL mode, and none is planned — the schema
uses those features deliberately.

## Health & monitoring

- **`GET /health`**: returns `{"status":"ok"}`. Point an external uptime monitor
  (Uptime Kuma, a Kubernetes liveness probe) here.
- **`GET /metrics`**: Prometheus text format, hand-rolled with no cache and no
  dependencies. Scrape it for `baudflow_*` gauges. See
  [Prometheus metrics](../prometheus-metrics/) for the full list.

Both endpoints bypass the browser pipeline deliberately: `/metrics` serves plain
text so scrapers avoid JSON content-negotiation and the CSRF/session plugs.

## Retention & backups

The `CleanupWorker` runs daily at 03:00 and prunes measurements older than
`retention_days` (default 365). To preserve history, back up the PostgreSQL
database on a cadence that matches your retention window. The full raw result
JSON is stored on every measurement, so a backup is a complete record.

## Security & access

baudflow is single-user by default and assumes it sits behind your own reverse
proxy or auth proxy (the project itself runs behind one). There is no built-in
login yet; the default is intentionally frictionless for a homelab. Auth is on
the roadmap. Until then, put an auth proxy in front and expose `/health` and
`/metrics` only if you intend to scrape them from outside the boundary.

## Production checklist

- Set a strong `SECRET_KEY_BASE` (≥ 64 bytes).
- Point `PHX_HOST` at your real domain, behind your reverse proxy / TLS.
- Give the container a reachable Postgres and a persistent volume for the DB.
- Scrape `/metrics` and watch `/health`.
- Decide on retention and schedule DB backups.
