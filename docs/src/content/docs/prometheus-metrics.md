---
title: Prometheus metrics
description: The eight baudflow_* gauges exposed at GET /metrics, in text-exposition format.
section: Reference
order: 30
---

Scrape `GET /metrics` for these gauges. The endpoint is hand-rolled Prometheus
text format with no dependency and no cache. A value with no current reading (a failed
test, or no tests yet) renders as `NaN` so Prometheus doesn't carry a stale value;
`baudflow_health` is omitted entirely when there's no verdict (calibrating, off
mode, failed, or no latest).

The bandwidth gauges reflect the **latest Ookla speed test**; a ping-only
measurement doesn't populate them.

| Metric | Description |
|---|---|
| `baudflow_download_mbps` | Latest download speed (Mbps). |
| `baudflow_upload_mbps` | Latest upload speed (Mbps). |
| `baudflow_ping_latency_ms` | Latest latency (ms). |
| `baudflow_ping_jitter_ms` | Latest jitter (ms). |
| `baudflow_packet_loss` | Latest packet loss (raw Ookla value). |
| `baudflow_health` | `1` if the latest test is healthy, `0` if unhealthy. Omitted when there's no verdict. |
| `baudflow_measurements_total` | Total retained measurements. |
| `baudflow_uptime_percentage` | Percentage of tests over the window that were healthy. |

## Scraping

```yaml
scrape_configs:
  - job_name: baudflow
    static_configs:
      - targets: ['baudflow:4000']
```

Point a Grafana panel or an Alertmanager rule at it and your homelab observability
stack picks baudflow up like any other exporter.
