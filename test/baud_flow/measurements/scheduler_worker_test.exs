defmodule BaudFlow.Measurements.SchedulerWorkerTest do
  use BaudFlow.DataCase, async: true
  use Oban.Testing, repo: BaudFlow.Repo

  alias BaudFlow.Measurements.SchedulerWorker
  alias BaudFlow.Measurements.SpeedtestWorker

  # The scheduler reads schedule_cron from the DB; seed it so the cron
  # always matches in the "enqueue" tests. "* * * * *" fires every minute.
  setup do
    BaudFlow.Settings.update_all(%{
      "schedule_cron" => "* * * * *",
      "preferred_servers" => "12345",
      "blocked_servers" => ""
    })

    :ok
  end

  describe "perform/1" do
    test "enqueues exactly one speedtest per minute (idempotent)" do
      # SchedulerWorker uses unique: [fields: [:worker, :args]] - both calls
      # land in the same truncated minute, so Oban deduplicates.
      assert :ok = perform_job(SchedulerWorker, %{})
      assert :ok = perform_job(SchedulerWorker, %{})

      assert_enqueued(worker: SpeedtestWorker)
    end

    test "includes scheduled_for in args" do
      assert :ok = perform_job(SchedulerWorker, %{})

      [job] = all_enqueued(worker: SpeedtestWorker)
      assert Map.has_key?(job.args, "scheduled_for")
    end

    test "sets source to scheduled" do
      assert :ok = perform_job(SchedulerWorker, %{})

      [job] = all_enqueued(worker: SpeedtestWorker)
      assert job.args["source"] == "scheduled"
    end

    test "uses ServerDiscovery for server selection" do
      assert :ok = perform_job(SchedulerWorker, %{})

      [job] = all_enqueued(worker: SpeedtestWorker)
      # With preferred_servers set to "12345", ServerDiscovery picks that
      assert job.args["server_id"] == 12_345
    end

    test "returns :ok even when cron does not match" do
      # Set cron to something that never matches any real time (Feb 31).
      BaudFlow.Settings.update_all(%{"schedule_cron" => "0 0 31 2 *"})

      assert :ok = perform_job(SchedulerWorker, %{})

      refute_enqueued(worker: SpeedtestWorker)
    end
  end
end
