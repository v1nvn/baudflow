# Baudflow

A self-hosted network speed monitoring dashboard built with Phoenix LiveView. Baudflow runs automated speed tests via the [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli), stores the results, and visualizes your network performance over time.

## Features

- Schedule tests on a cron, or trigger one from the dashboard
- Watch each test run on a CRT-style oscilloscope with real-time waveform, phase tracking (ping → download → upload), and live stats
- Browse historical charts for download/upload speeds, latency, jitter, packet loss, and test duration via Chart.js
- Speedtest CLI output streams line-by-line over Erlang ports for instant progress updates
- Browse past test runs with success/failure status
- Drill into ping, jitter, download, upload, server, and ISP info for any individual measurement
- Configure the cron schedule, preferred/blocked servers, retention policy, and degradation thresholds
- Oban workers handle test execution, scheduling, cleanup, and notifications
- Expose `GET /health` for uptime monitoring

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

## License

Copyright (C) 2026 Vineet Kumar (@v1nvn)

Baudflow is free software: you can redistribute it and/or modify it under the
terms of the GNU Affero General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

Baudflow is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the
[GNU Affero General Public License](https://www.gnu.org/licenses/agpl-3.0.html)
for more details.

You should have received a copy of the GNU Affero General Public License along
with this program. If not, see <https://www.gnu.org/licenses/>.

The bundled [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli) is a
third-party binary under its own separate license terms; the AGPL above applies
only to the baudflow source, not the Ookla binary.
