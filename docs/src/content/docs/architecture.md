---
title: Architecture
description: The four-stage Oban pipeline, per-domain contexts, PubSub, and health/metrics endpoints.
order: 30
---

Baudflow is a Phoenix 1.8 + LiveView app backed by PostgreSQL and Oban. The work
flows through a four-stage pipeline, each stage in its own worker, triggered by
Oban jobs and never reaching into another stage's internals.

## The pipeline

```
SchedulerWorker   (per minute — thin dispatcher)
      │
      ▼
SpeedtestWorker    (run the Ookla CLI, stream NDJSON, insert a Measurement)
      │
      ├─▶ BenchmarkWorker        (evaluate health)
      └─▶ NotificationWorker     (alert on degradation)

CleanupWorker      (prunes by retention, on its own schedule)
```

- **Decide → Run → Evaluate → Notify.** Each stage is decoupled and passes
  through Oban jobs or context APIs.
- **SpeedtestWorker** owns binary resolution, timeout wrapping, NDJSON parsing,
  and insertion — the speedtest binary is never invoked anywhere else.

## Contexts

DB access is routed exclusively through three contexts, each owning one domain:

- `Baudflow.Measurements` — schema, NDJSON streaming worker, scheduler, cleanup
- `Baudflow.Runs` — test-run tracking
- `Baudflow.Settings` — typed runtime configuration

`Repo` and `import Ecto.Query` live only inside context files.

## Real-time updates

LiveViews subscribe to the single `"measurements"` PubSub topic. Events have
stable shapes, and a terminal event is emitted for every outcome so the UI never
waits on a timer. Throughput is always displayed in **bits/sec** (the raw
`bandwidth` field is bytes/sec and storage-only).

## Endpoints

- `GET /health` — lightweight liveness check for uptime monitors.
- `GET /metrics` — Prometheus text format, hand-rolled with no cache; exposes
  `baudflow_*` gauges (NaN for nil values).
