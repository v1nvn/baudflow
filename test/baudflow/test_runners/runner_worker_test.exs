defmodule Baudflow.TestRunners.RunnerWorkerTest do
  # async: false — the failure/timeout sub-tests temporarily flip the global
  # :speedtest_bin env var to point at a throwaway script. Any concurrent test
  # that runs Ookla (pipeline_test) or probes binary_available? (dashboard) would
  # read the flipped value. Serializing this file isolates the flips.
  use Baudflow.DataCase, async: false
  use Oban.Testing, repo: Baudflow.Repo

  alias Baudflow.Measurements
  alias Baudflow.TestRunners.RunnerWorker

  import Baudflow.Test.TcpListener

  describe "perform/1 - success" do
    test "stores a measurement and broadcasts on success" do
      Phoenix.PubSub.subscribe(Baudflow.PubSub, "measurements")

      assert :ok = perform_job(RunnerWorker, %{"server_id" => nil, "test_type" => "ookla"})

      assert_receive {:result, %{download_mbps: mbps}} when mbps > 0
      assert [_] = Measurements.list_recent(limit: 10)
    end

    test "records a successful run" do
      perform_job(RunnerWorker, %{"server_id" => nil, "test_type" => "ookla"})

      measurements = Measurements.list_recent(limit: 1)
      assert length(measurements) == 1

      measurement = hd(measurements)

      run =
        Baudflow.Repo.one(from r in Baudflow.Runs.Run, where: r.measurement_id == ^measurement.id)

      assert run != nil
      assert run.status == "success"
    end

    test "stamps the measurement with its test_type" do
      perform_job(RunnerWorker, %{"server_id" => nil, "test_type" => "ookla"})

      [m] = Measurements.list_recent(limit: 1)
      assert m.test_type == "ookla"
    end

    test "enqueues a HealthWorker job" do
      perform_job(RunnerWorker, %{"server_id" => nil, "test_type" => "ookla"})

      assert_enqueued(worker: Baudflow.Health.HealthWorker)
    end

    test "parses Ookla JSON fields correctly" do
      perform_job(RunnerWorker, %{"server_id" => nil, "test_type" => "ookla"})

      [m] = Measurements.list_recent(limit: 1)
      # The fake outputs bandwidth 6384715 → 6384715 * 0.000008 = 51.08
      assert_in_delta m.download_mbps, 51.08, 0.01
      # Upload bandwidth 3615276 → 3615276 * 0.000008 = 28.92
      assert_in_delta m.upload_mbps, 28.92, 0.01
      assert m.ping_latency == 9.937
      assert m.source == "scheduled"
    end
  end

  describe "perform/1 - failure" do
    test "records a failure run when the CLI exits non-zero" do
      original_bin = Application.get_env(:baudflow, :speedtest_bin)

      failing_bin = Path.join(System.tmp_dir!(), "fake_speedtest_fail")
      File.write!(failing_bin, "#!/bin/sh\necho 'boom' >&2\nexit 1\n")
      File.chmod!(failing_bin, 0o755)

      try do
        Application.put_env(:baudflow, :speedtest_bin, failing_bin)

        Phoenix.PubSub.subscribe(Baudflow.PubSub, "measurements")

        assert {:error, _} =
                 perform_job(RunnerWorker, %{"server_id" => nil, "test_type" => "ookla"})

        # Every failure path must emit a terminal broadcast so the UI
        # never depends on a client-side timer.
        assert_receive {:test_failed, reason}
        assert reason =~ "exited with code"

        # A failure is also recorded as a measurement so it shows on the chart
        # timeline instead of a silent gap (failed: true, no speeds).
        assert_receive {:result, %{failed: true, test_type: "ookla"} = failed}
        assert failed.download_mbps == nil

        run =
          Baudflow.Repo.one(
            from r in Baudflow.Runs.Run,
              where: r.status == "failure",
              order_by: [desc: r.id],
              limit: 1
          )

        assert run != nil
        assert run.status == "failure"

        # A failed test routes through HealthWorker → :failed notification (#23).
        assert_enqueued(worker: Baudflow.Health.HealthWorker)
      after
        Application.put_env(:baudflow, :speedtest_bin, original_bin)
        File.rm(failing_bin)
      end
    end
  end

  describe "perform/1 - timeout" do
    test "records a timeout run when the CLI exits 124" do
      original_bin = Application.get_env(:baudflow, :speedtest_bin)

      timeout_bin = Path.join(System.tmp_dir!(), "fake_speedtest_timeout")
      File.write!(timeout_bin, "#!/bin/sh\nexit 124\n")
      File.chmod!(timeout_bin, 0o755)

      try do
        Application.put_env(:baudflow, :speedtest_bin, timeout_bin)

        Phoenix.PubSub.subscribe(Baudflow.PubSub, "measurements")

        assert {:error, :timeout} =
                 perform_job(RunnerWorker, %{"server_id" => nil, "test_type" => "ookla"})

        # The timeout path must emit a terminal broadcast so the UI
        # never depends on a client-side timer.
        assert_receive {:test_failed, reason}
        assert reason =~ "Timed out"

        # A timeout is a failure — it lands on the timeline as a failed point.
        assert_receive {:result, %{failed: true, test_type: "ookla"}}

        run =
          Baudflow.Repo.one(
            from r in Baudflow.Runs.Run,
              where: r.status == "timeout",
              order_by: [desc: r.id],
              limit: 1
          )

        assert run != nil
        assert run.status == "timeout"
        assert run.error =~ "timed out"

        # A timeout routes through HealthWorker → :failed notification (#23).
        assert_enqueued(worker: Baudflow.Health.HealthWorker)
      after
        Application.put_env(:baudflow, :speedtest_bin, original_bin)
        File.rm(timeout_bin)
      end
    end
  end

  describe "perform/1 - ping success" do
    # The Ping runner dispatches through the same pipeline as Ookla — this is
    # what proves the TestRunner abstraction. Ping measures TCP-handshake RTT,
    # so it's pointed at a real localhost listener; a result carries latency but
    # no bandwidth, so download_mbps/upload_mbps stay nil.
    test "stores a ping measurement with latency and no bandwidth" do
      {port, listen} = start()

      try do
        Phoenix.PubSub.subscribe(Baudflow.PubSub, "measurements")

        assert :ok =
                 perform_job(RunnerWorker, %{
                   "test_type" => "ping",
                   "target_host" => "127.0.0.1",
                   "target_port" => port,
                   "duration_seconds" => 1
                 })

        assert_receive {:result, %{test_type: "ping"} = m}
        assert is_float(m.ping_latency) and m.ping_latency >= 0.0
        assert is_float(m.ping_low) and m.ping_low >= 0.0
        assert is_float(m.ping_high) and m.ping_high >= 0.0
        assert is_float(m.ping_jitter) and m.ping_jitter >= 0.0
        assert m.packet_loss == 0.0
        assert m.download_mbps == nil
        assert m.upload_mbps == nil
        assert m.source == "scheduled"
      after
        stop(listen)
      end
    end

    test "enqueues a HealthWorker job for a ping measurement" do
      {port, listen} = start()

      try do
        perform_job(RunnerWorker, %{
          "test_type" => "ping",
          "target_host" => "127.0.0.1",
          "target_port" => port,
          "duration_seconds" => 1
        })

        assert_enqueued(worker: Baudflow.Health.HealthWorker)
      after
        stop(listen)
      end
    end
  end

  describe "perform/1 - ping failure" do
    # Every TCP connect failing (nothing listening on the port) routes through
    # the same failure path an unreachable host used to under ICMP.
    test "records a failure run when every connect fails" do
      port = closed_port()

      Phoenix.PubSub.subscribe(Baudflow.PubSub, "measurements")

      assert {:error, _} =
               perform_job(RunnerWorker, %{
                 "test_type" => "ping",
                 "target_host" => "127.0.0.1",
                 "target_port" => port,
                 "duration_seconds" => 1
               })

      # Every failure path must emit a terminal broadcast so the UI never
      # depends on a client-side timer.
      assert_receive {:test_failed, reason}
      assert reason =~ "TCP connect failed"

      # A ping failure is recorded as a failed measurement tagged ping.
      assert_receive {:result, %{failed: true, test_type: "ping"}}

      run =
        Baudflow.Repo.one(
          from r in Baudflow.Runs.Run,
            where: r.status == "failure",
            order_by: [desc: r.id],
            limit: 1
        )

      assert run != nil
      assert run.status == "failure"

      # A ping failure routes through HealthWorker → :failed notification (#23).
      assert_enqueued(worker: Baudflow.Health.HealthWorker)
    end
  end
end
