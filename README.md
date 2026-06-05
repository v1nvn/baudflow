# Baudflow

A self-hosted network speed monitoring dashboard built with Phoenix LiveView. Baudflow runs automated speed tests via the [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli), stores the results, and visualizes your network performance over time.

## Features

- **Automated & manual speed tests** - schedule tests on a cron or trigger one from the dashboard
- **Live speedtest visualization** - CRT-style oscilloscope display with real-time waveform, phase tracking (ping → download → upload), and live stats as the test runs
- **Real-time dashboard** - historical charts for download/upload speeds, latency, jitter, packet loss, and test duration via Chart.js
- **NDJSON streaming** - speedtest CLI output streamed line-by-line via Erlang ports for instant progress updates
- **Run history** - browse past test runs with success/failure status
- **Per-result detail** - drill into ping, jitter, download, upload, server, and ISP info for any individual measurement
- **Configurable settings** - cron schedule, preferred/blocked servers, retention policy, degradation thresholds
- **Background processing** - Oban workers for test execution, scheduling, cleanup, and notifications
- **Health endpoint** - `GET /health` for uptime monitoring

## Quick Start

### Prerequisites

- Elixir 1.19+ and Erlang/OTP 29+
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
├── baudflow/
│   ├── measurements/        # Speedtest schema, NDJSON streaming worker, scheduler, cleanup
│   ├── runs/                # Test run tracking
│   └── settings/            # App configuration (key-value)
└── baudflow_web/
    ├── live/
    │   ├── dashboard_live.ex   # / - main dashboard + live speedtest viz
    │   ├── history_live.ex     # /history - historical trends
    │   ├── runs_live.ex        # /runs - run management
    │   ├── result_live.ex      # /results/:id - single result
    │   └── settings_live.ex    # /settings - configuration
    ├── components/             # Shared UI components
    └── router.ex
assets/
├── js/app.js                # Chart.js hooks + SpeedtestViz CRT oscilloscope hook
└── css/app.css              # Tailwind v4 + CRT panel styles
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
