---
title: FAQ
description: "Answers to the common questions about baudflow: hosting, data retention, databases, auth, licensing, and how it compares to speedtest-tracker."
section: Resources
order: 40
---

### Self-hosted versus a hosted speed-test service?

A hosted service tests from its own servers, on its schedule, and keeps your
data. baudflow tests from your network, on your schedule, and the data never
leaves your machine — it is yours to chart, export, and scrape.

### Can baudflow prove my ISP isn't delivering the speed I pay for?

Yes. baudflow compares every test against the promised speed you configure and
rolls the results into an SLA percentage ("delivered 91.3% of promised speed
this month"), breach streaks, and a calendar heatmap of when your connection
fell short. Because it stores the full raw result of every test and never
backfills, the record is auditable from day one: export the chart, scrape
`/metrics` into Grafana, or screenshot the heatmap. See
[Internet speed SLA](../internet-speed-sla/).

### How does baudflow compare to speedtest-tracker?

speedtest-tracker is the mature incumbent: PHP/Laravel, broad Apprise
notifications, SQLite/MySQL/Postgres support, and a multi-language UI. baudflow
is a newer Elixir/Phoenix alternative focused on a live real-time dashboard, a
first-class continuous ping runner, SLA tracking against your promised speed,
and adaptive schedules. See the [full comparison](../comparison/).

### What do I need to run it?

Docker and a Postgres database — the Ookla CLI is bundled into the image. From
source you need Elixir 1.20+, OTP 29+, Postgres, and the Ookla CLI on your
`$PATH`. See [Getting started](../getting-started/).

### Why PostgreSQL only?

baudflow leans on Postgres for typed columns, JSON storage of raw results, and
window queries for baselines and SLA. See
[Deployment → Why PostgreSQL?](../deployment/#why-postgresql).

### Is there a login?

No. baudflow is single-user by default and assumes it sits behind your own
reverse proxy or auth proxy. Auth is on the roadmap. See
[Deployment → Security & access](../deployment/#security--access).

### Does the ping runner use ICMP?

No. It measures TCP-handshake RTT by opening connections to `host:port` at a
fixed cadence, so it needs no binary and no `CAP_NET_RAW` and runs unprivileged
under a locked-down security context. See [Ping](../ping/).

### How is the Ookla CLI licensed?

The Ookla Speedtest CLI is a third-party binary bundled into the image for
convenience; you accept Ookla's license terms by using it. baudflow itself is
AGPL-3.0. See [Getting started](../getting-started/).

### How long is data kept?

Measurements are pruned daily at 03:00 beyond `retention_days` (default 365).
The full raw JSON is retained for each measurement until it is pruned. See
[Configuration reference](../configuration-reference/).

### Can I get baudflow into Grafana?

Yes. `GET /metrics` exposes the `baudflow_*` gauges in Prometheus text format;
point a scrape job at it and build panels or Alertmanager rules like any
exporter. There is also an embeddable heatmap for dashboards that take iframes.
See [Prometheus metrics](../prometheus-metrics/).

### Does it work on a phone?

The dashboard is responsive and renders in the browser's local timezone, so a
glance from a phone just works. It is a LiveView app, not a native app — there
is nothing to install.

### What is on the roadmap?

Remote agents reporting from multiple locations, auto-grouped incident
timelines with traceroute context, a REST API, and exportable reports. See
[Contributing → Roadmap](../contributing/#roadmap).
