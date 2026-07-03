---
title: Configuration reference
description: Every Settings key, its default, and what it controls.
section: Reference
order: 10
---

Runtime settings live in the `settings` table and are edited on the **Settings**
page (`/settings`). Every key has a default; values are stored as strings and read
back as typed values with a safe fallback, so a bad value never crashes a queue.

## Servers

| Key | Default | Type | Purpose |
|---|---|---|---|
| `server_id` | _(empty)_ | int | Pin every speed test to one Ookla server. |
| `preferred_servers` | _(empty)_ | int list | Prefer these server IDs when selecting. |
| `blocked_servers` | _(empty)_ | int list | Exclude these server IDs from selection. |

## Dashboard & retention

| Key | Default | Type | Purpose |
|---|---|---|---|
| `dashboard_points` | `500` | int | Points plotted on the history charts. |
| `retention_days` | `365` | int | Measurements older than this are pruned daily at 03:00. |

## Health thresholds

| Key | Default | Type | Purpose |
|---|---|---|---|
| `threshold_mode` | `auto` | enum | `auto` \| `absolute` \| `off`. See [Health](../internet-speed-sla/). |
| `threshold_ratio` | `0.7` | float | Auto-mode breach factor (speed < ratio×median; ping > median/ratio). |
| `threshold_download` | `0` | float | Absolute-mode download floor (Mbps). `0` = unset. |
| `threshold_upload` | `0` | float | Absolute-mode upload floor (Mbps). `0` = unset. |
| `threshold_ping` | `0` | float | Absolute-mode ping ceiling (ms). `0` = unset. |

## Ping

| Key | Default | Type | Purpose |
|---|---|---|---|
| `ping_target` | `1.1.1.1` | string | Global ping host. |
| `ping_port` | `443` | int | Global ping TCP port. |
| `ping_duration_seconds` | `10` | int | How long a ping run samples. Longer = stabler. |

## SLA

| Key | Default | Type | Purpose |
|---|---|---|---|
| `promised_download_mbps` | `0` | float | Your plan's download rate, for SLA %. `0` = unset. |
| `promised_upload_mbps` | `0` | float | Your plan's upload rate, for SLA %. `0` = unset. |

## Notifications

| Key | Default | Type | Purpose |
|---|---|---|---|
| `breach_notify_streak` | `1` | int | Consecutive breaches before a breach alert fires. Clamped ≥ 1. |
| `webhook_url` | _(empty)_ | string | Webhook endpoint. Blank disables the channel. |
| `webhook_template` | _(empty)_ | string | Custom EEx JSON body. Blank = built-in default. |

ntfy is wired through application env, not these keys. See
[Notifications](../notifications/).
