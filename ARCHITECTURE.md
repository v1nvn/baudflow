# Architecture

An as-built map of baudflow: what the system is made of, how the pieces fit, and
the contracts that keep it additive. This documents **what exists**, not what's
planned - for scope boundaries, see [Deferred](#deferred--not-built) at the end.

`CLAUDE.md` (the checked-in AGENTS.md) is the rulebook; this is the map of the
thing those rules produced. When the two disagree, the code wins and one of them
is stale.

---

## At a glance

Phoenix 1.8 + LiveView, Oban, Postgres. A per-minute cron dispatches due test
schedules; each runs an Ookla speed test or a TCP ping, inserts a `Measurement`,
evaluates health, and fans notifications out on a threshold breach or recovery.

```
SchedulerWorker (every minute)
  → Scheduling.due_now/0            (which schedules match this minute)
  → RunnerWorker (per due schedule) (run the TestRunner impl → insert Measurement)
    → HealthWorker                  (JIT verdict → atomic streak/escalation → event)
      → NotificationWorker          (policy → template → channel fan-out)
```

All four stages are **decoupled Oban workers** that speak only through each
other's public context API and enqueued jobs - never through another's internals.

---

## The pipeline

Four queues (all concurrency `1`), configured once in `config/config.exs`:

| Queue           | Worker                       | Cadence / trigger        | max_attempts |
|-----------------|------------------------------|--------------------------|--------------|
| `:scheduler`    | `Scheduling.SchedulerWorker` | cron `* * * * *`         | 1            |
| `:speedtest`    | `TestRunners.RunnerWorker`   | enqueued by the scheduler| 2            |
| `:default`      | `Health.HealthWorker`        | enqueued by the runner   | 1            |
| `:notifications`| `Notifications.NotificationWorker` | enqueued by health | 3            |

`Measurements.CleanupWorker` prunes rows older than `retention_days` on cron
`0 3 * * *`. Oban runs in `testing: :manual` under `MIX_ENV=test` - tests enqueue
and assert, nothing fires on its own.

### 1. Decide - `Scheduling.SchedulerWorker`

Thin dispatcher. Owns no cron parsing and no health state. Each minute it asks
`Scheduling.due_now/0` for the enabled schedules whose **active** cron matches
now, and enqueues one `RunnerWorker` job per due schedule. Concurrency safety is
Oban uniqueness on `[:worker, :args]` (1h) keyed by a `scheduled_for` timestamp
truncated to the minute - at most one test per minute per schedule even if the
dispatcher races.

### 2. Run - `TestRunners.RunnerWorker`

Owns the pipeline body: resolve the `TestRunner` impl by `test_type`, run it,
parse the result, insert the `Measurement`, record the `Run`, broadcast the
terminal event, and enqueue `HealthWorker`. The worker **never invokes the test
binary directly** - that lives in the impl. Every failure path (timeout,
non-zero CLI exit, error, raised exception) stamps a `failed: true` measurement
via `Measurements.record_failure/1` and broadcasts it, so an outage is an
explicit marker on the chart instead of a silent gap - then enqueues
`HealthWorker` so the failure becomes a `:failed` notification.

### 3. Evaluate - `Health.HealthWorker`

The only module that constructs an `Event` and the only mutator of streak /
escalation state. It derives the verdict, persists the per-check `benchmarks`
detail (not the verdict - see [JIT health](#health-is-derived-just-in-time)),
mutates the schedule's streak / escalation **atomically**, and on a transition
enqueues `NotificationWorker` and broadcasts `{:health, id, transition}`. A
failed measurement short-circuits to a `:failed` event - no threshold evaluation,
no streak / escalation mutation (a CLI failure is neither a breach nor a
recovery).

### 4. Notify - `Notifications.NotificationWorker`

Runs the four-layer pipeline: `event → policy (notify?) → template (render) →
channel (fan-out)`. The policy is pure; the worker reads `Settings` into the
config it hands the policy, and only when the policy says notify does it load the
measurement, build a `Payload`, and fan out. Rendering is consolidated in the
`Template` module; each channel owns its transport config and enable gate, so
the worker never branches on channel logic.

---

## Cross-cutting contracts

These are the seams every feature codes against. A new feature adds a row, a
context function, or a behaviour impl - never a branch in an existing worker.

### Closed event vocabulary

`Notifications.Event`, `kind ∈ :healthy | :breach | :recovered | :failed`, plus a
`streak` snapshot (the breach streak at construction; `nil` for non-breach
events). **Constructed only in `Health`**; every other module reads events.
Serialized to Oban args by `HealthWorker` and deserialized via
`Event.from_args/1`, a closed string→atom map - never `String.to_atom/1` on
stored input.

### One state owner

The **schedule row** owns escalation state: `breach_streak` and
`escalation_level`. `Health` is the only code that mutates them, through atomic
`Scheduling` functions - never get→change→update, which would race across
concurrent Oban jobs:

- `escalate/1`, `deescalate/1` - compare-and-set `Repo.update_all`
  (`where: id == ^id and escalation_level == ^expected`); a concurrent job that
  already moved the level yields `{:ok, 0}`.
- `increment_breach_streak/1`, `reset_streak/1` - atomic `inc`/`set` that return
  the **resulting streak value**, so `HealthWorker` can snapshot it into the
  breach event without a second read across the async boundary.

`escalation_level` drives the **active cadence**: when `> 0` and the schedule has
an `escalated_cron`, `Scheduling.active_cron/1` returns it (else the base
`cron`). That single reader is what `due_now/0`, `next_run_at/1`, `next_run/0`,
and the schedules table all consume - so adaptive testing is a switch in one
place, not a parallel state path. Without an `escalated_cron`, the level is
maintained but inert.

### One threshold reader

`Scheduling.thresholds_for/1` resolves a schedule's thresholds into
`%{mode, ratio, download, upload, ping}`: the schedule's own value if set, else
the global `Settings` fallback, using an **explicit nil-check** so a real `false`
overrides instead of falling through (the `||` trap). `global_thresholds/0` is
the same reader for cross-schedule consumers (dashboard, `/metrics`, heatmap)
that have no single schedule to read.

`mode` is a closed, changeset-validated enum:

| Mode        | Verdict rule                                                                                  |
|-------------|-----------------------------------------------------------------------------------------------|
| `:auto`     | Each value vs the connection's own rolling-median baseline (the zero-config default).         |
| `:absolute` | Each value vs the fixed Mbps / ms thresholds.                                                 |
| `:off`      | No verdict - every row is `:unknown`.                                                         |

In `:auto`, a test breaches when download/upload fall below `ratio × median`, or
when ping rises above `median / ratio` (`ratio` from `Settings`, default `0.7`).

### Health is derived just-in-time

The verdict is **never stored**. `Measurements.healthy` was a stored boolean in
v1; the JIT migration dropped it and replaced `threshold_enabled` with
`threshold_mode` (one value, one meaning - the boolean plus a new "auto" concept
would have been a compensating flag). What *is* persisted:

- `failed` - a fact, not a verdict. A failed test is always `:failed`.
- `benchmarks` - the per-check detail map (`%{download: %{passed, value, threshold, unit}, …}`), saved so the result page and notification templates can render it.

`Health.verdict/3` / `Health.evaluate/3` derive `{healthy, benchmarks}` on read,
and every consumer funnels through one private `evaluate/3` that maps the result
to a `state ∈ :healthy | :breach | :failed | :unknown`:

- `Measurements.health/1`, `health_state/1` - single row (dashboard hero, result detail).
- `Measurements.health_states/1` - batch `%{id => state}` for the history table.
- `Measurements.health_buckets/1` - per-UTC-day counts for the heatmap and `/metrics` uptime.
- `Measurements.metrics/1` - the `/metrics` snapshot (latest Ookla, total, 30-day uptime).

Change the mode or ratio and every view re-derives on the next read - no
backfill, no stored column to drift out of sync.

The `:auto` baseline is the rolling median of the prior 7 days for the same
`test_type`, excluding failed and manual rows (`percentile_cont(0.5)`). Below 12
qualifying samples it is `:insufficient` - no verdict while calibrating. The list
consumers compute baselines in-memory with a two-pointer sliding window
(`trailing_baselines/2`) so the full-history heatmap stays O(n), not a rescan per
row.

### The pinning test

`test/baudflow/pipeline_test.exs` asserts the whole flow end to end -
`due_now → RunnerWorker → Measurement(schedule_id/test_type) → Health breach →
atomic streak + escalation → NotificationWorker(event)`. It is the guard that
keeps adaptive testing, the notification policies, and every future additive
feature from re-coupling the stages.

---

## Contexts

Each pipeline stage (and each domain) has its own context that owns its schema
and **all** its DB access. `import Ecto.Query` and `Repo` live only in context
files; `from m in Measurement` never appears elsewhere. The credo rule
`BanRepoOutsideContexts` enforces it.

```
lib/baudflow/
  scheduling/      Schedule schema + due_now/escalate/thresholds_for + SchedulerWorker
  measurements/    Measurement schema + store/aggregate/JIT-health + CleanupWorker + ServerDiscovery
  test_runners/    TestRunner behaviour + Ookla/Ping impls + RunnerWorker
  health/          pure Health evaluation + HealthWorker
  notifications/   Event/Policy/Template/Channel + Ntfy/Webhook + NotificationWorker
  runs/            Run schema + run tracking
  settings/        Setting schema + typed KV store
```

Mutations return `{:error, changeset}`, never bang - a worker logs and continues
(`BanBangRepoCalls`). Each schema has one `changeset/2` as its only construction
path.

---

## Extension seams

Two behaviours make new backends and channels one impl file with zero edits to
workers:

**`TestRunners.TestRunner`** - `run/1`, `parse/1`, `binary_available?/0`,
`timeout_ms/0`. `RunnerWorker` resolves the impl by `test_type` from a single
`@registry`, which is *also* the source for the schedule form's `<select>`
options - add a tuple and both dispatch and the UI pick it up. `BanBinaryInvocationOutsideRunners`
keeps `System.cmd` / `Port.open` inside impls.

- `Ookla` - the Ookla CLI binary, NDJSON progress streaming, `System.cmd` in the impl.
- `Ping` - pure-Elixir TCP-handshake RTT. No binary, no `CAP_NET_RAW`; it opens
  connections to `host:port` at a fixed cadence and measures connect time. A
  target that refuses TCP on the configured port reads as 100% loss, so it
  defaults to `1.1.1.1:443` (`ping_target` / `ping_port` / `ping_duration_seconds`
  settings).

**`Notifications.Channel`** - `send/1`. A channel takes an already-rendered
message and delivers it; rendering is the template layer's job.

- `Ntfy` - POST via app-env URL/topic (deploy wiring); always on.
- `Webhook` - POSTs JSON to a `Settings` URL; **enabled iff the URL is non-blank**
  (one "off" representation, no compensating enable flag). A hung endpoint never
  holds the queue slot (hard `Req` timeouts); a failure is a clean `:error`.

The notification layers, in order: `Event` (what) → `Policy` (notify?) →
`Template` (render) → `Channel` (send). `Policy.notify?/2` is pure - the worker
reads `Settings` into a config map, the policy never touches the DB. `Template`
is one EEx renderer per channel; a bad custom webhook template logs and falls
back to the default - a bad setting never crashes the `:notifications` queue.

---

## Data model

- **`Measurement`** - the raw result is sacred. The full Ookla JSON is stored in
  `raw_result` (GIN-indexed); nothing is dropped when mapping. `:integer` for
  bytes, `:float` for rates; `download_mbps`/`upload_mbps` are derived from
  `bandwidth × 0.000008` (bandwidth is bytes/sec, storage-only - never rendered
  as a rate). `schedule_id` / `test_type` / `failed` were forward-shaped in v2 so
  every writer has a column; `benchmarks` holds the per-check detail. There is no
  stored verdict column.
- **`Schedule`** - `name`, `cron`, `escalated_cron`, `test_type`, `server_id`,
  `target_host`, `enabled`, `escalation_level`, `breach_streak`, `threshold_mode`,
  `download`/`upload`/`ping`. Escalation fields are mutated only through the
  atomic `Scheduling` functions; threshold fields are nullable (`nil` =
  "inherit global"). Deleting a schedule nilifies its measurements' `schedule_id`
  (`on_delete: :nilify_all`) - history is retained.
- **`Run`** - run tracking with error details (success / timeout / failure).
- **`Setting`** - key/value strings.

A fresh install bootstraps two default schedules - "Default" (Ookla) and "Ping" -
both hourly, escalating to 15 min on a breach, idempotent per `test_type`
(`Scheduling.bootstrap/0`, gated off in test).

---

## Settings & config

`Settings` is a string KV store with typed accessors (`get_integer`, `get_float`,
`get_integer_list`, `get_all`, `update_all`) and a safe fallback. Every key is
registered in `Settings.@default_settings` - resolution never yields `nil`, and
there is one source for each default (no second literal in a caller). A bad value
parses to the default; it never crashes a queue. `String.to_integer` /
`to_float` live only here (`BanManualStringCoercion`).

The split: **user-tunable values go through `Settings`**; **deploy wiring goes
through `Application.get_env`** (binary paths, the ntfy URL/topic). The credo
project does not yet ban `Application.get_env` for user values - it's the one
deferred ratchet.

Per-row overrides resolve as **schedule value → global `Settings` fallback** in
one reader: `thresholds_for/1` for thresholds, `schedule.target_host ||
Settings.get("ping_target")` for the ping target. The global default is always
registered in `@default_settings`, so resolution never yields `nil`.

---

## Web layer

```
/                      DashboardLive      (Ookla speed: charts, hero, SLA, heatmap tile, next-test)
/ping                  PingLive           (TCP-RTT ping surface)
/history               HistoryLive        (filter/sort/paginate; JIT per-row badges)
/heatmap               HeatmapLive        (wall grid of monthly calendar tiles)
/heatmap/embed         HeatmapEmbedLive   (chrome-less current month, for iframes)
/runs                  RunsLive
/results/:id           ResultLive
/schedules             SchedulesLive      (CRUD; index/new/edit via push_patch + live_action)
/settings              SettingsLive
/health                HealthController   (JSON; GET only)
/metrics               MetricsController  (Prometheus text/plain; no pipeline)
```

LiveViews subscribe to the single `"measurements"` PubSub topic. Broadcast shapes
include `{:result, measurement}`, `{:test_failed, reason}`, `{:health, id,
transition}`, and the live progress events. **A LiveView that subscribes must
no-op every shape on the topic**, not just the ones it renders - any unhandled
one crashes the LV.

Stateful navigation flows through `push_patch` + URL params in `handle_params`;
charts stream via `push_event`. The dashboard's chart seam is one `:chart_config`
assign and one `chart_data` payload every chart reads, so threshold overlay lines,
failure markers, and future overlays add a field rather than a parallel state
path. The heatmap is a separate consumer - its own `HeatmapMatrix` hook
(`chartjs-chart-matrix`) and `HeatCalendar` component, with colors and labels
single-sourced and shipped to the hook via `data-colors` / `data-labels` so the
legend and tooltips can't drift.

`/metrics` serves Prometheus text exposition (`text/plain; version=0.0.4`) with
no pipeline - it bypasses the `:api` JSON negotiation and the `:browser`
CSRF/session plugs so a scraper's `Accept: text/plain` reads cleanly. Eight
`baudflow_*` gauges; a value with no current reading renders `NaN` so Prometheus
carries no stale value. `/metrics`, `/health`, and `/heatmap/embed` are open
today; they pick up an auth gate if/when auth lands.

Throughput is rendered in **bits/sec everywhere**; `bandwidth` is bytes/sec and
storage-only. Timestamps render browser-local via `<.local_time>` + the
`LocalTime` JS hook - the server can't know the viewer's timezone, so the only
`Calendar.strftime` on a datetime lives inside that component as a no-JS
fallback.

---

## Conventions enforced by the build

The linter is the ratchet, not this doc. Five custom credo rules pin the
invariants (`credo/`):

| Rule                              | Enforces                                                                          |
|-----------------------------------|-----------------------------------------------------------------------------------|
| `BanRepoOutsideContexts`          | `Repo` / `Ecto.Query` only in context files.                                      |
| `BangBangRepoCalls`               | No `Repo.*!` mutations - failures return `{:error, changeset}`.                   |
| `BanBinaryInvocationOutsideRunners` | `System.cmd` / `Port.open` only in `test_runners/` impls.                       |
| `BanManualStringCoercion`         | No `String.to_integer` / `to_float` outside `Settings`.                           |
| `BanNonReqHttp`                   | No `:httpc` / `:httpoison` / `:tesla` - `Req` for every outbound call.            |

Outbound HTTP uses `Req` throughout; tests stub it with `Req.Test` plugs via app
env, not Mox.

---

## What's built

The v2 release shipped: multiple cron schedules with per-schedule threshold
profiles; TCP ping as a second test runner; JIT health (`auto` / `absolute` /
`off` + ratio); adaptive testing (breach speeds up the cadence, recovery
reverts); the heatmap (wall grid + dashboard tile + embed); streak-gated,
recovery, and failure notifications; ntfy + webhook channels with editable
templates; SLA compliance and promised-speed settings; the next-test countdown;
persistent date-range preference; threshold overlay lines and failure markers on
the charts; and the Prometheus `/metrics` endpoint.

## Deferred / not built

Recorded as scope boundary, not promise: optional password auth (#18 - no plug
exists; `phx.gen.auth` + a provider behaviour is the planned shape); traceroute
on failure (#41); incident timelines (a first-class concept that groups
consecutive failures - would add an `incident_id`, deliberately not forward-shaped
since nothing writes it yet); remote agents / a REST API / CSV-PDF export;
iPerf3 and OIDC as later behaviour/provider impls. The auth gate, when it lands,
is the single point `/metrics`, `/health`, and `/heatmap/embed` adopt.
