defmodule BaudflowWeb.MetricsTest do
  use ExUnit.Case, async: true

  alias Baudflow.Measurements.Measurement
  alias BaudflowWeb.Metrics

  # The formatter is pure: it never touches the DB. Feed it a snapshot shaped
  # like Measurements.metrics/0's return and assert the exact exposition lines.

  describe "render/1 with a healthy latest test" do
    test "emits the 8 gauge blocks with help/type/value triplets" do
      latest = %Measurement{
        download_mbps: 421.52,
        upload_mbps: 22.1,
        ping_latency: 14.3,
        ping_jitter: 0.8,
        packet_loss: 0.0,
        healthy: true
      }

      body =
        Metrics.render(%{
          latest: latest,
          total: 1234,
          uptime: %{healthy: 100, total: 102, percent: 98.0}
        })

      assert body =~ "# HELP baudflow_download_mbps"
      assert body =~ "# TYPE baudflow_download_mbps gauge\n"
      assert body =~ "baudflow_download_mbps 421.52"
      assert body =~ "baudflow_upload_mbps 22.1"
      assert body =~ "baudflow_ping_latency_ms 14.3"
      assert body =~ "baudflow_ping_jitter_ms 0.8"
      assert body =~ "baudflow_packet_loss 0.0"
      assert body =~ "baudflow_health 1"
      assert body =~ "baudflow_measurements_total 1234"
      assert body =~ "baudflow_uptime_percentage 98.0"
    end
  end

  describe "render/1 with an unhealthy latest test" do
    test "renders health as 0" do
      body =
        Metrics.render(%{
          latest: %Measurement{download_mbps: 10.0, healthy: false},
          total: 5,
          uptime: %{healthy: 0, total: 5, percent: 0.0}
        })

      assert body =~ "baudflow_health 0"
    end
  end

  describe "render/1 with a failed latest test (nil speeds, healthy nil)" do
    test "emits NaN for the speed gauges and omits the health line" do
      body =
        Metrics.render(%{
          latest: %Measurement{
            download_mbps: nil,
            upload_mbps: nil,
            ping_latency: nil,
            ping_jitter: nil,
            packet_loss: nil,
            healthy: nil
          },
          total: 9,
          uptime: %{healthy: 4, total: 9, percent: 44.4}
        })

      assert body =~ "baudflow_download_mbps NaN"
      assert body =~ "baudflow_upload_mbps NaN"
      assert body =~ "baudflow_ping_latency_ms NaN"
      assert body =~ "baudflow_packet_loss NaN"
      # No verdict → no health line at all.
      refute body =~ "baudflow_health"
      assert body =~ "baudflow_measurements_total 9"
    end
  end

  describe "render/1 with no tests yet" do
    test "emits NaN gauges, 0 total, NaN uptime" do
      body =
        Metrics.render(%{
          latest: nil,
          total: 0,
          uptime: %{healthy: 0, total: 0, percent: nil}
        })

      assert body =~ "baudflow_download_mbps NaN"
      assert body =~ "baudflow_measurements_total 0"
      assert body =~ "baudflow_uptime_percentage NaN"
      refute body =~ "baudflow_health"
    end
  end
end
