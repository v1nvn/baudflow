defmodule Baudflow.Scheduling.SchedulerWorkerTest do
  use Baudflow.DataCase, async: true
  use Oban.Testing, repo: Baudflow.Repo

  alias Baudflow.Scheduling
  alias Baudflow.Scheduling.SchedulerWorker

  describe "perform/1" do
    test "enqueues a RunnerWorker per due schedule, carrying schedule_id, test_type, and target_host" do
      {:ok, schedule} =
        Scheduling.create(%{
          name: "Every min",
          cron: "* * * * *",
          enabled: true,
          target_host: "1.1.1.1"
        })

      assert :ok = perform_job(SchedulerWorker, %{})

      [job] = all_enqueued(worker: Baudflow.TestRunners.RunnerWorker)
      assert job.args["schedule_id"] == schedule.id
      assert job.args["test_type"] == "ookla"
      assert job.args["source"] == "scheduled"
      assert job.args["target_host"] == "1.1.1.1"
    end

    test "enqueues nothing when no schedule is due" do
      # Feb 31 - never matches a real time.
      {:ok, _} = Scheduling.create(%{name: "Never", cron: "0 0 31 2 *", enabled: true})

      assert :ok = perform_job(SchedulerWorker, %{})
      refute_enqueued(worker: Baudflow.TestRunners.RunnerWorker)
    end

    test "skips disabled schedules" do
      {:ok, _} = Scheduling.create(%{name: "Off", cron: "* * * * *", enabled: false})

      assert :ok = perform_job(SchedulerWorker, %{})
      refute_enqueued(worker: Baudflow.TestRunners.RunnerWorker)
    end

    test "is idempotent within a minute (Oban unique on worker+args)" do
      {:ok, _} = Scheduling.create(%{name: "Every min", cron: "* * * * *", enabled: true})

      assert :ok = perform_job(SchedulerWorker, %{})
      assert :ok = perform_job(SchedulerWorker, %{})

      assert length(all_enqueued(worker: Baudflow.TestRunners.RunnerWorker)) == 1
    end
  end
end
