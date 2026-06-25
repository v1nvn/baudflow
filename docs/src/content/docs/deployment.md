---
title: Deployment
description: Run Baudflow in production with Docker — image, env vars, health, metrics, and backups.
order: 40
---

## Container image

A multi-arch image (`linux/amd64`, `linux/arm64`) is built for every release tag
and published to GHCR:

```
ghcr.io/v1nvn/baudflow:<version>
```

The fastest path is the included `docker-compose.yml`, which brings up Baudflow
with Postgres in one command.

## Required environment

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | Ecto connection string, e.g. `ecto://user:pass@host/baudflow` |
| `SECRET_KEY_BASE` | Long random value used to sign/encrypt session cookies |

Additional runtime wiring (binary paths, ports, host) lives in
`config/runtime.exs`. See the
[Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html) for
production hardening.

## Health & monitoring

- **`GET /health`** — point an external uptime monitor here.
- **`GET /metrics`** — scrape with Prometheus for `baudflow_*` gauges. The
  endpoint is hand-rolled text format with no caching layer.

## Retention & backups

The `CleanupWorker` prunes measurements beyond the configured retention window.
To preserve history, back up the PostgreSQL database on a schedule that matches
your retention policy.
