defmodule BaudFlow.Measurements.NotificationWorkerTest do
  use BaudFlow.DataCase, async: true
  use Oban.Testing, repo: BaudFlow.Repo

  alias BaudFlow.Measurements
  alias BaudFlow.Measurements.NotificationWorker
  alias BaudFlow.Settings

  setup do
    Settings.update_all(%{"degradation_threshold" => "0.5"})

    # Point ntfy at a URL that will fail fast (no server), so :httpc returns
    # quickly with a connection-refused error. The worker must not crash.
    Application.put_env(:baud_flow, :ntfy_url, "http://127.0.0.1:1")
    Application.put_env(:baud_flow, :ntfy_topic, "baudflow-test")

    on_exit(fn ->
      Application.delete_env(:baud_flow, :ntfy_url)
      Application.delete_env(:baud_flow, :ntfy_topic)
    end)

    :ok
  end

  # source defaults to "scheduled" so rows participate in the 7-day avg query
  # (which filters out source == "manual"). Without an explicit source, the field
  # is NULL and SQL `NULL != "manual"` evaluates to FALSE, excluding the row.
  defp insert_measurement!(attrs) do
    defaults = %{
      timestamp: DateTime.utc_now(),
      ping_latency: 10.0,
      download_bandwidth: 1_000_000,
      upload_bandwidth: 500_000,
      server_name: "TestServer",
      server_location: "TestCity",
      source: "scheduled",
      result_id: Ecto.UUID.generate()
    }

    {:ok, m} = Measurements.create_measurement(Map.merge(defaults, attrs))
    m
  end

  describe "perform/1 - no alert (above threshold)" do
    test "does not crash and returns :ok when measurement is above threshold" do
      now = DateTime.utc_now()

      # Seed 7-day average: 7 measurements at 100 Mbps each -> avg = 100 Mbps
      for i <- 1..7 do
        ts = DateTime.add(now, -(i * 3600), :second)

        insert_measurement!(%{
          timestamp: ts,
          download_bandwidth: round(100.0 / 0.000008),
          result_id: "avg-#{i}"
        })
      end

      # New measurement at 80 Mbps - well above 100 * 0.5 = 50 Mbps threshold
      current =
        insert_measurement!(%{
          download_bandwidth: round(80.0 / 0.000008),
          result_id: "current-ok"
        })

      # The worker should succeed without attempting an alert (the :httpc call
      # to 127.0.0.1:1 would fail, but we never reach it because 80 > 50).
      assert :ok = perform_job(NotificationWorker, %{"measurement_id" => current.id})
    end
  end

  describe "perform/1 - alert triggered (below threshold)" do
    test "does not crash even when :httpc fails (ntfy unreachable)" do
      now = DateTime.utc_now()

      # Seed 7-day average: 100 Mbps
      for i <- 1..7 do
        ts = DateTime.add(now, -(i * 3600), :second)

        insert_measurement!(%{
          timestamp: ts,
          download_bandwidth: round(100.0 / 0.000008),
          result_id: "avg-#{i}"
        })
      end

      # New measurement at 20 Mbps - below 100 * 0.5 = 50 Mbps -> alert triggered
      current =
        insert_measurement!(%{
          download_bandwidth: round(20.0 / 0.000008),
          result_id: "current-low"
        })

      # The :httpc call to 127.0.0.1:1 will fail, but the worker catches it
      # and still returns :ok - a hung/unreachable ntfy must not crash the worker.
      assert :ok = perform_job(NotificationWorker, %{"measurement_id" => current.id})
    end
  end

  describe "perform/1 - edge cases" do
    test "returns :ok when no 7-day history exists (avg is nil)" do
      # No seed data at all - seven_day_avg returns nil -> no alert attempted.
      current =
        insert_measurement!(%{
          download_bandwidth: round(10.0 / 0.000008),
          result_id: "solo"
        })

      assert :ok = perform_job(NotificationWorker, %{"measurement_id" => current.id})
    end

    test "excludes manual measurements from the 7-day average" do
      now = DateTime.utc_now()

      # Only manual measurements exist - avg should be nil, no alert.
      for i <- 1..3 do
        ts = DateTime.add(now, -(i * 3600), :second)

        insert_measurement!(%{
          timestamp: ts,
          download_bandwidth: round(100.0 / 0.000008),
          source: "manual",
          result_id: "manual-#{i}"
        })
      end

      current =
        insert_measurement!(%{
          download_bandwidth: round(10.0 / 0.000008),
          result_id: "current-manual-ctx"
        })

      assert :ok = perform_job(NotificationWorker, %{"measurement_id" => current.id})
    end
  end

  describe "seven_day_avg/0" do
    test "returns nil when no measurements exist" do
      assert NotificationWorker.seven_day_avg() == nil
    end

    test "computes average excluding manual entries" do
      now = DateTime.utc_now()

      # Two scheduled measurements at 100 Mbps
      for i <- 1..2 do
        ts = DateTime.add(now, -(i * 3600), :second)

        insert_measurement!(%{
          timestamp: ts,
          download_bandwidth: round(100.0 / 0.000008),
          result_id: "sched-#{i}"
        })
      end

      # One manual measurement at 200 Mbps - should be excluded
      insert_measurement!(%{
        timestamp: DateTime.add(now, -3600, :second),
        download_bandwidth: round(200.0 / 0.000008),
        source: "manual",
        result_id: "manual-avg"
      })

      avg = NotificationWorker.seven_day_avg()
      assert avg != nil
      # Should be ~100 Mbps (only the two scheduled entries)
      assert_in_delta avg, 100.0, 1.0
    end

    test "excludes measurements older than 7 days" do
      now = DateTime.utc_now()

      # Old measurement (10 days ago) at 200 Mbps
      insert_measurement!(%{
        timestamp: DateTime.add(now, -10 * 24 * 3600, :second),
        download_bandwidth: round(200.0 / 0.000008),
        result_id: "old-avg"
      })

      # Recent measurement (1 day ago) at 100 Mbps
      insert_measurement!(%{
        timestamp: DateTime.add(now, -24 * 3600, :second),
        download_bandwidth: round(100.0 / 0.000008),
        result_id: "recent-avg"
      })

      avg = NotificationWorker.seven_day_avg()
      assert avg != nil
      assert_in_delta avg, 100.0, 1.0
    end
  end
end
