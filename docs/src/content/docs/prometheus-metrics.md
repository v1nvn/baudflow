---
title: Prometheus
description: The eight baudflow_* gauges exposed at GET /metrics, in text-exposition format.
section: Integrate
order: 10
---

`GET /metrics` returns these eight `baudflow_*` gauges in Prometheus
text-exposition format. The endpoint is hand-rolled — no dependency, no cache.

| Metric | Type | Unit | Description |
|---|---|---|---|
| `baudflow_download_mbps` | gauge | Mbps | Download speed of the latest Ookla test. |
| `baudflow_upload_mbps` | gauge | Mbps | Upload speed of the latest Ookla test. |
| `baudflow_ping_latency_ms` | gauge | ms | Latency of the latest Ookla test. |
| `baudflow_ping_jitter_ms` | gauge | ms | Jitter of the latest Ookla test. |
| `baudflow_packet_loss` | gauge | raw (Ookla) | Packet loss of the latest Ookla test, passed through unmodified. |
| `baudflow_health` | gauge | 1 / 0 | `1` if the latest Ookla test is healthy, `0` if breached. Omitted when there is no verdict. |
| `baudflow_measurements_total` | gauge | count | Number of retained measurements. |
| `baudflow_uptime_percentage` | gauge | % | Share of tests over the window that were healthy. |

## Semantics

- **No reading renders `NaN`.** A gauge whose latest value is missing — a failed test, or no test yet — renders `NaN`, so Prometheus never carries a stale reading.
- **No verdict omits `baudflow_health`.** It is dropped from the payload entirely when there is no verdict: calibrating, off mode, a failed test, or no latest test. The other seven gauges always render.
- **Latest means latest Ookla test.** The five `latest_*` gauges and `baudflow_health` are derived from the most recent `test_type == "ookla"` row, not the most recent row of any type. A ping-only measurement never becomes `latest`, so it never populates the bandwidth gauges. It still counts toward `baudflow_measurements_total` and `baudflow_uptime_percentage`.
- **`_total` is a gauge, not a counter.** `baudflow_measurements_total` decreases when `CleanupWorker` prunes old rows, so it is exposed as a gauge despite the `_total` suffix. Do not apply `rate()` to it.
- **No labels.** None of the eight gauges carry labels; each is a single unconfigured series.

## Scraping

```yaml
scrape_configs:
  - job_name: baudflow
    static_configs:
      - targets: ['baudflow:4000']
```

Point a Grafana panel or an Alertmanager rule at it and your homelab observability
stack picks baudflow up like any other exporter.
