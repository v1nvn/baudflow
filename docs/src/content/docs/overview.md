---
title: Overview
description: "What baudflow is, the design principles behind it, and the full feature catalog: real-time visibility, health intelligence, alerting, and stack integration."
section: Getting started
order: 5
article: true
updated: '2026-07-04'
---

Baudflow is a self-hosted network monitoring platform built with Phoenix
LiveView, Oban, and PostgreSQL. It runs automated Ookla speed tests and
continuous TCP-connect pings on a schedule, streams every run in real time, and
turns the results into health verdicts, SLA compliance, and alerts.

A speed test on a schedule tells you a number. Baudflow tells you whether your
connection is healthy, when it broke, how badly, and whether your provider is
delivering what you pay for — and it keeps the full raw record so the answer is
auditable, not anecdotal.

## Design principles

- **Raw data is sacred; derived views are cheap.** Every test's complete result
  is stored. Health verdicts, SLA percentages, and heatmaps are derived on the
  fly, so changing your thresholds or mode re-derives every past view instantly.
  Nothing is backfilled, nothing is lost.
- **Behaviours, not branches.** Test backends and notification channels are
  behaviour implementations. Adding a channel or a backend is a self-contained
  module, not a new fork in a worker.
- **One concern per stage.** Scheduling, running, evaluating, and notifying each
  live in their own context, wired together by Oban jobs rather than reaching
  into each other's internals.

## What a bare speed test leaves out

A scheduled speed test gives you one number per run. Baudflow closes the gaps
that number alone leaves open:

- **Adaptive cadence.** An hourly test gives a single point per hour — a blur
  during an outage and wasted bandwidth the rest of the time. A breached
  schedule runs faster until it recovers, then slows back down, giving you a
  detailed outage timeline without paying for it in bandwidth.
- **First-class ping.** Latency, jitter, and loss degrade before throughput
  moves. A continuous TCP-connect ping runner with its own live console catches
  what a speed test misses; most outages show up here first.
- **SLA + raw retention.** "It feels slow" is not a support ticket. Baudflow
  stores every result in full and rolls it into SLA percentages, breach
  timelines, and heatmaps — the kind of record a provider actually has to
  answer for.
- **A real alert pipeline.** Threshold checks bolted onto a cron fire on every
  re-check. Baudflow's event → policy → template → channel pipeline gates a
  breach to fire exactly once, and also notifies on recovery and on outright
  failure.

## Feature catalog

### Real-time visibility

Baudflow streams progress over PubSub as each test runs — no spinner, polling,
or waiting for a result to land.

- **Live CRT oscilloscope** — Ookla NDJSON streamed line-by-line, with phase
  tracking and phosphor afterglow as the waveform builds.
- **Live ping diagnostics** — a dedicated `/ping` page streams each TCP-connect
  sample: cumulative average, jitter, low/high, and loss, updating live.
- **Manual runs + history** — trigger a test instantly or let the scheduler run.
  Every run is logged with success, failure, or timeout status.
- **Per-result drill-down** — ping, jitter, packet loss, server, ISP. Every
  measurement is fully inspectable, with the raw JSON preserved.

### Health intelligence

Health is derived just-in-time from thresholds, never stored, so changing your
mode re-derives every view instantly.

- **Adaptive cadence** — a breached schedule switches to a faster escalated cron
  until it recovers, capturing outage detail without wasted bandwidth.
- **Auto / absolute / off thresholds** — Auto judges against your own rolling
  baseline (zero-config); Absolute uses fixed Mbps/ms; Off disables verdicts.
- **Breach streaks & transitions** — healthy → breach → recovered transitions,
  tracked atomically per schedule and surfaced to alerts and escalation.
- **SLA compliance** — the percentage of tests that met your promised speeds:
  "delivered 91.3% of the month" instead of a bare Mbps number.
- **Health heatmap** — a GitHub-style calendar wall revealing evening
  congestion, weekend slowdowns, and recurring outages at a glance.

### Alerting

Event → policy → template → channel. Each layer is one concern; the policy
decides whether to notify before any rendering work is done.

- **Four-layer pipeline** — a pure policy module, a per-channel template
  renderer, and a channel behaviour. Adding a channel is one module.
- **Breach-streak gating** — a breach fires exactly once, when the streak first
  reaches your threshold, not on every re-check. Less noise.
- **Recovery & failure alerts** — get notified when service recovers and when a
  run outright fails, not only on degradation.
- **ntfy** — push to a self-hosted or hosted ntfy.sh topic, wired through
  application env.
- **Webhooks + templates** — POST JSON to Home Assistant, Grafana, n8n, or a
  custom endpoint, with an editable EEx body. A blank URL disables it.

### Integrations

Standard interfaces, plain text, no lock-in. Baudflow slots into the
observability setup you already run.

- **Prometheus `/metrics`** — eight `baudflow_*` gauges in hand-rolled text
  format, NaN for stale values. Scrape it like any exporter.
- **`/health` endpoint** — a lightweight liveness check for Uptime Kuma or a
  Kubernetes probe.
- **Embeddable heatmap** — a chrome-less `/heatmap/embed` route for iframing
  into Home Assistant or Grafana dashboards.
- **Raw JSON retention** — the full result is stored on every measurement;
  derived views are cheap, raw data is sacred. Pruned by retention.
- **Multi-arch Docker** — a non-root, Ookla-bundled image for `amd64` and
  `arm64`. One container, one Postgres.

## Next steps

- [Get started](../getting-started/) — install in under a minute.
- Problem-first walkthroughs: [Self-host](../self-host/),
  [Monitor ISP speed](../monitor-isp-speed/),
  [Internet speed SLA](../internet-speed-sla/).
- See how baudflow [compares to speedtest-tracker](../comparison/).
- Read the [FAQ](../faq/).
