---
title: Environment variables
description: Process env vars read at runtime — database, secrets, host, ports, clustering.
section: Reference
order: 20
---

These are read from the process environment in `config/runtime.exs`. Only
`DATABASE_URL` and `SECRET_KEY_BASE` are required for a production release.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DATABASE_URL` | yes | — | Ecto connection string: `ecto://user:pass@host/baudflow` |
| `SECRET_KEY_BASE` | yes | — | Signs/encrypts cookies. Generate with `mix phx.gen.secret`. |
| `PHX_HOST` | no | `example.com` | Public host for generated URLs and redirects. |
| `PORT` | no | `4000` | HTTP listen port. |
| `POOL_SIZE` | no | `10` | DB connection pool size. |
| `ECTO_IPV6` | no | — | `true` / `1` to connect to Postgres over IPv6. |
| `DNS_CLUSTER_QUERY` | no | — | DNS name for Erlang node clustering. |
| `PHX_SERVER` | no | — | `true` to start the web server (releases). |

Notification transport (for example the ntfy endpoint) is set through application
env (`config :baudflow, ntfy_url: ..., ntfy_topic: ...`), not these variables —
see [Notifications](../notifications/).
