---
title: Overview
description: Baudflow records scheduled speed tests and continuous pings, stores every result in full, and derives health, SLA, and alerts from the record.
section: Start
order: 5
updated: '2026-08-08'
---

Baudflow records scheduled Ookla speed tests and continuous TCP pings, stores
every result in full, and derives health verdicts, SLA compliance, and alerts
from the record. It is a self-hosted Elixir/Postgres app.

![Baudflow dashboard](../../assets/screenshots/dashboard.png)

One speed test gives you one number. The record answers the questions a single
number can't: was the line slow on the 14th, how often it made plan speed this
month, when it broke and for how long.

## How it runs

- **Container** — multi-arch (`amd64`, `arm64`), non-root (UID 1000), Ookla CLI
  baked in. No `CAP_NET_RAW`: pings are TCP-connect, not ICMP.
- **Database** — Postgres only. You bring it; the image brings everything else.
- **Ingress** — plain HTTP on `:4000`. Put a reverse proxy in front. There is no
  built-in login yet.

See [Getting started](../getting-started/) for a one-command boot and
[Deployment](../deployment/) for manifests.

## What it stores

Every measurement keeps its full raw result — the complete Ookla JSON for a
speed test, the full sample set for a ping run. Derived views (health, SLA,
averages, the heatmap) are computed on the fly from that record and the current
thresholds, so changing a threshold re-derives history instantly. Nothing is
backfilled; nothing is lost.

## Core concepts

| Concept | Meaning |
|---|---|
| **Schedule** | A row: cron cadence, test type, target, its own thresholds and escalation state. Scheduling is data, not config keys. |
| **Measurement** | One run's full raw result, stored verbatim. |
| **Health verdict** | `:healthy` \| `:breach` \| `:failed` \| `:unknown`, derived per measurement against thresholds. `:unknown` means too little history to judge yet (calibrating). |
| **SLA** | The share of measurements that met plan speed over a window. Derived, not stored. |

## Integrate

- `GET /metrics` — eight `baudflow_*` gauges, Prometheus text format. See [Prometheus metrics](../prometheus-metrics/).
- `GET /health` — `{"status":"ok"}`, for uptime monitors and probes.
- `GET /heatmap/embed` — chrome-less heatmap for iframe embedding. See [HTTP endpoints](../http-api/).

## Next steps

- [Getting started](../getting-started/) — one-command boot.
- [Configuration](../configuration/) — schedules, thresholds, notifications from the UI.
- [Deployment](../deployment/) — production setup, backups, upgrades.
