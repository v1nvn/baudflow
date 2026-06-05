This is a network speed monitoring dashboard built with Phoenix v1.8 + LiveView.

## Project guidelines

- DO run `mix precommit` when done with all changes and fix any pending issues
- DO use the included `Req` library for HTTP requests - avoid `:httpoison`, `:tesla`, and `:httpc`
- DON'T add new dependencies unless explicitly asked

## Phoenix v1.8

- DO wrap all LiveView template content in `<Layouts.app flash={@flash} ...>`
- DON'T call `<.flash_group>` outside of `layouts.ex`
- DO use the `<.icon name="hero-...">` component for icons - never use `Heroicons` modules
- DO use the imported `<.input>` component for form inputs from `core_components.ex`
- DON'T forget that overriding `<.input>` class replaces all defaults - you must fully style it

## JS and CSS

- DO use Tailwind CSS v4 with the `@import "tailwindcss" source(none)` syntax already in `app.css`
- DON'T use `@apply` in raw CSS
- DON'T use daisyUI - write custom Tailwind components
- DON'T reference external vendor scripts/links in layouts - import everything into `app.js`/`app.css`
- DON'T write inline `<script>` tags in templates - use colocated hooks or external `phx-hook`
- DO build polished UIs with micro-interactions, smooth transitions, and thoughtful hover/loading states

## Elixir

- DO use `Enum.at/2`, pattern matching, or `List` for index-based list access - bracket syntax doesn't work
- DO rebind the result of `if`/`case`/`cond` to a variable - never rebind inside the expression body
- DON'T nest multiple modules in one file - causes cyclic dependency errors
- DO access struct fields with dot notation (`struct.field`), not bracket syntax (`struct[:field]`)
- DON'T use `String.to_atom/1` on user input - memory leak risk
- DO end predicate function names with `?` - reserve `is_` prefix for guards
- DO pass `timeout: :infinity` to `Task.async_stream/3` in most cases
- DON'T use `else if` or `elseif` - use `cond` or `case` for multiple conditionals

## Mix

- DO use `mix test test/my_test.exs` for targeted test runs and `mix test --failed` for previously failed tests
- DON'T use `mix deps.clean --all` unless you have a very good reason

## Testing

- DO use `start_supervised!/1` to start processes in tests - guarantees cleanup
- DON'T use `Process.sleep/1` - use `Process.monitor/1` and assert on `{:DOWN, ...}` instead
- DO use `_ = :sys.get_state/1` to synchronize before the next call instead of sleeping

## Ecto

- DO preload associations in queries when they'll be accessed in templates
- DO use `:string` type for all text columns, including `:text`
- DO use `Ecto.Changeset.get_field/2` to access changeset fields
- DON'T list programmatically-set fields (like `user_id`) in `cast` calls - set them explicitly on the struct
- DO use `mix ecto.gen.migration` to generate migrations so timestamps and conventions are correct
- DON'T pass `:allow_nil` to `validate_number/2` - it's not supported and unnecessary

## Phoenix HTML & HEEx

- DO use `~H` or `.html.heex` files - never `~E`
- DO use `Phoenix.Component.form/1` and `inputs_for/1` - never the outdated `Phoenix.HTML` versions
- DO use `to_form/2` to build forms and access fields as `@form[:field]` - never access changesets in templates
- DO add unique DOM IDs to forms, buttons, and key elements for test targeting
- DO use HEEx list syntax `[...]` for class attributes with conditional classes
- DO use `<%= for item <- @collection do %>` - never `<% Enum.each %>`
- DO use `<%!-- comment --%>` for template comments
- DO use `{...}` for attribute interpolation and `<%= ... %>` for tag body interpolation only
- DO annotate `<pre>`/`<code>` blocks with `phx-no-curly-interpolation` when showing literal curly braces

## LiveView

- DO use `<.link navigate={...}>` and `<.link patch={...}>` - never deprecated `live_redirect`/`live_patch`
- DO use `push_navigate`/`push_patch` in LiveViews - never deprecated `live_redirect`/`live_patch`
- DON'T use LiveComponents unless you have a strong, specific need
- DO name LiveViews with a `Live` suffix (e.g. `DashboardLive`)

### Streams

- DO use LiveView streams for all collections - never assign raw lists
- DO set `phx-update="stream"` and a DOM id on the parent element, consume via `@streams.stream_name`
- DO refetch and re-stream with `reset: true` when filtering - streams aren't enumerable
- DO track counts with a separate assign - streams don't support counting or empty states
- DO use `stream_insert/3` when an assign change should update a streamed item's rendered content
- DON'T use deprecated `phx-update="append"` or `phx-update="prepend"`

### JS interop

- DO set `phx-update="ignore"` alongside `phx-hook` when the hook manages its own DOM
- DO provide a unique DOM id alongside `phx-hook`
- DO use colocated hooks (`:type={Phoenix.LiveView.ColocatedHook}`) with `.` prefix names for inline scripts
- DO define external hooks in `assets/js/` and register them in the `LiveSocket` constructor
- DO return or rebind the socket on `push_event/3` calls

### LiveView tests

- DO use `element/2`, `has_element/2`, and `LazyHTML` selectors - never test against raw HTML strings
- DO reference DOM IDs from templates in tests
- DO test for element presence over text content - text changes, structure is stable
- DO use `LazyHTML.from_fragment` and `LazyHTML.filter` for debug output when selectors fail

### Forms

- DO use `to_form/2` from a changeset and pass `@form` to `<.form>` - never pass changesets to templates
- DO give every form an explicit, unique DOM ID (e.g. `id="settings-form"`)
- DON'T use `<.form let={f} ...>` - always use `<.form for={@form} ...>` and access fields as `@form[:field]`

## Baudflow-specific

### Oban workers

- DO use the four existing queues: `:scheduler`, `:speedtest`, `:notifications`, `:default` - don't invent new ones without reason
- DO use `unique: [fields: [:worker, :args], period: 3600]` on speedtest jobs to prevent duplicates
- DO keep `testing: :manual` for Oban in test config - don't switch to `:inline` or `:disabled`
- DON'T invoke the speedtest binary directly - always go through `SpeedtestWorker` which handles timeout wrapping and output parsing
- DO broadcast results via `Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", msg)` - don't create new topic names

### Settings

- DO use the `Settings` context (`get/1`, `get_all/0`, `update_all/1`) for all runtime configuration - don't read `Application.get_env` for user-tunable values
- DO store settings as strings in the DB - the context layer handles type coercion
- DON'T add new settings without also adding a sensible default in the Settings defaults map

### Measurements schema

- DO use `@derive {Jason.Encoder, only: [...]}` on schemas that get serialized to JSON
- DO store the raw Ookla JSON in `raw_result` - don't drop fields when parsing
- DO use `:bigint` for byte counts and `:float` for Mbps/latency - match existing field types

### LiveView conventions

- DO set `:active_page` and `:page_title` assigns on every LiveView mount
- DO subscribe to `Baudflow.PubSub` `"measurements"` topic in mount when the LiveView needs real-time updates
- DO use `push_patch` with URL query params for filtering/pagination - don't `push_navigate` for same-page state changes
- DO use `push_event("append_point", ...)` for streaming chart data to the client

### Chart.js integration

- DO define all chart hooks in `assets/js/app.js` - don't create separate JS entry points
- DO use the existing color palette: download=cyan/blue, upload=green, latency=yellow, jitter=red, averages=purple/pink
- DO handle theme changes in charts by listening to the theme toggle event

### Speedtest CLI

- DO use `Application.get_env(:baudflow, :speedtest_bin)` for the binary path - it supports multi-word wrapper commands
- DO use `binary_available?()` to gate features that depend on the CLI - don't assume the binary exists
- DO handle both pretty-printed JSON and NDJSON output from the speedtest CLI

### Tests

- DO use testcontainers (Docker) for Postgres in CI - configured via `mix check`
- DO use the fake speedtest binary at `test/support/fake_speedtest` for deterministic test output
- DO use `DataCase` for context tests and `ConnCase` for controller/LiveView tests

### Docker & CI

- DO build multi-platform images (AMD64 + ARM64) for GitHub Container Registry
- DON'T modify the CI pipeline without understanding the branch protection and image build gating
