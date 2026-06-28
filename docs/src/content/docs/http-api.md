---
title: HTTP endpoints
description: "The lightweight HTTP surface: /health, /metrics, and the embeddable heatmap."
section: Reference
order: 40
---

Baudflow is a LiveView app, so most interaction is the UI. The plain-HTTP surface
is deliberately tiny.

## `GET /health`

```json
{ "status": "ok" }
```

A liveness check for uptime monitors (Uptime Kuma, a Kubernetes probe). No auth,
no meaningful database hit.

## `GET /metrics`

Prometheus text format. See [Prometheus metrics](../prometheus-metrics/). Served
as plain text, bypassing the JSON pipeline and the browser CSRF/session plugs so
scrapers just work.

## `GET /heatmap/embed`

A chrome-less, current-month-only health heatmap for iframe embedding into a
Home Assistant or Grafana dashboard:

```html
<iframe src="https://baudflow.example/heatmap/embed"
        style="border:0;width:100%;height:320px"></iframe>
```
