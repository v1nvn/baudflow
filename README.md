# Baudflow

[![GitHub release](https://img.shields.io/github/v/release/v1nvn/baudflow?logo=github)](https://github.com/v1nvn/baudflow/releases)
[![GitHub stars](https://img.shields.io/github/stars/v1nvn/baudflow?style=social)](https://github.com/v1nvn/baudflow/stargazers)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](https://www.gnu.org/licenses/agpl-3.0.html)

A self-hosted speed-test tracker and network monitor. Baudflow runs automated
[Ookla](https://www.speedtest.net/apps/cli) speed tests and continuous
TCP-connect pings on a schedule, streams every run in real time, and turns the
results into health verdicts, SLA compliance, and a calendar heatmap you can take
to your ISP.

![A live Ookla speed test streaming into baudflow's CRT oscilloscope — download phase, building in real time.](docs/src/assets/screenshots/oscilloscope.jpg)

**Docs:** [baudflow.com/docs](https://baudflow.com/docs) · **Why:** [Why I built baudflow](https://baudflow.com/articles/why-i-built-baudflow/) · **Compare:** [baudflow vs speedtest-tracker](https://baudflow.com/articles/baudflow-vs-speedtest-tracker/)

## Quick start

**With Docker Compose** (brings its own Postgres, zero config):

```bash
git clone https://github.com/v1nvn/baudflow && cd baudflow
docker compose up
```

Then open [localhost:4000](http://localhost:4000). Migrations run automatically on
first boot.

**Or run the prebuilt image** against an existing Postgres:

```bash
docker run -d --name baudflow -p 4000:4000 \
  -e DATABASE_URL="ecto://user:pass@host/baudflow" \
  -e SECRET_KEY_BASE="replace-with-a-long-random-value" \
  ghcr.io/v1nvn/baudflow:latest
```

Only `DATABASE_URL` and `SECRET_KEY_BASE` are required — see the
[environment variables](https://baudflow.com/docs/environment-variables/) reference.
The image is multi-arch (`linux/amd64`, `linux/arm64`) and bundles the Ookla CLI.
`:latest` tracks `main`; tagged releases (e.g. `v0.11.7`) are the stable cuts —
see [packages](https://github.com/v1nvn/baudflow/pkgs/container/baudflow).

## Features

**Real-time visibility**

- CRT-style oscilloscope streaming each test as it runs, with phase tracking (ping → download → upload) and live stats
- First-class continuous TCP-connect ping runner with its own live, per-sample console — no binary, no `CAP_NET_RAW`
- Historical charts for download/upload, latency, jitter, packet loss, and test duration (Chart.js)

**Health intelligence**

- SLA compliance tracking against the speed you're promised — "delivered 91.3% this month," with breach streaks
- GitHub-style health heatmap: a calendar of healthy / breach / failed days
- Adaptive cadence: a breached schedule runs faster until it recovers, then slows back down
- Breach-streak alert gating — a degradation notifies once, not on every re-check

**Fits your stack**

- Multi-schedule platform with per-target cron, thresholds, and escalation
- Four-layer alert pipeline (event → policy → template → channel): ntfy and webhooks
- Prometheus `/metrics` endpoint
- Embeddable heatmap widget (iframe) for external dashboards
- `GET /health` for uptime monitors

## How it compares to speedtest-tracker

speedtest-tracker is the mature incumbent — PHP/Laravel, broad Apprise
notifications, SQLite/MySQL/Postgres, a multi-language UI. baudflow is a newer
Elixir/Phoenix project that trades that breadth for a live real-time dashboard, a
first-class continuous ping runner, SLA tracking, and adaptive schedules —
several of speedtest-tracker's most-upvoted open requests, built. See the
[full, source-cited comparison](https://baudflow.com/articles/baudflow-vs-speedtest-tracker/).

## Screenshots

| Dashboard | Health heatmap | Live ping |
|---|---|---|
| ![Dashboard](docs/src/assets/screenshots/dashboard.png) | ![Health heatmap](docs/src/assets/screenshots/heatmap.png) | ![Live ping](docs/src/assets/screenshots/ping.png) |

## Stack

**Phoenix 1.8** · **LiveView** · **Oban** · **PostgreSQL** · **Tailwind CSS v4** · **Chart.js** · **Bandit**

## Development

From source you'll need **Elixir 1.20+**, **Erlang/OTP 29+**, **PostgreSQL**, and
the [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli) on your `$PATH`
(only for speed tests — the ping runner needs no binary).

```bash
mix setup      # install deps, create the database, run migrations
mix phx.server # start the server at localhost:4000
```

The [justfile](justfile) is the source of truth for the quality gates CI runs:

```bash
just precommit   # fast loop: compile warnings, format, then the test suite
just check       # the done-gate: mix lint + assets-check (tsc/eslint/prettier) + tests
```

## Architecture

```
lib/
├── baudflow/
│   ├── measurements/    # Speedtest schema, NDJSON streaming, cleanup, retention
│   ├── scheduling/      # Cron schedules, thresholds, adaptive cadence
│   ├── runs/            # Test run tracking
│   ├── notifications/   # Four-layer alert pipeline + channels (behaviours)
│   ├── health/          # Health verdicts
│   ├── settings/        # Key-value config with typed getters + safe fallbacks
│   └── test_runners/    # Speedtest + ping runner behaviours
└── baudflow_web/
    ├── live/            # Dashboard, ping, history, heatmap, schedules, settings, runs
    └── components/      # Shared HEEx + function components
assets/
├── js/                  # app.ts, charts.ts (Chart.js hooks), typed event payloads
└── css/                 # Tailwind v4 + CRT panel styles
```

The four pipeline stages — decide, run, evaluate, notify — are decoupled, each in
its own context, triggered by Oban jobs. See
[`ARCHITECTURE.md`](ARCHITECTURE.md) and the [docs](https://baudflow.com/docs/).

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
