defmodule Baudflow.HealthTest do
  use ExUnit.Case, async: true

  alias Baudflow.Health
  alias Baudflow.Measurements.Measurement
  alias Baudflow.Scheduling.Schedule

  # Pure unit tests — build structs directly (no DB), all threshold fields
  # explicit so thresholds_for never falls back to Settings.
  defp schedule(opts) do
    struct!(Schedule,
      threshold_mode: "absolute",
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

  describe "evaluate/3 - mode off" do
    test "returns nil healthy/benchmarks and no transition" do
      {healthy, benchmarks, transition} =
        Health.evaluate(measurement([]), schedule(threshold_mode: "off", download: 100.0))

      assert healthy == nil
      assert benchmarks == nil
      assert transition == nil
    end
  end

  describe "evaluate/3 - absolute mode, passing" do
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

  describe "evaluate/3 - absolute mode, breach" do
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

  describe "evaluate/3 - recovery" do
    test "healthy after a breach streak → :recovered" do
      {true, _, :recovered} =
        Health.evaluate(measurement([]), schedule(download: 25.0, breach_streak: 3))
    end
  end

  describe "evaluate/3 - nil measurement value (a ping result)" do
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

  # :auto verdicts are tested via verdict/3 with an explicit thresholds map and a
  # baseline — no schedule/DB needed. ratio 0.7 → speed floor 0.7×median,
  # ping ceiling median/0.7. baseline medians 100/50/10 → floors 70/35, ping 14.3.
  describe "verdict/3 - auto mode" do
    @auto %{mode: :auto, ratio: 0.7, download: 0, upload: 0, ping: 0}
    @baseline %{download: 100.0, upload: 50.0, ping: 10.0}

    test "all above the derived floors → healthy" do
      m = measurement(download_mbps: 90.0, upload_mbps: 45.0, ping_latency: 5.0)
      {healthy, benchmarks} = Health.verdict(m, @auto, @baseline)
      assert healthy == true
      assert benchmarks.download.threshold == 70.0
      assert benchmarks.download.passed
    end

    test "a value below ratio×median breaches" do
      m = measurement(download_mbps: 60.0, upload_mbps: 45.0, ping_latency: 5.0)
      {healthy, benchmarks} = Health.verdict(m, @auto, @baseline)
      assert healthy == false
      refute benchmarks.download.passed
    end

    test "ping breaches above median/ratio" do
      m = measurement(download_mbps: 90.0, upload_mbps: 45.0, ping_latency: 20.0)
      {healthy, benchmarks} = Health.verdict(m, @auto, @baseline)
      assert healthy == false
      refute benchmarks.ping.passed
      assert_in_delta benchmarks.ping.threshold, 10.0 / 0.7, 0.001
    end

    test ":insufficient baseline → no verdict" do
      {healthy, benchmarks} = Health.verdict(measurement([]), @auto, :insufficient)
      assert healthy == nil
      assert benchmarks == nil
    end

    test "a nil value for a metric skips that check" do
      m = measurement(download_mbps: nil, upload_mbps: 45.0, ping_latency: 5.0)
      {healthy, benchmarks} = Health.verdict(m, @auto, @baseline)
      assert healthy == true
      refute Map.has_key?(benchmarks, :download)
    end

    test "tunability: a tighter ratio flips a borderline value to breach (no backfill)" do
      m = measurement(download_mbps: 75.0, upload_mbps: 45.0, ping_latency: 5.0)

      strict = %{mode: :auto, ratio: 0.8, download: 0, upload: 0, ping: 0}
      lax = %{mode: :auto, ratio: 0.7, download: 0, upload: 0, ping: 0}

      {true, _} = Health.verdict(m, lax, @baseline)
      {false, _} = Health.verdict(m, strict, @baseline)
    end
  end
end
