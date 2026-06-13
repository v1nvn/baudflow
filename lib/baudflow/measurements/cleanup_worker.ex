defmodule Baudflow.Measurements.CleanupWorker do
  @moduledoc """
  Oban worker that prunes measurements older than the configured retention period.

  Reads `retention_days` from `Baudflow.Settings` and deletes all measurements
  whose `timestamp` falls before the computed cutoff. Runs on the `:default` queue
  with `max_attempts: 1` (failure means the job is discarded; next cron fires tomorrow).
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Baudflow.Measurements.Measurement
  alias Baudflow.Repo
  alias Baudflow.Settings

  @impl true
  def perform(_job) do
    retention_days = Settings.get_integer("retention_days", 365)

    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 24 * 3600, :second)

    {count, _} =
      Repo.delete_all(
        from m in Measurement,
          where: m.timestamp < ^cutoff
      )

    {:ok, pruned: count}
  end
end
