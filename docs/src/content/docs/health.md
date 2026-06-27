---
title: Health & thresholds
description: Auto, absolute, and off modes; breach streaks; just-in-time verdicts; and SLA compliance.
section: Guides
order: 40
---

Health is a pure function of a measurement and its thresholds, evaluated by
`Baudflow.Health`. It has no database access of its own, and the verdict is **never
stored** — every reader (dashboard hero, heatmap, `/metrics`, history filter,
result detail) derives it just-in-time on the next read. Change the mode or ratio
and every view re-derives instantly, with no backfill.

## Modes

Resolved per-schedule → global, through one reader (`Scheduling.thresholds_for/1`):

- **`auto`** *(default)* — judges each value against the connection's own rolling
  median baseline. A test breaches when download or upload falls below
  `ratio × median`, or when ping exceeds `median / ratio`. While there isn't enough
  history the baseline is `:insufficient` and no verdict is produced — the
  zero-config default that calibrates itself.
- **`absolute`** — against fixed Mbps / ms values. Download/upload must meet or
  exceed their threshold; ping must be at or below its threshold.
- **`off`** — no verdict at all.

A check runs only when it has both a threshold and a value: a ping result carries
no bandwidth, so its download/upload checks are simply skipped (never an error).

## Breach streaks and transitions

`Health.evaluate/3` also produces a **transition** against the schedule's prior
breach streak:

- `:breach` — the first test that fails after a healthy run.
- `:recovered` — the first healthy test after a breach.
- `:healthy` — steady healthy.
- `nil` — still breaching, or no verdict.

The streak (`breach_streak`) and escalation level live on the schedule row and are
mutated only by `Scheduling`, atomically. That transition is what drives both
[adaptive cadence](../schedules/) and [notifications](../notifications/).

## SLA compliance

The dashboard's SLA card turns raw Mbps into an accountability number: the
percentage of tests in the window that met your **promised** speeds
(`promised_download_mbps` / `promised_upload_mbps`). Set those to your plan's
rates and the card reads "delivered promised speed N% of the month."
