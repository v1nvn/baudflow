defmodule BaudflowWeb.RunsLiveTest do
  use BaudflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Baudflow.Runs

  describe "mount" do
    test "renders runs page with empty state", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/runs")
      assert html =~ "Run History"
      assert html =~ "No runs recorded yet"
    end
  end

  describe "displaying runs" do
    test "shows successful runs with View link", %{conn: conn} do
      {:ok, measurement} =
        Baudflow.Measurements.create_measurement(
          valid_measurement_attrs(result_id: "run-test-result-1")
        )

      started = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
      {:ok, run} = Runs.complete_run(started, measurement.id, 42)

      {:ok, lv, _html} = live(conn, ~p"/runs")
      html = render(lv)

      assert has_element?(lv, "#runs-table")
      assert html =~ "success"
      assert has_element?(lv, "a[href='/results/#{measurement.id}?ref=runs']")
      assert html =~ ~s(phx-hook="LocalTime")
      refute html =~ " UTC"
    end

    test "shows failed runs with error message", %{conn: conn} do
      started = DateTime.utc_now() |> DateTime.add(-30, :second) |> DateTime.truncate(:second)
      {:ok, _run} = Runs.fail_run(started, "Connection refused", 99, "failure")

      {:ok, lv, _html} = live(conn, ~p"/runs")
      html = render(lv)

      assert html =~ "failure"
      assert html =~ "Connection refused"
      assert has_element?(lv, ".status-pill.error")
    end

    test "shows timeout runs with warning badge", %{conn: conn} do
      started = DateTime.utc_now() |> DateTime.add(-120, :second) |> DateTime.truncate(:second)
      {:ok, _run} = Runs.fail_run(started, "Speedtest timed out after 120s", 100, "timeout")

      {:ok, lv, _html} = live(conn, ~p"/runs")
      html = render(lv)

      assert html =~ "timeout"
      assert has_element?(lv, ".status-pill.warning")
    end

    test "shows summary stat cards", %{conn: conn} do
      started = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, m} =
        Baudflow.Measurements.create_measurement(valid_measurement_attrs(result_id: "stat-run-1"))

      Runs.complete_run(started, m.id, 1)
      Runs.fail_run(started, "error", 2, "failure")
      Runs.fail_run(started, "timed out", 3, "timeout")

      {:ok, lv, _html} = live(conn, ~p"/runs")
      html = render(lv)

      assert html =~ "Success"
      assert html =~ "Failed"
      assert html =~ "Timeout"
    end

    test "shows duration for completed runs", %{conn: conn} do
      started = DateTime.utc_now() |> DateTime.add(-45, :second) |> DateTime.truncate(:second)

      {:ok, m} =
        Baudflow.Measurements.create_measurement(valid_measurement_attrs(result_id: "dur-run-1"))

      Runs.complete_run(started, m.id, 10)

      {:ok, lv, _html} = live(conn, ~p"/runs")
      html = render(lv)

      assert html =~ "s</span>"
    end
  end

  describe "pagination" do
    test "paginates when runs exceed per_page (20)", %{conn: conn} do
      for i <- 1..25 do
        started =
          DateTime.utc_now() |> DateTime.add(-i * 60, :second) |> DateTime.truncate(:second)

        Runs.fail_run(started, "test error #{i}", i, "failure")
      end

      {:ok, lv, _html} = live(conn, ~p"/runs")
      assert render(lv) =~ "Page 1 of 2"

      {:ok, lv2, html2} = live(conn, ~p"/runs?page=2")
      assert html2 =~ "Page 2 of 2"
      assert html2 =~ "Prev"
    end
  end

  describe "invalid page param" do
    test "falls back to page 1 for non-numeric ?page= instead of crashing", %{conn: conn} do
      # Pre-fix this raised ArgumentError in String.to_integer/1; the success
      # of live/2 (returning {:ok, _}) is itself the regression assertion.
      {:ok, _lv, html} = live(conn, ~p"/runs?page=abc")

      assert html =~ "Run History"
      assert html =~ "No runs recorded yet"
    end

    test "clamps negative ?page= to page 1 instead of crashing", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/runs?page=-5")

      assert html =~ "Run History"
      assert html =~ "No runs recorded yet"
    end
  end

  # --- Helpers ---

  defp valid_measurement_attrs(overrides) do
    %{
      timestamp:
        Keyword.get(overrides, :timestamp, DateTime.utc_now() |> DateTime.truncate(:second)),
      ping_latency: Keyword.get(overrides, :ping_latency, 12.5),
      ping_jitter: Keyword.get(overrides, :ping_jitter, 1.2),
      ping_low: Keyword.get(overrides, :ping_low, 10.0),
      ping_high: Keyword.get(overrides, :ping_high, 15.0),
      download_bandwidth: Keyword.get(overrides, :download_bandwidth, 10_000_000),
      upload_bandwidth: Keyword.get(overrides, :upload_bandwidth, 5_000_000),
      download_bytes: Keyword.get(overrides, :download_bytes, 50_000_000),
      upload_bytes: Keyword.get(overrides, :upload_bytes, 25_000_000),
      download_elapsed: Keyword.get(overrides, :download_elapsed, 5000),
      upload_elapsed: Keyword.get(overrides, :upload_elapsed, 5000),
      packet_loss: Keyword.get(overrides, :packet_loss, 0.0),
      result_id: Keyword.get(overrides, :result_id, "test-result-1"),
      result_url: Keyword.get(overrides, :result_url, "https://www.speedtest.net/result/test"),
      source: Keyword.get(overrides, :source, "scheduled"),
      server_name: Keyword.get(overrides, :server_name, "TestServer"),
      server_location: Keyword.get(overrides, :server_location, "TestCity"),
      server_country: Keyword.get(overrides, :server_country, "TestCountry"),
      server_host: Keyword.get(overrides, :server_host, "test.host.com"),
      isp: Keyword.get(overrides, :isp, "TestISP"),
      speedtest_version: Keyword.get(overrides, :speedtest_version, "1.0.0")
    }
  end
end
