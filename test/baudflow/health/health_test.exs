defmodule Baudflow.HealthTest do
  use ExUnit.Case, async: true

  alias Baudflow.Health
  alias Baudflow.Measurements.Measurement
  alias Baudflow.Scheduling.Schedule

  # Pure unit tests — build structs directly (no DB), all threshold fields
  # explicit so thresholds_for never falls back to Settings.
  defp schedule(opts) do
    struct!(Schedule,
      threshold_enabled: true,
      breach_streak: 0,
      download: 0.0,
      upload: 0.0,
      ping: 0.0
    )
    |> struct!(opts)
  end

  defp measurement(opts) do
    struct!(Measurement, download_mbps: 50.0, upload_mbps: 25.0, ping_latency: 10.0)
    |> struct!(opts)
  end

  describe "evaluate/2 - thresholds disabled" do
    test "returns nil healthy/benchmarks and no transition" do
      {healthy, benchmarks, transition} =
        Health.evaluate(measurement([]), schedule(threshold_enabled: false, download: 100.0))

      assert healthy == nil
      assert benchmarks == nil
      assert transition == nil
    end
  end

  describe "evaluate/2 - passing" do
    test "all pass → healthy, :healthy from a clean streak" do
      {true, benchmarks, :healthy} =
        Health.evaluate(measurement([]), schedule(download: 25.0, upload: 10.0, ping: 50.0))

      assert benchmarks.download.passed
      assert benchmarks.upload.passed
      assert benchmarks.ping.passed
    end

    test "unset (0) thresholds are skipped; only set ones are checked" do
      {true, benchmarks, :healthy} =
        Health.evaluate(measurement([]), schedule(download: 25.0))

      assert Map.has_key?(benchmarks, :download)
      refute Map.has_key?(benchmarks, :upload)
      refute Map.has_key?(benchmarks, :ping)
    end
  end

  describe "evaluate/2 - breach" do
    test "download below → unhealthy, :breach from a clean streak" do
      {false, benchmarks, :breach} = Health.evaluate(measurement([]), schedule(download: 100.0))

      refute benchmarks.download.passed
      assert benchmarks.download.threshold == 100.0
    end

    test "ping above → unhealthy" do
      {false, _, :breach} = Health.evaluate(measurement([]), schedule(ping: 5.0))
    end

    test "already breaching (streak > 0) → nil transition, no re-breach" do
      {false, _, nil} =
        Health.evaluate(measurement([]), schedule(download: 100.0, breach_streak: 2))
    end
  end

  describe "evaluate/2 - recovery" do
    test "healthy after a breach streak → :recovered" do
      {true, _, :recovered} =
        Health.evaluate(measurement([]), schedule(download: 25.0, breach_streak: 3))
    end
  end

  describe "evaluate/2 - nil measurement value (a ping result)" do
    # A ping measurement has no bandwidth: its download_mbps/upload_mbps are nil.
    # A threshold check needs both a threshold AND a value — a nil value must
    # skip (not raise `nil >= threshold`), so only the ping check evaluates.
    test "skips checks whose value is nil, evaluating only checks with a value" do
      {healthy, benchmarks, transition} =
        Health.evaluate(
          measurement(download_mbps: nil, upload_mbps: nil, ping_latency: 15.0),
          schedule(download: 100.0, ping: 50.0)
        )

      assert healthy == true
      assert transition == :healthy
      refute Map.has_key?(benchmarks, :download)
      refute Map.has_key?(benchmarks, :upload)
      assert benchmarks.ping.passed
    end
  end
end
