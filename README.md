# BaudFlow

A self-hosted network speed monitoring dashboard built with Phoenix LiveView. BaudFlow runs automated speed tests via the [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli), stores the results, and visualizes your network performance over time.

## Features

- **Automated & manual speed tests** — schedule tests on a cron or trigger one from the dashboard
- **Real-time dashboard** — live charts for download/upload speeds and latency via Chart.js
- **Run history** — browse past test runs with success/failure status
- **Per-result detail** — drill into ping, jitter, download, upload, server, and ISP info for any individual measurement
- **Configurable settings** — cron schedule, preferred/blocked servers, retention policy, degradation thresholds
- **Background processing** — Oban workers for test execution, scheduling, cleanup, and notifications
- **Health endpoint** — `GET /health` for uptime monitoring

## Quick Start

### Prerequisites

- Elixir 1.18+ and Erlang/OTP 27+
- PostgreSQL
- [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli) installed and in `$PATH`

### Setup

```bash
# Install dependencies, create database, run migrations
mix setup

# Start the server
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) from your browser.

You can also run inside an IEx session:

```bash
iex -S mix phx.server
```

## Architecture

```
lib/
├── baud_flow/
│   ├── measurements/        # Speedtest schema, worker, scheduler, cleanup
│   ├── runs/                # Test run tracking
│   └── settings/            # App configuration (key-value)
└── baud_flow_web/
    ├── live/
    │   ├── dashboard_live.ex   # / — main dashboard
    │   ├── history_live.ex     # /history — historical trends
    │   ├── runs_live.ex        # /runs — run management
    │   ├── result_live.ex      # /results/:id — single result
    │   └── settings_live.ex    # /settings — configuration
    ├── components/             # Shared UI components
    └── router.ex
```

Key dependencies: **Phoenix 1.8**, **LiveView**, **Ecto + PostgreSQL**, **Oban** (jobs), **Tailwind CSS v4**, **Bandit**.

## Running Tests

```bash
mix test
```

## Pre-commit Checks

```bash
mix precommit
```

## Deployment

See the [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html) for production setup. A `docker/` directory is included for containerized deployment.

## Learn More

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html)
- [Phoenix Docs](https://hexdocs.pm/phoenix)
- [Elixir Forum](https://elixirforum.com/c/phoenix-forum)
