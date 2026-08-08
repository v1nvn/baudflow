---
title: Environment variables
description: "Process env vars read at runtime: database, secrets, host, ports, and clustering."
section: Reference
order: 20
---

These eight variables are read from the process environment in `config/runtime.exs`, which runs once at boot after compilation and before the system starts. Only `DATABASE_URL` and `SECRET_KEY_BASE` are required for a production release.

**Restart needed: yes for every variable below.** None are re-read at runtime; changing a value requires restarting the process.

## Required

Both raise at boot in production if unset.

| Variable | Default | Example | When read |
|---|---|---|---|
| `DATABASE_URL` | (none) | `ecto://USER:PASS@HOST/baudflow` | boot, prod |
| `SECRET_KEY_BASE` | (none) | output of `mix phx.gen.secret` | boot, prod |

## Optional

| Variable | Default | Example | When read |
|---|---|---|---|
| `PHX_HOST` | `example.com` | `baudflow.example.com` | boot, prod |
| `PORT` | `4000` | `4000` | boot, all envs |
| `POOL_SIZE` | `10` | `15` | boot, prod |
| `ECTO_IPV6` | unset | `true` | boot, prod |

> **`PHX_HOST` defaults to `example.com`.** Set it to your real domain in production. It drives generated URLs and redirects, so leaving the default produces links and redirects pointing at `example.com`.

`ECTO_IPV6` is enabled by setting it to `true` or `1`; any other value leaves Postgres on IPv4.

## Deployment

| Variable | Default | Example | When read |
|---|---|---|---|
| `PHX_SERVER` | unset | `true` | boot, all envs |

Set `PHX_SERVER=true` to start the web server when running a release (for example, `PHX_SERVER=true bin/baudflow start`). Unset in `mix phx.server` / dev, where the server starts by other means.

## Clustering

| Variable | Default | Example | When read |
|---|---|---|---|
| `DNS_CLUSTER_QUERY` | unset | `baudflow.internal` | boot, prod |

DNS name queried to discover peer Erlang nodes. The query must resolve to the IPs of running nodes. Leave unset for a single-node deployment.

---

Notification transport (for example the ntfy endpoint) is set through application env (`config :baudflow, ntfy_url: ..., ntfy_topic: ...`), not these variables. See [Notifications](../notifications/).
