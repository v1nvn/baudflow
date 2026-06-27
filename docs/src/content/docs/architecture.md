---
title: Architecture
description: The four-stage Oban pipeline, per-domain contexts, the real-time PubSub layer, and the metrics endpoints.
section: Guides
order: 10
---

Baudflow is a Phoenix 1.8 + LiveView app backed by PostgreSQL and Oban. All work
flows through a four-stage pipeline — **decide → run → evaluate → notify** — each
stage in its own Oban worker, passing through jobs and context APIs, never
reaching into another stage's internals.

## The pipeline

```
SchedulerWorker    queue :scheduler     every minute — a thin dispatcher
      │  Scheduling.due_now() → enqueues one RunnerWorker per due schedule
      ▼
RunnerWorker       queue :speedtest     runs the TestRunner impl, inserts a Measurement
      │  → broadcast {:result, measurement} → enqueue HealthWorker
      ▼
HealthWorker       queue :default       evaluates health, mutates streak/escalation (atomic)
      │  → broadcast {:health, id, transition} → enqueue NotificationWorker
      ▼
NotificationWorker queue :notifications event → policy → template → channel fan-out

CleanupWorker      queue :default       daily 03:00 — prunes beyond retention_days
```

- **SchedulerWorker** owns no cron parsing and no health state — it asks
  `Scheduling.due_now()` and enqueues whatever's due. A malformed cron on one row
  is logged and skipped; it can't stall the per-minute queue.
- **RunnerWorker** is the only thing that touches a test binary. It resolves the
  runner by `test_type` from a registry, so a new test backend is one behaviour
  implementation plus one registry entry — no branch in the worker.
- **HealthWorker** is the sole author of health `Event`s and the sole mutator of
  breach streaks and escalation level (compare-and-set `update_all`, never
  get→change→update).
- **NotificationWorker** fans out through four layers and decides *whether* to
  notify before it ever touches the database.

The cron schedule (`{"* * * * *", SchedulerWorker}`, plus the daily cleanup) and
the four queues live in `config/config.exs`.

## Domains

DB access is routed exclusively through contexts — `Repo` and `import Ecto.Query`
live only inside these files:

- **`Baudflow.Measurements`** — the schema, JIT health, baselines, buckets, SLA
  compliance, retention pruning, and server discovery.
- **`Baudflow.Runs`** — test-run records (success / failure / timeout).
- **`Baudflow.Scheduling`** — schedules, cron matching, atomic escalation, and
  threshold resolution.
- **`Baudflow.Settings`** — typed runtime configuration with safe fallbacks.
- **`Baudflow.Health`** — pure health evaluation (no database access).
- **`Baudflow.Notifications`** — `Event`, `Policy`, `Template`, `Channel`, and
  the `Ntfy` / `Webhook` channel implementations.

## Real-time layer

LiveViews subscribe to a single PubSub topic, `"measurements"`. Events have
stable shapes, and a terminal event is emitted for every outcome so the UI never
waits on a timer:

- `{:result, measurement}` — a run finished (Ookla or ping).
- `{:speedtest_progress, phase, data}` — per-phase Ookla NDJSON (download / upload
  bandwidth).
- `{:ping_progress, data}` — per-sample ping (cumulative avg / jitter / loss).
- `{:health, id, transition}` — a health state change.
- `{:test_failed, reason}` — a terminal failure.

A LiveView that subscribes to the topic must no-op **every** one of these shapes
— not just the ones it renders — or an unhandled broadcast crashes the view.

Throughput is always displayed in **bits/sec**. The raw `bandwidth` field is
bytes/sec and storage-only; it's never rendered as a rate.

## Endpoints

- `GET /health` — `{"status":"ok"}`, for uptime monitors.
- `GET /metrics` — Prometheus text format; `baudflow_*` gauges, `NaN` for any
  value without a current reading. See
  [Prometheus metrics](../prometheus-metrics/).
