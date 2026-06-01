defmodule BaudFlow.Measurements.SpeedtestWorkerTest do
  use BaudFlow.DataCase, async: true
  use Oban.Testing, repo: BaudFlow.Repo

  alias BaudFlow.Measurements
  alias BaudFlow.Measurements.SpeedtestWorker

  describe "perform/1 - success" do
    test "stores a measurement and broadcasts on success" do
      Phoenix.PubSub.subscribe(BaudFlow.PubSub, "measurements")

      assert :ok = perform_job(SpeedtestWorker, %{"server_id" => nil})

      assert_receive {:result, %{download_mbps: mbps}} when mbps > 0
      assert [_] = Measurements.list_recent(limit: 10)
    end

    test "records a successful run" do
      perform_job(SpeedtestWorker, %{"server_id" => nil})

      measurements = Measurements.list_recent(limit: 1)
      assert length(measurements) == 1

      # Verify a run was recorded - query directly since we don't have a list function
      measurement = hd(measurements)

      run =
        BaudFlow.Repo.one(from r in BaudFlow.Runs.Run, where: r.measurement_id == ^measurement.id)

      assert run != nil
      assert run.status == "success"
    end

    test "enqueues a NotificationWorker job" do
      perform_job(SpeedtestWorker, %{"server_id" => nil})

      assert_enqueued(worker: BaudFlow.Measurements.NotificationWorker)
    end

    test "enqueues a BenchmarkWorker job" do
      perform_job(SpeedtestWorker, %{"server_id" => nil})

      assert_enqueued(worker: BaudFlow.Measurements.BenchmarkWorker)
    end

    test "parses Ookla JSON fields correctly" do
      perform_job(SpeedtestWorker, %{"server_id" => nil})

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
      original_bin = Application.get_env(:baud_flow, :speedtest_bin)

      # Create a failing fake that exits 1
      failing_bin = Path.join(System.tmp_dir!(), "fake_speedtest_fail")
      File.write!(failing_bin, "#!/bin/sh\necho 'boom' >&2\nexit 1\n")
      File.chmod!(failing_bin, 0o755)

      try do
        Application.put_env(:baud_flow, :speedtest_bin, failing_bin)

        assert {:error, _} = perform_job(SpeedtestWorker, %{"server_id" => nil})

        run =
          BaudFlow.Repo.one(
            from r in BaudFlow.Runs.Run,
              where: r.status == "failure",
              order_by: [desc: r.id],
              limit: 1
          )

        assert run != nil
        assert run.status == "failure"
      after
        Application.put_env(:baud_flow, :speedtest_bin, original_bin)
        File.rm(failing_bin)
      end
    end
  end

  describe "perform/1 - timeout" do
    test "records a timeout run when the CLI exits 124" do
      original_bin = Application.get_env(:baud_flow, :speedtest_bin)

      # Create a fake that exits 124 (simulating OS timeout kill)
      timeout_bin = Path.join(System.tmp_dir!(), "fake_speedtest_timeout")
      File.write!(timeout_bin, "#!/bin/sh\nexit 124\n")
      File.chmod!(timeout_bin, 0o755)

      try do
        Application.put_env(:baud_flow, :speedtest_bin, timeout_bin)

        assert {:error, :timeout} = perform_job(SpeedtestWorker, %{"server_id" => nil})

        run =
          BaudFlow.Repo.one(
            from r in BaudFlow.Runs.Run,
              where: r.status == "timeout",
              order_by: [desc: r.id],
              limit: 1
          )

        assert run != nil
        assert run.status == "timeout"
        assert run.error =~ "timed out"
      after
        Application.put_env(:baud_flow, :speedtest_bin, original_bin)
        File.rm(timeout_bin)
      end
    end
  end
end
