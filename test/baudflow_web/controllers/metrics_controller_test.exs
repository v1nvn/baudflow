defmodule BaudflowWeb.MetricsControllerTest do
  use BaudflowWeb.ConnCase, async: true

  alias Baudflow.Measurements

  describe "GET /metrics" do
    test "serves Prometheus text exposition with the right content type" do
      conn = get(build_conn(), "/metrics")

      assert conn.status == 200
      [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "text/plain")
      assert response(conn, 200) =~ "# TYPE baudflow_measurements_total gauge"
    end

    test "reports 0 total and NaN gauges on an empty store" do
      body = get(build_conn(), "/metrics") |> response(200)

      assert body =~ "baudflow_measurements_total 0"
      assert body =~ "baudflow_download_mbps NaN"
      assert body =~ "baudflow_uptime_percentage NaN"
      # No verdict yet → no health line.
      refute body =~ "baudflow_health"
    end

    test "reflects the latest Ookla speeds, count, and uptime" do
      {:ok, m} =
        Measurements.create_measurement(%{
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          download_mbps: 421.5,
          upload_mbps: 22.1,
          ping_latency: 14.3,
          result_id: "metrics-1",
          source: "scheduled"
        })

      {:ok, _} = Measurements.update_health(m, true, nil)

      body = get(build_conn(), "/metrics") |> response(200)

      assert body =~ "baudflow_download_mbps 421.5"
      assert body =~ "baudflow_upload_mbps 22.1"
      assert body =~ "baudflow_ping_latency_ms 14.3"
      assert body =~ "baudflow_health 1"
      assert body =~ "baudflow_measurements_total 1"
      assert body =~ "baudflow_uptime_percentage 100.0"
    end

    test "NaN speed gauges and no health line when the latest test failed" do
      Measurements.record_failure(%{
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        test_type: "ookla"
      })

      body = get(build_conn(), "/metrics") |> response(200)

      assert body =~ "baudflow_download_mbps NaN"
      assert body =~ "baudflow_measurements_total 1"
      refute body =~ "baudflow_health"
    end
  end
end
