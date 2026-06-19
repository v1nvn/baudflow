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

  # --- Reads ------------------------------------------------------------------

  @doc "List all schedules, ordered by name."
  @spec list_schedules() :: [Schedule.t()]
  def list_schedules do
    Repo.all(from(s in Schedule, order_by: [asc: s.name]))
  end

  @doc "Fetch a schedule by id (raises if missing)."
  @spec get_schedule!(term()) :: Schedule.t()
  def get_schedule!(id), do: Repo.get!(Schedule, id)

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

  defp matches_now?(%Schedule{id: id, name: name, cron: cron}, now) do
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
  def next_run_at(%Schedule{cron: cron}) do
    case Schedule.parse_cron(cron) do
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

  @doc "Atomically increment the breach streak."
  @spec increment_breach_streak(Schedule.t()) :: {:ok, non_neg_integer()}
  def increment_breach_streak(%Schedule{id: id}) do
    {count, _} =
      from(s in Schedule, where: s.id == ^id)
      |> Repo.update_all(inc: [breach_streak: 1])

    {:ok, count}
  end

  @doc "Atomically reset the breach streak to zero."
  @spec reset_streak(Schedule.t()) :: {:ok, non_neg_integer()}
  def reset_streak(%Schedule{id: id}) do
    {count, _} =
      from(s in Schedule, where: s.id == ^id)
      |> Repo.update_all(set: [breach_streak: 0])

    {:ok, count}
  end

  # --- Thresholds (single reader) ---------------------------------------------

  @doc """
  Resolve a schedule's thresholds: the schedule's own value if set, else the
  global `Settings` fallback. Uses an explicit nil-check for the boolean so a
  real `false` overrides instead of falling through (the `||` trap).
  """
  @spec thresholds_for(Schedule.t()) :: %{
          enabled: boolean(),
          download: float() | nil,
          upload: float() | nil,
          ping: float() | nil
        }
  def thresholds_for(%Schedule{} = schedule) do
    %{
      enabled: resolve_boolean(schedule.threshold_enabled, "threshold_enabled"),
      download: resolve_float(schedule.download, "threshold_download"),
      upload: resolve_float(schedule.upload, "threshold_upload"),
      ping: resolve_float(schedule.ping, "threshold_ping")
    }
  end

  defp resolve_boolean(nil, key), do: Settings.get_boolean(key)
  defp resolve_boolean(value, _key), do: value

  defp resolve_float(nil, key), do: Settings.get_float(key, 0.0)
  defp resolve_float(value, _key), do: value

  # --- Seeding ----------------------------------------------------------------

  @doc """
  Seed the default schedule from the legacy `schedule_cron` setting when none
  exist. Idempotent. A malformed legacy cron falls back to hourly so deployed
  users keep a cadence instead of a broken one.
  """
  @spec bootstrap() :: {:ok, Schedule.t()} | {:ok, :already_seeded} | {:error, Ecto.Changeset.t()}
  def bootstrap do
    if list_schedules() == [] do
      cron = (Settings.get("schedule_cron") || @fallback_cron) |> valid_cron_or(@fallback_cron)
      create(%{name: "Default", cron: cron, enabled: true})
    else
      {:ok, :already_seeded}
    end
  end

  defp valid_cron_or(candidate, fallback) do
    case Schedule.parse_cron(candidate) do
      {:ok, _} -> candidate
      {:error, _} -> fallback
    end
  end
end
