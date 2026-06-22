defmodule Baudflow.Health.HealthWorkerTest do
  use Baudflow.DataCase, async: true
  use Oban.Testing, repo: Baudflow.Repo

  alias Baudflow.Health.HealthWorker
  alias Baudflow.Measurements
  alias Baudflow.Scheduling

  setup do
    {:ok, schedule: schedule!(%{threshold_mode: "absolute", download: 100.0})}
  end

  defp schedule!(attrs) do
    {:ok, s} = Scheduling.create(Map.merge(%{name: "S", cron: "0 * * * *"}, attrs))
    s
  end

  # download threshold 100; pass download_mbps above/below it.
  defp insert_measurement!(download_mbps) do
    {:ok, m} =
      Measurements.create_measurement(%{
        timestamp: DateTime.utc_now(),
        ping_latency: 10.0,
        download_bandwidth: round(download_mbps / 0.000008),
        upload_bandwidth: round(25.0 / 0.000008),
        result_id: Ecto.UUID.generate()
      })

    m
  end

  describe "perform/1 - breach" do
    test "sets unhealthy, bumps streak, escalates, enqueues a notification, broadcasts",
         %{schedule: schedule} do
      Phoenix.PubSub.subscribe(Baudflow.PubSub, "measurements")
      m = insert_measurement!(50.0)
      id = m.id

      assert :ok = perform_job(HealthWorker, %{"measurement_id" => m.id})

      refreshed = Scheduling.get_schedule!(schedule.id)
      assert refreshed.breach_streak == 1
      assert refreshed.escalation_level == 1

      [job] = all_enqueued(worker: Baudflow.Notifications.NotificationWorker)
      assert job.args["kind"] == "breach"
      assert job.args["measurement_id"] == m.id
      # The streak is snapshotted into the event so the policy can gate on it.
      assert job.args["streak"] == 1

      assert_receive {:health, ^id, :breach}
    end

    test "enqueues a breach event on every consecutive breach with the climbing streak",
         %{schedule: schedule} do
      # 3 unhealthy results → 3 breach events carrying streaks 1, 2, 3. The
      # notification policy (not HealthWorker) decides which fire. This is what
      # makes #21 streak-gating possible: each breach is observable.
      Enum.each(1..3, fn _ ->
        m = insert_measurement!(50.0)
        assert :ok = perform_job(HealthWorker, %{"measurement_id" => m.id})
      end)

      jobs = all_enqueued(worker: Baudflow.Notifications.NotificationWorker)
      assert length(jobs) == 3
      # Order isn't guaranteed (all_enqueued returns newest-first); the streak
      # values themselves are what matter.
      assert jobs |> Enum.map(& &1.args["streak"]) |> Enum.sort() == [1, 2, 3]
      assert Enum.all?(jobs, &(&1.args["kind"] == "breach"))

      assert Scheduling.get_schedule!(schedule.id).breach_streak == 3
    end
  end

  describe "perform/1 - failed" do
    test "emits a :failed event without touching streak or escalation", %{schedule: schedule} do
      {:ok, failed} =
        Measurements.record_failure(%{
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          test_type: "ookla"
        })

      assert :ok = perform_job(HealthWorker, %{"measurement_id" => failed.id})

      [job] = all_enqueued(worker: Baudflow.Notifications.NotificationWorker)
      assert job.args["kind"] == "failed"
      assert job.args["measurement_id"] == failed.id

      # A CLI failure is neither a confirmed breach nor a recovery — the
      # breach/recovery state machine must stay put.
      refreshed = Scheduling.get_schedule!(schedule.id)
      assert refreshed.breach_streak == 0
      assert refreshed.escalation_level == 0
    end

    test "does not crash when no schedule exists for a failed measurement" do
      # Bootstrap always seeds one, but defensively: a failed measurement with no
      # schedule logs and skips (the runner already broadcast {:result, _}).
      Scheduling.list_schedules() |> Enum.each(&Scheduling.delete/1)

      {:ok, failed} =
        Measurements.record_failure(%{
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          test_type: "ookla"
        })

      assert :ok = perform_job(HealthWorker, %{"measurement_id" => failed.id})
      refute_enqueued(worker: Baudflow.Notifications.NotificationWorker)
    end
  end

  describe "perform/1 - healthy" do
    test "no streak change, no escalation, no notification", %{schedule: schedule} do
      m = insert_measurement!(150.0)

      assert :ok = perform_job(HealthWorker, %{"measurement_id" => m.id})

      refreshed = Scheduling.get_schedule!(schedule.id)
      assert refreshed.breach_streak == 0
      assert refreshed.escalation_level == 0

      refute_enqueued(worker: Baudflow.Notifications.NotificationWorker)
    end
  end

  describe "perform/1 - recovery" do
    test "resets the streak and deescalates after a breach", %{schedule: schedule} do
      breach = insert_measurement!(50.0)
      assert :ok = perform_job(HealthWorker, %{"measurement_id" => breach.id})
      assert Scheduling.get_schedule!(schedule.id).escalation_level == 1

      recovered = insert_measurement!(150.0)
      assert :ok = perform_job(HealthWorker, %{"measurement_id" => recovered.id})

      refreshed = Scheduling.get_schedule!(schedule.id)
      assert refreshed.breach_streak == 0
      assert refreshed.escalation_level == 0

      # Recovery (#22) enqueues a :recovered event alongside the original breach.
      jobs = all_enqueued(worker: Baudflow.Notifications.NotificationWorker)
      assert Enum.any?(jobs, &(&1.args["kind"] == "recovered"))
    end
  end
end
