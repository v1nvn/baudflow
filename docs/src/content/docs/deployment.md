---
title: Deployment
description: Run Baudflow in production — container image, environment, health, metrics, and backups.
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

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DATABASE_URL` | yes | — | Ecto connection string, e.g. `ecto://user:pass@host/baudflow` |
| `SECRET_KEY_BASE` | yes | — | Signs/encrypts session cookies. Generate with `mix phx.gen.secret` |
| `PHX_HOST` | no | `example.com` | Public host, used in generated URLs and redirects |
| `PORT` | no | `4000` | HTTP listen port |
| `POOL_SIZE` | no | `10` | DB connection pool size |
| `ECTO_IPV6` | no | — | `true` or `1` to connect to Postgres over IPv6 |
| `DNS_CLUSTER_QUERY` | no | — | DNS name for Erlang clustering (multi-node) |
| `PHX_SERVER` | no | — | `true` to start the web server (used by releases) |

On boot the release runs `Baudflow.Release.migrate/0`, so migrations apply
automatically — no separate step unless you run from source (`mix ecto.migrate`).

Notification transport wiring (for example the ntfy endpoint) is set through
application env, not these process env vars — see [Notifications](../notifications/).

## Health & monitoring

- **`GET /health`** — returns `{"status":"ok"}`. Point an external uptime monitor
  (Uptime Kuma, a Kubernetes liveness probe) here.
- **`GET /metrics`** — Prometheus text format, hand-rolled with no cache and no
  dependencies. Scrape it for `baudflow_*` gauges — see
  [Prometheus metrics](../prometheus-metrics/) for the full list.

Both endpoints bypass the browser pipeline deliberately: `/metrics` serves plain
text so scrapers avoid JSON content-negotiation and the CSRF/session plugs.

## Retention & backups

The `CleanupWorker` runs daily at 03:00 and prunes measurements older than
`retention_days` (default 365). To preserve history, back up the PostgreSQL
database on a cadence that matches your retention window. The full raw result
JSON is stored on every measurement, so a backup is a complete record.

## Production checklist

- Set a strong `SECRET_KEY_BASE` (≥ 64 bytes).
- Point `PHX_HOST` at your real domain, behind your reverse proxy / TLS.
- Give the container a reachable Postgres and a persistent volume for the DB.
- Scrape `/metrics` and watch `/health`.
- Decide on retention and schedule DB backups.
