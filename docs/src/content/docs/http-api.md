---
title: HTTP API
description: "The lightweight HTTP surface: /health, /metrics, and the embeddable heatmap."
section: Integrate
order: 20
---

Baudflow is a LiveView app, so most interaction is the UI. The plain-HTTP surface
is deliberately tiny. Three endpoints, none behind a login:

| Method | Path | Returns | Consumer |
|---|---|---|---|
| `GET` | `/health` | `{"status":"ok"}` JSON | Uptime monitor, liveness probe |
| `GET` | `/metrics` | Prometheus text (0.0.4) | Prometheus scraper |
| `GET` | `/heatmap/embed` | HTML, chrome-less heatmap | iframe dashboard |

## `GET /health`

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"status":"ok"}
```

Liveness probe. No database query, no session, no auth.

```bash
curl https://baudflow.example/health
```

Routed through the `:api` pipeline, which only sets `accepts ["json"]`. The
browser plugs (`fetch_session`, `protect_from_forgery`) do not run, so a plain
HTTP GET works from any monitor. Point Uptime Kuma or a Kubernetes
liveness/readiness probe at it.

## `GET /metrics`

```http
HTTP/1.1 200 OK
Content-Type: text/plain; version=0.0.4; charset=utf-8

# HELP baudflow_download_mbps Latest speed test (Ookla) download speed in Mbps.
# TYPE baudflow_download_mbps gauge
baudflow_download_mbps 342.18
# HELP baudflow_upload_mbps Latest speed test (Ookla) upload speed in Mbps.
# TYPE baudflow_upload_mbps gauge
baudflow_upload_mbps 28.91
# HELP baudflow_health 1 if the latest speed test is healthy, 0 if unhealthy.
# TYPE baudflow_health gauge
baudflow_health 1
...
```

Prometheus text-exposition format. Eight `baudflow_*` gauges reflect the latest
Ookla test; see [Prometheus](../prometheus-metrics/) for the full list. A value
with no current reading renders as `NaN`, and `baudflow_health` is omitted
entirely when there is no verdict.

No pipeline at all. The endpoint bypasses the `:api` JSON content negotiation
and the `:browser` session/CSRF plugs, so a scraper hits it with no headers and
gets text back.

```yaml
scrape_configs:
  - job_name: baudflow
    static_configs:
      - targets: ['baudflow:4000']
```

## `GET /heatmap/embed`

```html
<iframe src="https://baudflow.example/heatmap/embed"
        style="border:0;width:100%;height:320px"></iframe>
```

Chrome-less heatmap tile for iframe embedding — Home Assistant, Grafana, a status
page. No nav, no flash toasts, just the calendar and its legend. The full
all-months grid (with a link back here) lives at `/heatmap`.

Current month only. The view reads `Date.utc_today()` on load and renders the
month containing today; there are no query parameters for a time range. It draws
the latest state once and is read-only — reload the iframe to refresh. Only
Ookla results feed the calendar.

No auth. The page is a LiveView on the browser pipeline, so the GET returns HTML
and the embedded CSRF token lets the websocket connect without a login.
