defmodule Baudflow.Measurements.SchedulerWorker do
  @moduledoc """
  Oban worker that checks the DB-stored cron schedule and enqueues a
  SpeedtestWorker job when the current minute matches.

  Idempotency is guaranteed via Oban's unique constraint on
  `[:worker, :args]` with a 1-hour period. The `scheduled_for` key in
  args (truncated to the minute) ensures at most one speedtest per minute
  even if multiple schedulers race.
  """
  use Oban.Worker, queue: :scheduler, max_attempts: 1

  alias Baudflow.Measurements.ServerDiscovery
  alias Baudflow.Measurements.SpeedtestWorker
  alias Crontab.CronExpression.Parser, as: CronParser
  alias Crontab.DateChecker

  @impl true
  def perform(_job) do
    if should_run_now?() do
      scheduled_for =
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> then(fn dt -> %{dt | second: 0} end)
        |> DateTime.to_iso8601()

      server_id = ServerDiscovery.select_server()

      %{scheduled_for: scheduled_for, server_id: server_id, source: "scheduled"}
      |> SpeedtestWorker.new(unique: [fields: [:worker, :args], period: 3600])
      |> Oban.insert()
    end

    :ok
  end

  defp should_run_now? do
    cron = Baudflow.Settings.get("schedule_cron")
    expression = CronParser.parse!(cron)
    DateChecker.matches_date?(expression, DateTime.utc_now())
  end
end
