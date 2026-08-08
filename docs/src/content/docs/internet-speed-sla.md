---
title: Speed SLA
description: Internet speed SLA is the share of tests that hit your promised speed. How baudflow derives it on the fly, the auto/absolute/off threshold modes, breach streaks, and just-in-time health verdicts.
section: Operate
order: 30
article: true
updated: "2026-07-03"
---

Baudflow derives an internet speed SLA from completed speed-test results. For
each result it judges download and upload against a threshold, then rolls met
and breached results into a percentage over a rolling window.

![The baudflow dashboard showing internet speed SLA compliance alongside the live readout, health heatmap, and speed history.](../../assets/screenshots/dashboard.png)

## How the number is computed

Each test in the window is classified met or breached against the Mbps figures on
its schedule. A schedule can set `promised_download_mbps` /
`promised_upload_mbps` per row; rows that don't override fall back to the global
default through one reader, `Scheduling.thresholds_for/1`. The percentage is
`meeting / total` over the window. A test counts as met only when it meets every
configured promise; a ping result with no bandwidth, or a failed test with no
download number, is excluded.

Set the promised speeds on the [schedule row](../schedules/).

## Modes: auto, absolute, or off

The threshold mode governs the per-result health verdict — what the heatmap, the
per-row badges, and the `/metrics` health and uptime gauges show. It does not
change the promised-speed percentage above, which compares to `promised_*_mbps`
whenever those are set.

- **`auto`** *(default)*: judges each value against the connection's own rolling-median baseline. Download or upload breaches below `ratio × median`; ping breaches above `median / ratio`. While there isn't enough history the baseline is `:insufficient` and no verdict is produced. Zero config; a stable line stays quiet.
- **`absolute`**: a hard line in Mbps and ms. Set it to your plan tier and "met" means "hit the speed you pay for." Download and upload must meet or exceed the threshold; ping must be at or below it.
- **`off`**: disables verdicts. The heatmap and badges show no healthy or breach call, and the `baudflow_uptime_percentage` gauge counts no healthy rows. Raw throughput is still stored and charted.

A check runs only when it has both a threshold and a value: a ping result carries
no bandwidth, so its download and upload checks are skipped, never an error.

## Why changing a threshold doesn't rewrite history

The SLA is never written down. Health is a pure function of a measurement and its
thresholds (`Baudflow.Health`), with no database access of its own, and the
verdict is never stored: every reader — dashboard hero, heatmap, `/metrics`,
history filter, result detail — derives it just-in-time on the next read. Every
Ookla result is stored in full (download, upload, ping, jitter, packet loss,
server, provider), and the percentage, breach streaks, and heatmap are computed
from that store on demand. Change your promised speed or switch from `auto` to
`absolute` and every past window re-derives under the new rule the next time you
look. Nothing is backfilled; nothing is lost.

## Breach streaks and transitions

`Baudflow.Health.evaluate/3` also produces a transition against the schedule's
prior breach streak:

- `:breach`. The first test that fails after a healthy run.
- `:recovered`. The first healthy test after a breach.
- `:healthy`. Steady healthy.
- `nil`. Still breaching, or no verdict.

The streak (`breach_streak`) and escalation level live on the schedule row and
are mutated only by `Scheduling`, atomically. That transition drives both
[adaptive cadence](../schedules/) and [notifications](../notifications/).

## Reading the number

The in-app SLA compliance is judged against your **promised** speeds
(`promised_download_mbps` / `promised_upload_mbps`). That is distinct from the
`baudflow_uptime_percentage` gauge at [`/metrics`](../prometheus-metrics/), which
reflects threshold-based health. The two agree only when the mode is `absolute`
and the thresholds equal your promised speeds.

For scraping `/metrics`, embedding the heatmap, or taking the record to a
provider, see [Monitor ISP speed](../../articles/monitoring-your-isp/).
