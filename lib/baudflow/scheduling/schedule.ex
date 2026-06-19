defmodule Baudflow.Scheduling.Schedule do
  @moduledoc """
  Schema for a test schedule: a cron cadence plus the per-schedule escalation
  and threshold state the pipeline reads and mutates.

  The escalation fields (`breach_streak`, `escalation_level`) live here and are
  mutated only through the atomic functions in `Baudflow.Scheduling` — never via
  a get→change→update, which races across concurrent Oban jobs. The threshold
  fields are nullable: a `nil` means "inherit the global `Settings` value",
  resolved by `Scheduling.thresholds_for/1` (the single threshold reader).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Crontab.CronExpression.Parser, as: CronParser

  schema "schedules" do
    field :name, :string
    field :cron, :string
    field :server_id, :integer
    field :test_type, :string, default: "ookla"
    field :enabled, :boolean, default: true
    field :escalation_level, :integer, default: 0
    field :breach_streak, :integer, default: 0
    field :threshold_enabled, :boolean
    field :download, :float
    field :upload, :float
    field :ping, :float

    timestamps()
  end

  @type t :: %__MODULE__{}

  @fields ~w(name cron server_id test_type enabled escalation_level breach_streak
             threshold_enabled download upload ping)a

  @doc "The only construction path for a schedule."
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, @fields)
    |> validate_required([:name, :cron])
    |> validate_cron(:cron)
  end

  @doc """
  Parse a cron string without raising.

  Returns `{:ok, expression}` or `{:error, reason}`. A malformed cron is a data
  problem the caller logs and skips — never a queue-crashing exception.
  """
  @spec parse_cron(String.t()) :: {:ok, term()} | {:error, term()}
  def parse_cron(cron) when is_binary(cron) do
    CronParser.parse(cron)
  end

  # Non-bang validation: a bad value becomes a changeset error, not a raise.
  defp validate_cron(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      value when is_binary(value) ->
        case parse_cron(value) do
          {:ok, _} -> changeset
          {:error, _} -> add_error(changeset, field, "is not a valid cron expression")
        end

      _ ->
        changeset
    end
  end
end
