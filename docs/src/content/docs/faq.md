---
title: FAQ
description: Short answers to common questions about running baudflow. For anything covered in depth elsewhere, the answer points you there.
section: Project
order: 30
---

### Self-hosted versus a hosted speed test?

A hosted service tests from its own servers, on its schedule, and keeps your
data. baudflow tests from your network, on your schedule, and the data stays on
your machine.

### What do I need to run it?

Docker and a Postgres database — the Ookla CLI is bundled into the image. From
source you also need Elixir 1.20+ and Erlang/OTP 29+. See
[Getting started](../getting-started/).

### Why PostgreSQL only?

Typed columns, JSON storage of raw results, and window queries for baselines and
SLA. No SQLite or MySQL mode is planned. See
[Deployment](../deployment/#why-postgresql).

### Is there a login?

No. baudflow is single-user and assumes a reverse proxy or auth proxy in front.
Auth is on the roadmap. See
[Deployment](../deployment/#security--access).

### How is the Ookla CLI licensed?

It is a third-party binary bundled into the image for convenience; using it
accepts Ookla's license terms. baudflow itself is AGPL-3.0. See
[Getting started](../getting-started/).

### Does it work on a phone?

Yes. The dashboard is responsive and renders in the browser's local timezone.
It is a web app, not a native app.

### How does it compare to speedtest-tracker?

See the [comparison](../../articles/baudflow-vs-speedtest-tracker/). The short version: speedtest-tracker is
the mature, broader incumbent (Apprise, SQLite, i18n); baudflow trades that
breadth for a live dashboard, continuous ping, and SLA tracking.
