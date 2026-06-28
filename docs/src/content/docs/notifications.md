---
title: Notifications
description: The four-layer alert pipeline (event, policy, template, channel), with ntfy and webhooks.
section: Guides
order: 50
---

Alerts run through a four-layer pipeline, each layer one concern:

```
event → policy (notify?) → template (render) → channel (send)
```

`NotificationWorker` orchestrates it: it builds the event, asks the policy whether
to notify, and only then loads the measurement and fans out. Adding a channel is
one behaviour implementation and one `Template.render/1` line, not a branch in
the worker.

## Events

Health transitions become typed events: `:breach`, `:recovered`, `:failed` (a test
that errored), and `:healthy`. They're constructed in exactly one place
(`HealthWorker`) and carry a snapshot of the streak.

## Policy

`Policy.notify?/2` is pure. It reads only the event and a small config map,
never the database. It's what keeps alert fatigue down:

- **`:breach`** fires **exactly once**, when the streak first reaches
  `breach_notify_streak`. A breach that climbs 1, 2, … N alerts only at N, never
  again, until it recovers and re-breaches. (Default `breach_notify_streak` is 1,
  so you alert on the first breach.)
- **`:recovered`** and **`:failed`** fire on their transitions.
- **`:healthy`** never fires.

## Channels

Two ship out of the box.

### ntfy

Posts to a self-hosted or hosted [ntfy.sh](https://ntfy.sh) topic. It's wired
through application env (deploy wiring, not a per-user setting):

```elixir
config :baudflow,
  ntfy_url: "http://ntfy-svc",
  ntfy_topic: "baudflow"
```

Messages arrive with the title **Baudflow Alert** and priority **high**.

### Webhook

POSTs a JSON payload to any URL: Home Assistant, Grafana, n8n, or a custom
endpoint. Configure it on the **Settings** page:

- **`webhook_url`**: the endpoint. **Blank disables the channel** (one "off"
  representation, no separate enable flag).
- **`webhook_template`**: a custom JSON body (EEx). Blank means use the built-in
  default; a malformed template falls back to the default rather than crashing the
  queue.

A hung endpoint never holds a worker slot. Both channels post with hard connect
and receive timeouts, and a failure is logged, never raised.

## Adding a channel

Implement the `Channel` behaviour (`send/1`), add a `Template.render(:your_channel)`
line to the fan-out, and a default template. Your channel owns its own transport
config and enable gate; the worker never branches on it.
