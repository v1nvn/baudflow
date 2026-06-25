---
title: Configuration
description: Tune cron schedules, servers, retention, thresholds, and notifications from the Settings page.
order: 20
---

All runtime configuration lives behind the **Settings** page (`/settings`). It is
a key-value store that holds strings and returns typed values with a safe
fallback, so a bad value never crashes a queue. Every key ships with a default.

## Schedule

Scheduling is **data, not config keys**: each schedule row owns its own
escalation. The scheduler is a thin per-minute dispatcher that enqueues a
speed-test job according to the configured cron. Edit the cron expression to
change how often tests run.

## Servers

- **Preferred servers** — pin tests to specific Ookla servers.
- **Blocked servers** — exclude servers from selection.

Both accept server-id lists and are resolved through a single reader.

## Retention

Set how long measurements are kept. The `CleanupWorker` prunes old rows on a
schedule according to the retention policy.

## Degradation thresholds

Define what counts as "healthy." Thresholds resolve as
**per-row override → global `Settings` fallback**, with one reader
(`thresholds_for/1`) so there is a single source of truth and resolution never
yields `nil`. Register the global default in `Settings.@default_settings`.

## Notification channels

Notifications are **behaviour implementations, not branches in a worker**. The
worker orchestrates; the channel behaviour does the work. Add a new channel by
implementing the behaviour.

## Ping target

A schedule may override the ping target per row; otherwise it falls back to the
global setting:

```
schedule.target_host || Settings.get("ping_target")
```
