# AGENTS.md

## Context

Baudflow — network speed monitoring dashboard. Phoenix 1.8 + LiveView, Oban background jobs, Postgres. A cron-driven Oban job runs the Ookla `speedtest` CLI, streams per-phase progress to the browser over PubSub, stores the result, evaluates health thresholds, and alerts on degradation.

**Data flow:** `SchedulerWorker` (every minute, checks the DB-stored cron) → enqueues `SpeedtestWorker` → runs the CLI, broadcasts progress, inserts a `Measurement`, enqueues `BenchmarkWorker` (health thresholds) + `NotificationWorker` (degradation alert). LiveViews subscribe to the `"measurements"` PubSub topic for real-time updates. `CleanupWorker` prunes by retention nightly.

## Build & Test

- `mix precommit` — the gate to run when done with changes (compile warnings-as-errors, unused-dep check, format, test). **Never format or lint by hand — always run this.**
- `mix check` — full local gate: lint + tests in a throwaway Postgres (testcontainers). `mix lint` is the no-DB static gate (format check, deps.audit, credo --strict, sobelow, dialyzer).
- `mix test test/path_test.exs` for targeted runs, `mix test --failed` to rerun failures.
- Tests use the fake CLI at `test/support/fake_speedtest` (deterministic output) and testcontainers for Postgres — no local speedtest binary or PG install needed.

## Code Organization

- `lib/baudflow/{measurements,runs,settings}/` — each is a **context** owning one domain and all of its DB access. The top-level `measurements.ex` / `runs.ex` / `settings.ex` are the public API; sibling files are schemas and Oban workers.
- `lib/baudflow_web/live/` — one LiveView per page (`*Live`), template in a colocated `.html.heex`. `components/` for shared HEEx and layouts.
- `config/` — `runtime.exs` (prod, env-driven) and `dev.exs` carry the Oban queues + crontab; `test.exs` keeps Oban `testing: :manual`.

## Layering & contexts

**DO:**
- Route **all** database access through a context module. `import Ecto.Query` and `Repo` calls live only in `lib/baudflow/{measurements,runs,settings}/*.ex` context files.
- Have workers and LiveViews call context functions (`Measurements.list_since/2`, `Measurements.prune_older_than/1`) — never build queries inline.
- Keep each query in exactly one place. Rolling averages, retention pruning, neighbor lookups, etc. are context functions reused by every caller.

**DON'T:**
- Don't call `Repo.*` or write `from m in Measurement` outside a context. A worker that needs data adds a context function instead.
- Don't duplicate a query because it's "just one line" — duplicated queries drift out of sync.

## Settings

**DO:**
- Read and write all runtime-tunable config through the `Settings` context (`get/1`, `get_all/0`, `update_all/1`). Store every value as a **string** in the DB.
- Do type coercion **in the `Settings` context** — typed accessors that return `integer`/`float`/`boolean` with a safe fallback, so callers receive ready-to-use values.
- Add a default to the `Settings` defaults map for every new key — `get/1` must always return something usable.

**DON'T:**
- Don't read `Application.get_env` for user-tunable values — that's for deploy-time wiring (binary paths, ntfy URL), not settings.
- Don't scatter `String.to_integer/2`, `String.to_float/1`, or bespoke parsers across workers and LiveViews. (`String.to_float/1` also raises on integer-looking input — a bad setting must never crash a queue.)

## Background jobs (Oban)

**DO:**
- Use the four existing queues only: `:scheduler`, `:speedtest`, `:notifications`, `:default`.
- Put `unique: [fields: [:worker, :args], period: ...]` on speedtest jobs to prevent duplicate runs in the same window.
- Go through `SpeedtestWorker` to run a test — it owns CLI resolution, timeout wrapping, NDJSON parsing, and result insertion.
- Broadcast on the single `"measurements"` topic via `Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", msg)`. Keep the message shapes stable: `{:speedtest_progress, type, data}`, `{:result, measurement}`, `{:test_failed, reason}`, `{:benchmarked, id, healthy?}`.
- Emit a terminal event for **every** outcome — success and *every* failure path (timeout, non-zero exit, parse/changeset error). The UI reacts to broadcasts; it must never depend on a client-side timer to learn a test finished.

**DON'T:**
- Don't invoke the speedtest binary directly from anywhere but `SpeedtestWorker`.
- Don't invent new queues or PubSub topics without a clear reason.
- Don't switch Oban test mode to `:inline` or `:disabled`.

## Speedtest CLI

**DO:**
- Resolve the binary at **runtime** via `Application.get_env(:baudflow, :speedtest_bin)`, falling back to `SPEEDTEST_BIN`, then `"speedtest"`. It may be a bare name or a multi-word wrapper (`docker exec … speedtest`).
- Gate any CLI-dependent feature behind `SpeedtestWorker.binary_available?()` — never assume the binary exists.
- Handle both NDJSON (`--format=jsonl`) streaming lines and the final result line; skip non-JSON banner/blank lines.
- Keep the timeout value consistent across the OS `timeout` wrapper, the port-receive fallback, and any user-facing message.

## Schemas & Ecto

**DO:**
- Give each schema one `changeset/2` (cast → validate → constraints) as the single construction path. Mutations go through a changeset, not ad-hoc `Repo.update!` on a raw struct.
- `@derive {Jason.Encoder, only: [...]}` on any schema serialized to JSON, and keep that list in step with the fields the client needs.
- Store the full raw Ookla JSON in `raw_result` — never drop fields when mapping.
- Use `:bigint` for byte counts, `:float` for Mbps/latency/jitter, `:string` for all text. Generate migrations with `mix ecto.gen.migration`.

**DON'T:**
- Don't use `String.to_atom/1` on external/CLI/user input (memory leak risk).
- Don't list programmatically-set fields (e.g. `measurement_id`) in `cast` — set them on the struct.

## Web & LiveView

**DO:**
- Name LiveViews `*Live`. In `mount`, set `:active_page` and `:page_title`, and subscribe to `"measurements"` when the view needs real-time data.
- Drive filtering/pagination through `push_patch` with URL query params handled in `handle_params` — same-page state lives in the URL. Refetch collections from the context on each `handle_params`; track total counts as a separate assign. (Bounded, server-paginated result sets — plain list assigns, deliberately not streams.)
- Stream chart data to the client with `push_event("append_point", ...)` / `push_event("chart_data", ...)`.
- Wrap template content in `<Layouts.app flash={@flash} ...>`, use `<.input>` / `<.icon name="hero-...">` from `core_components`, and build forms with `to_form/2` + `<.form for={@form} id="...">`. Give forms, buttons, and key elements unique DOM ids for test targeting.

**DON'T:**
- Don't write inline `<script>` tags or reference external vendor scripts — use colocated or external `phx-hook`, and import everything through `app.js`/`app.css`.
- Don't use daisyUI or `@apply` in raw CSS; write custom Tailwind v4 components.
- Don't reach for `LiveComponent`s without a strong, specific need.

## Frontend / charts

**Color theme — Tron Legacy:** Dark-mode only. The UI uses a Tron Legacy neon palette: near-black surfaces with cold blue undertones (HSL-based), electric neon accents (cyan, green, amber, red). All color tokens are HSL in `@theme {}` — surfaces step systematically in lightness (4.5% → 10.5% → 16% → 23% → 31.5%). Chart dataset colors in `chartColors()` use matching HSL neon values. There is no theme toggle — the app is dark-only.

**DO:**
- Define all chart hooks in `assets/js/app.js` — no separate JS entry points.
- Use `makeChartOptions()` for shared chart config (responsive sizing, grid styling, tooltips). All charts use `maintainAspectRatio: false` for proper container filling.
- Hero chart (SpeedChart): `borderWidth: 2`, subtle fill, `tension: 0.25`. Secondary charts: `borderWidth: 1.5`, no fill on overlapping datasets, `tension: 0.2`.
- Build polished UIs — micro-interactions, smooth transitions, thoughtful hover/loading states.

## Tests

**DO:**
- `DataCase` for context tests, `ConnCase` for controller/LiveView tests.
- Keep tests deterministic: the fake speedtest binary for CLI output, fixed timestamps, `start_supervised!/1` for processes.
- Target elements by DOM id with `element/2` / `has_element/2`; assert on structure, not raw HTML strings.

**DON'T:**
- Don't use `Process.sleep/1` — monitor processes or use `:sys.get_state/1` to synchronize.
- Don't add dependencies unless explicitly asked; use the included `Req` for HTTP.

## HTTP

**DO:** Use `Req` for every outbound HTTP call (Ookla server discovery, ntfy alerts).

**DON'T:** Don't use `:httpc`, `:httpoison`, or `:tesla`.

## Docker & CI

**DO:** Build multi-platform images (AMD64 + ARM64) for the GitHub Container Registry.

**DON'T:** Don't change the CI pipeline without understanding the branch-protection and image-build gating.

## Scope

- Make minimal, focused changes. Don't create files, add features beyond what was asked, or add comments/docstrings to code you didn't change.
