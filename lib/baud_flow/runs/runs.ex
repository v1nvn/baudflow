defmodule BaudFlow.Runs do
  @moduledoc """
  Context for speedtest run records.
  """
  import Ecto.Query

  alias BaudFlow.Repo
  alias BaudFlow.Runs.Run

  @doc "Record a successful run."
  def complete_run(started_at, measurement_id, oban_job_id) do
    Run.complete_changeset(started_at, measurement_id, oban_job_id)
    |> Repo.insert()
  end

  @doc "Record a failed run."
  def fail_run(started_at, error, oban_job_id, status) do
    Run.fail_changeset(started_at, error, oban_job_id, status)
    |> Repo.insert()
  end

  @doc "List runs paginated, most recent first. Optionally filter by status."
  def list_runs_paginated(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    status = Keyword.get(opts, :status)
    offset = (page - 1) * per_page

    from(r in Run,
      order_by: [desc: r.started_at],
      limit: ^per_page,
      offset: ^offset
    )
    |> maybe_filter_status(status)
    |> Repo.all()
  end

  @doc "Count total runs, optionally filtered by status."
  def count_runs(opts \\ []) do
    status = Keyword.get(opts, :status)

    from(r in Run, select: count(r.id))
    |> maybe_filter_status(status)
    |> Repo.one()
  end

  @doc "Count runs grouped by status."
  def count_by_status do
    from(r in Run,
      group_by: r.status,
      select: {r.status, count(r.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: from(r in query, where: r.status == ^status)

  @doc "Get a single run by ID."
  def get_run!(id) do
    Repo.get!(Run, id)
  end
end
