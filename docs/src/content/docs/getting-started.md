---
title: Getting Started
description: Prerequisites and a one-command install to run Baudflow locally.
order: 10
---

## Prerequisites

- **Elixir 1.19+** and **Erlang/OTP 29+**
- **PostgreSQL**
- The [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli), installed and on your `$PATH`

## Quick start

```bash
# Install deps, create the database, and run migrations
mix setup

# Start the Phoenix server
mix phx.server
```

Now visit [localhost:4000](http://localhost:4000). You can also run inside an IEx
session:

```bash
iex -S mix phx.server
```

The dashboard is live. Trigger a manual speed test from the home page, or wait
for the scheduler to fire one — the CRT oscilloscope streams the run in real
time.

## Run with Docker

Prefer a container? An image is published for each release:

```bash
docker run -d \
  -p 4000:4000 \
  -e DATABASE_URL=ecto://user:pass@db-host/baudflow \
  -e SECRET_KEY_BASE=replace-with-a-long-random-value \
  ghcr.io/v1nvn/baudflow:0.6.0
```

A `docker-compose.yml` is included in the repo for a single-command stack with
Postgres. See the [Deployment guide](../deployment/) for the full setup.

## Next steps

- Schedule tests and set degradation thresholds on the [Configuration](../configuration/) page.
- Understand the worker pipeline in [Architecture](../architecture/).
