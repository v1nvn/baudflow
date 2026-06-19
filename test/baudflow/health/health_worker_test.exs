defmodule Baudflow.Health.HealthWorkerTest do
  use Baudflow.DataCase, async: true
  use Oban.Testing, repo: Baudflow.Repo

  alias Baudflow.Health.HealthWorker
  alias Baudflow.Measurements
  alias Baudflow.Scheduling

  setup do
    {:ok, schedule: schedule!(%{threshold_enabled: true, download: 100.0})}
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

      assert Measurements.get_measurement!(m.id).healthy == false

      refreshed = Scheduling.get_schedule!(schedule.id)
      assert refreshed.breach_streak == 1
      assert refreshed.escalation_level == 1

      [job] = all_enqueued(worker: Baudflow.Notifications.NotificationWorker)
      assert job.args["kind"] == "breach"
      assert job.args["measurement_id"] == m.id

      assert_receive {:health, ^id, :breach}
    end
  end

  describe "perform/1 - healthy" do
    test "no streak change, no escalation, no notification", %{schedule: schedule} do
      m = insert_measurement!(150.0)

      assert :ok = perform_job(HealthWorker, %{"measurement_id" => m.id})

      assert Measurements.get_measurement!(m.id).healthy == true

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
    end
  end
end
