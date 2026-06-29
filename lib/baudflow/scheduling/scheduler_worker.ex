defmodule Baudflow.Scheduling.SchedulerWorker do
  @moduledoc """
  Thin dispatcher: every minute, ask `Scheduling` which schedules are due and
  enqueue a `RunnerWorker` per due schedule. Owns no cron parsing or health
  state - those live in `Scheduling` and `Health` respectively.

  Idempotency is guaranteed via Oban's unique constraint on
  `[:worker, :args]` with a 1-hour period. The `scheduled_for` key (truncated to
  the minute) ensures at most one test per minute per schedule even if the
  dispatcher races.
  """

  use Oban.Worker, queue: :scheduler, max_attempts: 1

  alias Baudflow.Measurements.ServerDiscovery
  alias Baudflow.Scheduling
  alias Baudflow.TestRunners.RunnerWorker

  @impl true
  def perform(_job) do
    for schedule <- Scheduling.due_now() do
      server_id = schedule.server_id || ServerDiscovery.select_server()

      %{
        scheduled_for: scheduled_for_now(),
        server_id: server_id,
        target_host: schedule.target_host,
        source: "scheduled",
        test_type: schedule.test_type,
        schedule_id: schedule.id
      }
      |> RunnerWorker.new(unique: [fields: [:worker, :args], period: 3600])
      |> Oban.insert()
    end

    :ok
  end

  defp scheduled_for_now do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> then(fn dt -> %{dt | second: 0} end)
    |> DateTime.to_iso8601()
  end
end
