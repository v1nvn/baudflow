defmodule BaudFlow.Runs.Run do
  @moduledoc """
  Schema for speedtest run records.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "runs" do
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :status, :string
    field :error, :string
    field :oban_job_id, :integer
    field :measurement_id, :id

    timestamps()
  end

  @doc "Changeset for a successful run."
  def complete_changeset(started_at, measurement_id, oban_job_id) do
    %__MODULE__{}
    |> change(%{
      started_at: started_at,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      status: "success",
      measurement_id: measurement_id,
      oban_job_id: oban_job_id
    })
    |> validate_required([:started_at, :status])
  end

  @doc "Changeset for a failed run."
  def fail_changeset(started_at, error, oban_job_id, status) do
    %__MODULE__{}
    |> change(%{
      started_at: started_at,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      status: status,
      error: error,
      oban_job_id: oban_job_id
    })
    |> validate_required([:started_at, :status])
    |> validate_inclusion(:status, ["failure", "timeout"])
  end
end
