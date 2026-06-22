defmodule Baudflow.Scheduling do
  @moduledoc """
  Context for test schedules: the cron cadence plus the per-schedule escalation
  and threshold state the pipeline reads and mutates.

  Mutations of `breach_streak` / `escalation_level` are atomic — compare-and-set
  via `Repo.update_all`, never get→change→update, because concurrent Oban jobs
  (later: ping every minute + speedtest) race on the same row. Thresholds are
  read through `thresholds_for/1`, the one threshold reader: a schedule's own
  value overrides the global `Settings` fallback, using an explicit nil-check so
  a real `false` overrides instead of falling through.
  """

  import Ecto.Query
  require Logger

  alias Baudflow.Repo
  alias Baudflow.Scheduling.Schedule
  alias Baudflow.Settings
  alias Crontab.DateChecker

  @fallback_cron "0 * * * *"
  @next_run_cap_minutes 7 * 24 * 60

  # Crash-guard for the auto-mode breach ratio when the setting is blanked to an
  # unparseable value (the canonical default is the `"threshold_ratio"` entry in
  # `Settings.@default_settings`; this only stops a nil reaching Health's `ratio ×
  # median` arithmetic). Keep the two in sync.
  @fallback_ratio 0.7

  # --- Reads ------------------------------------------------------------------

  @doc "List all schedules, ordered by name."
  @spec list_schedules() :: [Schedule.t()]
  def list_schedules do
    Repo.all(from(s in Schedule, order_by: [asc: s.name]))
  end

  @doc "Fetch a schedule by id (raises if missing)."
  @spec get_schedule!(term()) :: Schedule.t()
  def get_schedule!(id), do: Repo.get!(Schedule, id)

  @doc "Fetch a schedule by id (nil if missing)."
  @spec get_schedule(term()) :: Schedule.t() | nil
  def get_schedule(id), do: Repo.get(Schedule, id)

  # --- Writes -----------------------------------------------------------------

  @doc "Create a schedule. Cron is validated non-bang; a bad value returns an error, never raises."
  @spec create(map()) :: {:ok, Schedule.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %Schedule{}
    |> Schedule.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Update a schedule from an attrs map."
  @spec update(Schedule.t(), map()) :: {:ok, Schedule.t()} | {:error, Ecto.Changeset.t()}
  def update(%Schedule{} = schedule, attrs) do
    schedule
    |> Schedule.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a schedule. Its measurements' `schedule_id` is nilified by the FK
  `on_delete: :nilify_all`, so history is retained (HealthWorker falls back to
  the first schedule when `schedule_id` is nil). Non-bang — returns
  `{:error, changeset}` on failure, never raises.
  """
  @spec delete(Schedule.t()) :: {:ok, Schedule.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Schedule{} = schedule), do: Repo.delete(schedule)

  # --- Scheduling -------------------------------------------------------------

  @doc """
  Return the enabled schedules whose cron matches the current minute.

  A schedule with an unparseable cron is logged and skipped — never raised — so
  one bad row cannot crash the per-minute scheduler queue. (The changeset
  rejects bad crons at write time; this is the defensive belt.)
  """
  @spec due_now() :: [Schedule.t()]
  def due_now do
    now = DateTime.utc_now()

    Schedule
    |> where(enabled: true)
    |> Repo.all()
    |> Enum.filter(&matches_now?(&1, now))
  end

  defp matches_now?(%Schedule{id: id, name: name} = schedule, now) do
    cron = active_cron(schedule)

    case Schedule.parse_cron(cron) do
      {:ok, expression} ->
        DateChecker.matches_date?(expression, now)

      {:error, reason} ->
        Logger.warning(
          "schedule #{inspect(id)} (#{name}) has unparseable cron #{inspect(cron)}: " <>
            "#{inspect(reason)}; skipping"
        )

        false
    end
  end

  @doc """
  Compute the next time the schedule fires after now, or `nil` if the cron is
  unparseable or fires less often than once a week.
  """
  @spec next_run_at(Schedule.t()) :: DateTime.t() | nil
  def next_run_at(%Schedule{} = schedule) do
    case Schedule.parse_cron(active_cron(schedule)) do
      {:ok, expression} ->
        base = now_truncated_to_minute() |> DateTime.add(60, :second)
        find_next(expression, base, 0)

      {:error, _} ->
        nil
    end
  end

  defp find_next(expression, candidate, step) when step < @next_run_cap_minutes do
    if DateChecker.matches_date?(expression, candidate) do
      candidate
    else
      find_next(expression, DateTime.add(candidate, 60, :second), step + 1)
    end
  end

  defp find_next(_expression, _candidate, _step), do: nil

  defp now_truncated_to_minute do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    %{now | second: 0}
  end

  @doc """
  The soonest next fire across enabled schedules, or `nil` when none run.

  Returns `%{name: schedule_name, at: datetime}` for the enabled schedule whose
  `next_run_at/1` is earliest. Read-only — the dashboard "next test" card uses
  it; never mutates schedule state.
  """
  @spec next_run() :: %{name: String.t(), at: DateTime.t()} | nil
  def next_run do
    Schedule
    |> where(enabled: true)
    |> Repo.all()
    |> Enum.map(fn schedule -> {schedule.name, next_run_at(schedule)} end)
    |> Enum.reject(fn {_name, at} -> is_nil(at) end)
    |> Enum.min_by(fn {_name, at} -> at end, fn -> nil end)
    |> case do
      nil -> nil
      {name, at} -> %{name: name, at: at}
    end
  end

  # --- Active cadence (single reader) -----------------------------------------

  @doc """
  The cron expression in effect right now: the `escalated_cron` when the schedule
  is escalated (`escalation_level > 0`) and one is configured, else the base
  `cron`. The single reader for "which cadence runs now" — `due_now/0`,
  `next_run_at/1` (and so the dashboard "next test" card + the schedules table)
  all read it, so adaptive testing (#13) is a switch here, not a parallel path.

  `escalation_level` is maintained by `Health` regardless; without an
  `escalated_cron` the level is inert (falls back to the base cron).
  """
  @spec active_cron(Schedule.t()) :: String.t()
  def active_cron(%Schedule{escalation_level: level, escalated_cron: escalated})
      when level > 0 and is_binary(escalated) and escalated != "" do
    escalated
  end

  def active_cron(%Schedule{cron: cron}), do: cron

  # --- Escalation state (atomic) ----------------------------------------------

  @doc """
  Atomically escalate the schedule's escalation level via compare-and-set.

  Returns `{:ok, count}`: `1` if this caller won the CAS (the level was still
  the expected value) or `0` if a concurrent job already moved it. Never
  get→change→update — that races across concurrent Oban jobs.
  """
  @spec escalate(Schedule.t()) :: {:ok, non_neg_integer()}
  def escalate(%Schedule{id: id, escalation_level: expected}) do
    {count, _} =
      from(s in Schedule, where: s.id == ^id and s.escalation_level == ^expected)
      |> Repo.update_all(inc: [escalation_level: 1])

    {:ok, count}
  end

  @doc """
  Atomically deescalate via compare-and-set, floored at zero. A level already at
  zero is a no-op (`{:ok, 0}`).
  """
  @spec deescalate(Schedule.t()) :: {:ok, non_neg_integer()}
  def deescalate(%Schedule{id: id, escalation_level: expected}) do
    {count, _} =
      from(s in Schedule,
        where: s.id == ^id and s.escalation_level == ^expected and s.escalation_level > 0
      )
      |> Repo.update_all(inc: [escalation_level: -1])

    {:ok, count}
  end

  @doc """
  Atomically increment the breach streak; returns `{:ok, new_streak}` — the value
  just written, so HealthWorker can snapshot it into the breach event. The read
  back is authoritative (a schedule has a single writer per cron tick, so there is
  no concurrent inc to race the second read). `nil` if the row was concurrently
  deleted (no caller acts on a missing schedule).
  """
  @spec increment_breach_streak(Schedule.t()) :: {:ok, integer() | nil}
  def increment_breach_streak(%Schedule{id: id}) do
    {_, _} = from(s in Schedule, where: s.id == ^id) |> Repo.update_all(inc: [breach_streak: 1])
    {:ok, streak_of(id)}
  end

  @doc """
  Atomically reset the breach streak to zero; returns `{:ok, 0}` — the value it
  set (a reset always writes zero).
  """
  @spec reset_streak(Schedule.t()) :: {:ok, 0}
  def reset_streak(%Schedule{id: id}) do
    {_, _} = from(s in Schedule, where: s.id == ^id) |> Repo.update_all(set: [breach_streak: 0])
    {:ok, 0}
  end

  defp streak_of(id) do
    case Repo.get(Schedule, id) do
      %Schedule{breach_streak: streak} -> streak
      nil -> nil
    end
  end

  # --- Thresholds (single reader) ---------------------------------------------

  @doc """
  Resolve a schedule's thresholds: the schedule's own value if set, else the
  global `Settings` fallback. Each uses an explicit nil-check so a set value
  overrides instead of falling through (the `||` trap).

  `mode` is `:auto | :absolute | :off`; `ratio` is the auto-mode breach factor
  (global-only — a schedule-level ratio is not exposed yet). Download/upload/ping
  are the absolute-mode Mbps/ms. The canonical defaults live in `Settings`;
  `@fallback_ratio` only guards a blanked setting (see its definition).
  """
  @spec thresholds_for(Schedule.t()) :: %{
          mode: :auto | :absolute | :off,
          ratio: float(),
          download: float() | nil,
          upload: float() | nil,
          ping: float() | nil
        }
  def thresholds_for(%Schedule{} = schedule) do
    mode = resolve_mode(schedule.threshold_mode, "threshold_mode")

    # Read the ratio only in :auto — absolute/off callers (incl. pure unit tests
    # whose schedule sets every field) then never touch Settings. `@fallback_ratio`
    # is the lone code literal; the else value is an inert placeholder.
    %{
      mode: mode,
      ratio:
        if(mode == :auto,
          do: Settings.get_float("threshold_ratio", @fallback_ratio),
          else: @fallback_ratio
        ),
      download: resolve_float(schedule.download, "threshold_download"),
      upload: resolve_float(schedule.upload, "threshold_upload"),
      ping: resolve_float(schedule.ping, "threshold_ping")
    }
  end

  @doc """
  Global thresholds — the `Settings` fallbacks a blank schedule would resolve
  to. The dashboard chart and JIT readers span all schedules, so they have no
  single schedule to read; this is the one reader for "what's the configured
  health mode/ratio right now?".
  """
  @spec global_thresholds() :: map()
  def global_thresholds, do: thresholds_for(%Schedule{})

  # Closed string→atom mapping; never String.to_atom/1 on stored input. An
  # unknown or absent value resolves to :auto (the smart default).
  defp resolve_mode(nil, key), do: key |> Settings.get() |> mode_atom()
  defp resolve_mode(value, _key), do: mode_atom(value)

  defp mode_atom("absolute"), do: :absolute
  defp mode_atom("off"), do: :off
  defp mode_atom(_), do: :auto

  defp resolve_float(nil, key), do: Settings.get_float(key, 0.0)
  defp resolve_float(value, _key), do: value

  # --- Seeding ----------------------------------------------------------------

  @default_escalated_cron "*/15 * * *"

  # The default schedules a fresh install gets, one per test_type: an Ookla
  # speed test and an ICMP ping, both hourly, both escalating to 15 min on a
  # breach. Keyed by test_type so re-bootstrapping is idempotent per-kind — a
  # power user's extra schedules are untouched, and an existing one-schedule
  # install gains the ping schedule on next boot.
  @default_schedules [
    {"ookla", "Default"},
    {"ping", "Ping"}
  ]

  @doc """
  Seed the default schedules idempotently, one per test_type. Each gets the
  resolved base cron (legacy `schedule_cron` setting or hourly fallback) and a
  15-min escalated cadence so escalation actually speeds up tests on a breach.
  A malformed legacy cron falls back to hourly.
  """
  @spec bootstrap() :: :ok
  def bootstrap do
    cron = (Settings.get("schedule_cron") || @fallback_cron) |> valid_cron_or(@fallback_cron)

    for {test_type, name} <- @default_schedules do
      seed_if_absent(%{
        test_type: test_type,
        name: name,
        cron: cron,
        escalated_cron: @default_escalated_cron,
        enabled: true
      })
    end

    :ok
  end

  defp seed_if_absent(%{test_type: test_type} = attrs) do
    if Repo.get_by(Schedule, test_type: test_type) do
      {:ok, :already_seeded}
    else
      create(attrs)
    end
  end

  defp valid_cron_or(candidate, fallback) do
    case Schedule.parse_cron(candidate) do
      {:ok, _} -> candidate
      {:error, _} -> fallback
    end
  end
end
