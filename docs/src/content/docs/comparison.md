---
title: Comparison with speedtest-tracker
description: "An honest, source-cited comparison of baudflow and speedtest-tracker — where each wins and where the gaps are, with links to the upstream issue tracker."
section: Reference
order: 50
article: true
updated: '2026-07-04'
---

Two self-hosted speed test trackers, compared honestly.
[speedtest-tracker](https://github.com/alexjustesen/speedtest-tracker) is the
mature incumbent — PHP/Laravel, around 5,800 GitHub stars, broad Apprise
notifications, SQLite/MySQL/Postgres support, and a multi-language UI. baudflow
is a newer Elixir/Phoenix alternative that ships the features its users have
requested for years: a live real-time dashboard, a first-class continuous ping
runner, SLA tracking against your promised speed, and adaptive schedules.

## TL;DR

Pick **speedtest-tracker** if you want a battle-tested tracker with broad
notification channels (Apprise), a multi-language UI, a built-in login, and your
choice of database (including SQLite). Pick **baudflow** if you want a live,
real-time dashboard, a first-class continuous ping runner, SLA tracking against
your promised speed, adaptive schedules, and you're happy running PostgreSQL.

## Feature matrix

Green = yes · Amber = partial / planned · — = not available. Evidence links
point to the upstream issue tracker.

| Capability | Baudflow | speedtest-tracker | Notes |
|---|---|---|---|
| Automated, scheduled Ookla speed tests | Yes | Yes | |
| Download / upload / ping / packet-loss capture | Yes | Yes | |
| Full historical results + charts | Yes | Yes | |
| Live, real-time test streaming (oscilloscope) | Yes | — | ST: open request [#2035](https://github.com/alexjustesen/speedtest-tracker/issues/2035) |
| First-class continuous ping runner + live console | Yes | — | ST: top open request [#826](https://github.com/alexjustesen/speedtest-tracker/issues/826) (13👍) |
| Adaptive cadence (auto-escalate during a breach) | Yes | — | ST: related [#1815](https://github.com/alexjustesen/speedtest-tracker/issues/1815) |
| GitHub-style health heatmap | Yes | — | |
| SLA compliance vs. your promised speed | Yes | — | ST: open request [#1943](https://github.com/alexjustesen/speedtest-tracker/issues/1943) |
| Multi-schedule / per-target cron | Yes | Partial | ST: one schedule; multi-server requested [#2586](https://github.com/alexjustesen/speedtest-tracker/issues/2586) |
| Breach-streak alert gating (notify once) | Yes | Partial | ST: threshold alerts; "notify once" requested [#2731](https://github.com/alexjustesen/speedtest-tracker/issues/2731) |
| Per-channel notification templates | Yes | — | ST: template engine requested [#2105](https://github.com/alexjustesen/speedtest-tracker/issues/2105) |
| Notification channels (out of the box) | Partial | Yes | Baudflow: ntfy + webhooks · ST: dozens via Apprise + Telegram |
| Prometheus /metrics endpoint | Yes | Yes | |
| Embeddable widgets (heatmap iframe) | Yes | — | |
| Built-in auth / login | — | Yes | Baudflow: single-user, behind your reverse proxy |
| Multi-language UI | — | Yes | ST: community translations via Crowdin |
| Database | Partial | Yes | Baudflow: PostgreSQL only · ST: SQLite, MySQL, or Postgres |
| Image ecosystem | Partial | Yes | Baudflow: multi-arch Docker · ST: LinuxServer.io (Synology, Unraid, NAS) |
| License | Yes | Yes | Baudflow: AGPL-3.0 · ST: MIT |
| Stack | Yes | Yes | Baudflow: Elixir / Phoenix LiveView + Oban · ST: PHP / Laravel + Filament |

## Where speedtest-tracker wins

- **Broad notifications.** Dozens of channels through Apprise plus native Telegram; baudflow ships ntfy and webhooks.
- **Database flexibility.** SQLite, MySQL, or Postgres; SQLite means no separate database to run. baudflow is Postgres-only.
- **Multi-language UI.** Community translations via Crowdin. baudflow is English-only today.
- **Built-in auth.** Login and OIDC out of the box. baudflow is single-user by design and expects a reverse proxy.
- **Ecosystem polish.** The LinuxServer.io image lands on Synology, Unraid, and consumer NAS gear with one click.
- **Maturity.** ~5,800 stars and years of production use across a large install base.

## Where baudflow pulls ahead

- **Live, real-time tests.** Every test streams over PubSub as it runs, with no spinner or refresh ([ST #2035](https://github.com/alexjustesen/speedtest-tracker/issues/2035)).
- **A real ping runner.** Continuous TCP-connect ping with its own live console, the single most upvoted open request on speedtest-tracker ([ST #826](https://github.com/alexjustesen/speedtest-tracker/issues/826)).
- **SLA evidence.** "Delivered 91.3% of promised speed this month" — the number you can take to your ISP ([ST #1943](https://github.com/alexjustesen/speedtest-tracker/issues/1943)).
- **Adaptive cadence.** A breached schedule runs faster until it recovers, then slows back down ([ST #1815](https://github.com/alexjustesen/speedtest-tracker/issues/1815)).
- **Smart alerts.** A breach fires once when the streak is reached, not on every re-check ([ST #2731](https://github.com/alexjustesen/speedtest-tracker/issues/2731)), with a per-channel template pipeline ([ST #2105](https://github.com/alexjustesen/speedtest-tracker/issues/2105)).
- **Health heatmap.** A GitHub-style calendar wall that makes evening congestion jump out.

## Same goal, different priorities

Both projects do the same core job: run Ookla speed tests on a schedule and keep
the results so you can watch your connection over time. They are not in a race
to be "better" in the abstract; they optimize for different people.

speedtest-tracker prioritizes reach and familiarity: more notification channels,
more databases, more languages, a login screen, and a NAS-ready image. If you
want a dependable tracker that fits into an existing homelab with the least
friction, it is a safe, well-supported choice.

baudflow prioritizes depth and immediacy: a live dashboard you watch instead of
wait on, ping treated as a first-class citizen, health and SLA derived from your
own baselines, and an alert pipeline that filters noise before it reaches you. It
asks for PostgreSQL in return, and it is younger: smaller community, fewer
channels, no login yet.

If your pain is "I have no proof to show my ISP," "my calls lag but my speed
test says I'm fine," or "I get a notification every five minutes during an
outage," baudflow is built for exactly that. If your pain is "I want this
running on my Synology in five minutes with Telegram alerts," speedtest-tracker
will get you there faster today.

## Switching & migration

**Is baudflow a fork of speedtest-tracker?**

No. They are entirely separate codebases. speedtest-tracker is PHP/Laravel;
baudflow is Elixir/Phoenix LiveView with Oban and PostgreSQL. Different
language, framework, and architecture. baudflow is an independent project
chasing the same goal from a different starting point.

**Can I migrate my speedtest-tracker history into baudflow?**

Not yet. baudflow is a fresh install with no importer today. If your existing
history matters, run both side by side until baudflow accumulates its own
record. A migration path is plausible later, but it is not promised.

**Which is lighter to run?**

speedtest-tracker has the lower-friction floor: it can run on SQLite with no
separate database process. baudflow needs PostgreSQL, because it leans on JSON
columns and window queries for baselines and SLA. Both are a single container
plus a database.

**Does baudflow support as many notification channels?**

No. baudflow ships ntfy and webhooks; speedtest-tracker covers dozens of
services through Apprise plus native Telegram. baudflow's notification channels
are behaviour implementations, so adding one is a self-contained module, but
today the built-in count is lower.

**Which should I pick?**

Pick speedtest-tracker if you want a battle-tested tracker with broad
notification channels, a multi-language UI, a built-in login, and your choice of
database. Pick baudflow if you want a live, real-time dashboard, a first-class
continuous ping runner, SLA tracking against your promised speed, adaptive
schedules, and you are happy running PostgreSQL.
