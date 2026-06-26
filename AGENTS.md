# AGENTS.md

## Context

Network speed monitoring dashboard. Phoenix 1.8 + LiveView, Oban, Postgres. A cron job runs the Ookla `speedtest` CLI, streams progress over PubSub, stores the result, evaluates health, and alerts on degradation.

**Flow:** `SchedulerWorker` (per minute) → `SpeedtestWorker` (run CLI, insert `Measurement`) → `BenchmarkWorker` (health) + `NotificationWorker` (alert). LiveViews subscribe to the `"measurements"` topic. `CleanupWorker` prunes by retention.

## Build & Test

Run quality gates through the `justfile` (`just`), not `mix` directly - the recipes are the source of truth and mirror what CI runs.

- `just check` - **the done-gate.** Runs the full CI gate locally: `mix lint` + the test suite in a throwaway testcontainers Postgres (`MIX_ENV=test`) - the two steps ci.yml runs, verbatim. Run it before declaring a task done or pushing. Needs Docker.
- `just lint` - the no-DB static gate (`mix lint`: format-**check**, deps audit, warnings-as-errors, credo `--strict`, sobelow, dialyzer). Fast; use it when Docker isn't available.
- `just precommit` - fast loop (`mix precommit`: compile warnings, `deps.unlock --unused`, format, test). **Not CI-equivalent** - it skips the static gate, so it can be green while `just lint`/CI is red. Never use it alone as the done-gate; that is exactly how CI stayed red unnoticed.
- `just test [path.exs]` / `just test --failed` to target or rerun failures.
- Fake CLI at `test/support/fake_speedtest` + testcontainers Postgres - no local binary or PG needed.
- Never format or lint by hand - the gates own that.

## Code Organization

- `lib/baudflow/{measurements,runs,settings}/` - each context owns one domain and all its DB access; the top-level `*.ex` is the public API, siblings are schemas and workers.
- `lib/baudflow_web/live/` - one `*Live` per page, template colocated; `components/` for shared HEEx.
- `config/` - `runtime.exs`/`dev.exs` carry queues + crontab; `test.exs` keeps Oban `testing: :manual`.

## DO

- Keep the four stages decoupled - decide, run, evaluate, notify - each in its own worker/context, triggered by Oban jobs, never reaching into another's internals.
- Split a context the moment it grows a second sub-concern; one that schedules, runs, evaluates, and notifies is too many.
- Make new test backends and notification channels behaviour implementations, not branches in a worker - the worker orchestrates, the behaviour does the work.
- Treat scheduling as data (a table), not config keys - the scheduler is a thin dispatcher.
- Route all DB access through a context; `import Ecto.Query` and `Repo` live only in context files.
- Keep each query in exactly one place - averages, retention, neighbor lookups are context functions, not inline.
- Read and write runtime config through `Settings`, which stores strings and returns typed values with a safe fallback; add a default for every key.
- Resolve a tunable that has a critical default as **per-row override → global `Settings` fallback** (e.g. `Scheduling.thresholds_for/1`, the ping target `schedule.target_host || Settings.get("ping_target")`); register the global default in `Settings.@default_settings` so resolution never yields nil - one reader, no second source of the default.
- Run tests through `SpeedtestWorker` - it owns binary resolution, timeout wrapping, NDJSON parsing, and insertion.
- Broadcast on the single `"measurements"` topic with stable shapes; emit a terminal event for every outcome so the UI never waits on a timer.
- A LiveView that subscribes to `"measurements"` must no-op every broadcast shape on it (`{:health,_,_}`, `{:speedtest_progress,_,_}`, `{:ping_progress,_}`, …), not just the ones it renders — any unhandled one crashes the LV.
- Give each schema one `changeset/2` as the only construction path; `@derive {Jason.Encoder, only: [...]}` on anything serialized.
- Store the full raw result JSON - never drop fields when mapping; `:bigint` for bytes, `:float` for rates.
- Display throughput in bits/sec everywhere; the raw `bandwidth` field is bytes/sec and storage-only - never render it as a rate, or one screen shows the same speed in both bits and bytes.
- Drive LiveView state through `push_patch` + URL params in `handle_params`; stream charts with `push_event`; give forms and buttons unique DOM ids.
- Build forms with `to_form/2` + `<.input field={…}>`; preserve DOM ids and submit namespaces when converting raw inputs.
- Render a CRUD resource as a table (match the `runs`/`history` idiom) with a New/Edit form on its own route via `push_patch` + `live_action` in `handle_params` - not stacked inline forms or a modal (no modal precedent in this app).
- A nullable boolean with `nil` = "inherit" semantics renders as a tristate `<select>` (a transient param translated in the handler), not a checkbox - a checkbox can't express nil.
- Parse an int id from a path/event param with `Integer.parse/1` or let `Repo.get` cast the PK - `String.to_integer/1` is credo-banned outside `Settings`.
- Use `Req` for every outbound HTTP call. Prefer `Req.Test` plugs (app env) for stubs, not Mox.
- Derive timeouts and magic numbers from module attributes (`@timeout_seconds`) - single source of truth.
- Keep tests deterministic - fake speedtest binary, fixed timestamps, `start_supervised!/1`, assert by DOM id.
- Run `just check` before declaring a task done - it reproduces CI exactly; `just precommit` is a fast loop that skips `lint` and goes green-locally-red-on-CI if used alone.
- Build polished UIs - dark-only Tron neon palette (HSL tokens in `@theme`, chart colors in `chartColors()`).
- Render user-facing timestamps via `<.local_time>` + the `LocalTime` JS hook (browser-local) - the server can't know the viewer's timezone, so the only `Calendar.strftime` on a datetime lives inside that component as a no-JS fallback.
- Put a unique DOM `id` on every `phx-hook` element - LiveView won't attach a hook without one (silent no-op), and use the record id inside `:for` loops to stay unique.
- One level of abstraction per function - orchestration and data-wrangling don't share a body.
- Give every value exactly one meaning; fix the representation instead of adding a compensating flag.
- Raw data is sacred, derived views are cheap.
- Delete replaced functions wholesale after a refactor - don't leave `parse_server_list/1` when `Settings.get_integer_list/1` superseded it.
- When a session lands on a rule worth keeping, add it to DO or DON'T as a one-liner - this file is the memory, not the transcript.

## DON'T

- Don't let pipeline stages reach into each other's internals - pass through Oban jobs or context APIs.
- Don't call `Repo.*` or write `from m in Measurement` outside a context; don't duplicate a "one-line" query.
- Don't use bang mutations (`Repo.update!/insert!/delete!`) - failures must return `{:error, changeset}` so workers can log and continue.
- Don't read `Application.get_env` for user-tunable values (that's for deploy wiring: binary paths, ntfy URL).
- Don't scatter `String.to_integer`/`to_float` across callers - a bad setting must never crash a queue.
- Don't call `Schema.changeset/1` (arity-1) - schemas expose one `changeset/2`; a blank form uses `changeset(%Schema{}, %{})`.
- Don't invoke the speedtest binary outside `SpeedtestWorker`.
- Don't invent Oban queues, PubSub topics, or behaviours without reason; don't move Oban off `testing: :manual`.
- Don't `String.to_atom/1` on external input; don't cast programmatically-set fields like `measurement_id`.
- Don't write inline `<script>` or vendor scripts; don't use daisyUI or `@apply`; don't reach for `LiveComponent`s without a strong need.
- Don't `Process.sleep/1` in tests - monitor or `:sys.get_state/1`.
- Don't broadcast a half-formed measurement from an async LiveView test — async tests share the `"measurements"` topic, so an Ookla row with a nil upload crashes a concurrent dashboard LV's `Float.round`. Fixtures must be complete rows.
- Don't use `:httpc`, `:httpoison`, or `:tesla`; don't add deps unless asked.
- Don't change CI without understanding the branch-protection and image-build gating.
- Don't create files, add features beyond what was asked, or comment code you didn't touch.
