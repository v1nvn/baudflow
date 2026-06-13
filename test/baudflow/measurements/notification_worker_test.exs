defmodule Baudflow.Measurements.NotificationWorkerTest do
  use Baudflow.DataCase, async: true
  use Oban.Testing, repo: Baudflow.Repo

  alias Baudflow.Measurements
  alias Baudflow.Measurements.NotificationWorker
  alias Baudflow.Settings

  setup do
    Settings.update_all(%{"degradation_threshold" => "0.5"})

    # Route ntfy posts through a Req.Test plug stub instead of a real server.
    # Tests set the per-request behavior with Req.Test.stub/2. A pointlessly
    # invalid URL ensures no real network call ever escapes if a stub is missed.
    Application.put_env(:baudflow, :ntfy_url, "http://ntfy.test")
    Application.put_env(:baudflow, :ntfy_topic, "baudflow-test")
    Application.put_env(:baudflow, :ntfy_plug, {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.delete_env(:baudflow, :ntfy_url)
      Application.delete_env(:baudflow, :ntfy_topic)
      Application.delete_env(:baudflow, :ntfy_plug)
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

  # A successful stub: ntfy accepts the alert.
  defp stub_success do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 200, "")
    end)
  end

  # A failure stub: ntfy returns an error status. The worker must not crash.
  defp stub_failure do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 503, "unavailable")
    end)
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

      # No stub is set, but we never reach send_ntfy because 80 > 50.
      assert :ok = perform_job(NotificationWorker, %{"measurement_id" => current.id})
    end
  end

  describe "perform/1 - alert triggered (below threshold)" do
    test "succeeds when ntfy accepts the post" do
      stub_success()
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

      assert :ok = perform_job(NotificationWorker, %{"measurement_id" => current.id})
    end

    test "does not crash when ntfy returns an error status" do
      stub_failure()
      now = DateTime.utc_now()

      for i <- 1..7 do
        ts = DateTime.add(now, -(i * 3600), :second)

        insert_measurement!(%{
          timestamp: ts,
          download_bandwidth: round(100.0 / 0.000008),
          result_id: "avg-#{i}"
        })
      end

      current =
        insert_measurement!(%{
          download_bandwidth: round(20.0 / 0.000008),
          result_id: "current-low-err"
        })

      # ntfy returns 503, but the worker swallows it and still returns :ok -
      # a degraded ntfy must not crash the worker.
      assert :ok = perform_job(NotificationWorker, %{"measurement_id" => current.id})
    end
  end

  describe "send_ntfy/3" do
    test "returns :ok on a successful post and forwards ntfy headers/body" do
      stub_success()

      Application.put_env(:baudflow, :ntfy_url, "http://ntfy.test")
      Application.put_env(:baudflow, :ntfy_topic, "topic-xyz")

      Req.Test.stub(__MODULE__, fn conn ->
        # The full URL path is url/topic, and ntfy expects the alert text in the body.
        assert conn.method == "POST"
        assert conn.request_path == "/topic-xyz"
        assert Plug.Conn.get_req_header(conn, "title") == ["Baudflow Alert"]
        assert Plug.Conn.get_req_header(conn, "priority") == ["high"]
        body = Req.Test.raw_body(conn)
        assert String.contains?(body, "degradation")

        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert :ok =
               NotificationWorker.send_ntfy("http://ntfy.test", "topic-xyz", "Speed degradation!")
    end

    test "returns :error (without raising) when ntfy returns a failure status" do
      stub_failure()

      assert :error = NotificationWorker.send_ntfy("http://ntfy.test", "baudflow-test", "boom")
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

  describe "perform/1 - 7-day average is sourced from the Measurements context" do
    # NotificationWorker no longer computes the average itself; it calls
    # Measurements.rolling_average(7). The query semantics (exclude manual,
    # last 7 days only) are covered in measurements_test.exs. These tests
    # confirm the worker still behaves correctly given those averages.
    test "returns nil when no measurements exist" do
      assert Measurements.rolling_average(7) == nil
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

      avg = Measurements.rolling_average(7)
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

      avg = Measurements.rolling_average(7)
      assert avg != nil
      assert_in_delta avg, 100.0, 1.0
    end
  end
end
