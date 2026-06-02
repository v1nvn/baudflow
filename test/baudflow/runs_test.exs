defmodule Baudflow.RunsTest do
  use Baudflow.DataCase, async: true

  alias Baudflow.Measurements
  alias Baudflow.Runs
  alias Baudflow.Runs.Run

  describe "complete_run/3" do
    test "creates a successful run" do
      started_at = ~U[2024-01-01 00:00:00Z]
      {:ok, measurement} = Measurements.create_measurement(measurement_attrs())
      oban_job_id = 99

      assert {:ok, %Run{} = run} =
               Runs.complete_run(started_at, measurement.id, oban_job_id)

      assert run.status == "success"
      assert run.started_at == started_at
      assert run.measurement_id == measurement.id
      assert run.oban_job_id == oban_job_id
      assert run.completed_at != nil
    end
  end

  describe "fail_run/4" do
    test "creates a failed run with status failure" do
      started_at = ~U[2024-01-01 00:00:00Z]

      assert {:ok, %Run{} = run} =
               Runs.fail_run(started_at, "something broke", 99, "failure")

      assert run.status == "failure"
      assert run.error == "something broke"
      assert run.oban_job_id == 99
      assert run.completed_at != nil
    end

    test "creates a timed-out run with status timeout" do
      started_at = ~U[2024-01-01 00:00:00Z]

      assert {:ok, %Run{} = run} =
               Runs.fail_run(started_at, "exceeded 120s", 100, "timeout")

      assert run.status == "timeout"
      assert run.error == "exceeded 120s"
    end
  end

  defp measurement_attrs do
    %{
      timestamp: ~U[2024-01-01 00:00:00Z],
      ping_latency: 12.5,
      download_bandwidth: 10_000_000,
      upload_bandwidth: 5_000_000,
      result_id: "run-test-measurement",
      source: "scheduled"
    }
  end
end
