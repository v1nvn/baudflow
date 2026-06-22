defmodule BaudflowWeb.DashboardLiveTest do
  use BaudflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  use Oban.Testing, repo: Baudflow.Repo

  alias Baudflow.Measurements

  describe "mount" do
    test "renders dashboard page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Run Test"
    end

    test "pushes chart_data event on mount", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "chart_data", %{
        results: [],
        averages: %{avg_7d: nil, avg_30d: nil}
      })
    end

    test "pushes the current-month heatmap tile on mount", %{conn: conn} do
      # Verdict derives JIT; absolute mode + a 50 Mbps threshold the 80 Mbps
      # result clears so today's cell is "healthy".
      Baudflow.Settings.update_all(%{
        "threshold_mode" => "absolute",
        "threshold_download" => "50"
      })

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _m} =
        Measurements.create_measurement(valid_attrs(timestamp: now, result_id: "hm-dash-1"))

      {:ok, lv, _html} = live(conn, ~p"/")

      today = Date.to_iso8601(DateTime.to_date(now))

      assert_push_event(lv, "heatmap_tile:heatmap-dashboard", %{cells: cells})

      assert Enum.any?(cells, &(&1.d == today and &1.v == "healthy"))
    end

    test "pushes chart_data with existing measurements", %{conn: conn} do
      {:ok, m} =
        Measurements.create_measurement(
          valid_attrs(
            timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
            result_id: "dash-test-1"
          )
        )

      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "chart_data", %{results: results, averages: _averages})
      assert length(results) == 1

      [point] = results
      assert point.timestamp == DateTime.to_iso8601(m.timestamp)
      assert point.download_mbps == m.download_mbps
      assert point.upload_mbps == m.upload_mbps
      assert point.ping_latency == m.ping_latency
      assert point.ping_jitter == m.ping_jitter
      assert point.ping_low == m.ping_low
      assert point.ping_high == m.ping_high
      assert point.download_jitter == m.download_jitter
      assert point.upload_jitter == m.upload_jitter
      assert point.packet_loss == m.packet_loss
      assert point.download_elapsed == m.download_elapsed
      assert point.upload_elapsed == m.upload_elapsed
    end

    test "renders latest result card when measurements exist", %{conn: conn} do
      Measurements.create_measurement(
        valid_attrs(
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          result_id: "card-test-1"
        )
      )

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Download"
    end

    test "renders all 6 chart hook containers", %{conn: conn} do
      create_recent_measurement("chart-hook-test")

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#speed-chart[phx-hook='SpeedChart']")
      assert has_element?(lv, "#ping-chart[phx-hook='PingChart']")
      assert has_element?(lv, "#jitter-chart[phx-hook='JitterChart']")
      assert has_element?(lv, "#ping-detail-chart[phx-hook='PingDetailChart']")
      assert has_element?(lv, "#packet-loss-chart[phx-hook='PacketLossChart']")
      assert has_element?(lv, "#duration-chart[phx-hook='DurationChart']")
    end

    test "renders all 6 chart canvases", %{conn: conn} do
      create_recent_measurement("chart-canvas-test")

      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#speed-chart-canvas")
      assert has_element?(lv, "#ping-chart-canvas")
      assert has_element?(lv, "#jitter-chart-canvas")
      assert has_element?(lv, "#ping-detail-chart-canvas")
      assert has_element?(lv, "#packet-loss-chart-canvas")
      assert has_element?(lv, "#duration-chart-canvas")
    end

    test "shows empty state when no measurements exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "No measurements yet"
    end

    test "renders dashboard controls and empty state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#run-test-btn")
      assert has_element?(lv, "button[phx-click='set_range']")
    end
  end

  describe "time range selector" do
    test "renders time range buttons", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "button[phx-click='set_range'][phx-value-range='24h']")
      assert has_element?(lv, "button[phx-click='set_range'][phx-value-range='7d']")
      assert has_element?(lv, "button[phx-click='set_range'][phx-value-range='30d']")
    end

    test "7d button is active by default", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "button[phx-value-range='7d'][class*='active']")
    end

    test "set_range event pushes chart_data with filtered results", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      # Consume the initial chart_data push
      assert_push_event(lv, "chart_data", _)

      lv
      |> element("button[phx-value-range='24h']")
      |> render_click()

      assert_push_event(lv, "chart_data", %{results: results, averages: _averages})
      assert results == []
    end

    test "set_range updates active button", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "chart_data", _)

      lv
      |> element("button[phx-value-range='24h']")
      |> render_click()

      assert has_element?(lv, "button[phx-value-range='24h'][class*='active']")
      refute has_element?(lv, "button[phx-value-range='7d'][class*='active']")
    end

    # #5 — the dashboard range is a per-browser preference stored in localStorage
    # and replayed via connect_params (see app.js), so the server queries the right
    # window on first render with no flash.

    test "honors the persisted time range from connect_params on mount", %{conn: conn} do
      # connect_params carry the localStorage value the client would replay — see
      # `get_connect_params/1` in mount and app.js `readSavedTimeRange`.
      {:ok, lv, _html} =
        conn
        |> get(~p"/")
        |> put_connect_params(%{"time_range" => "30d"})
        |> live()

      assert has_element?(lv, "button[phx-value-range='30d'][class*='active']")
      refute has_element?(lv, "button[phx-value-range='7d'][class*='active']")
    end

    test "falls back to 7d when the persisted range is unknown", %{conn: conn} do
      {:ok, lv, _html} =
        conn
        |> get(~p"/")
        |> put_connect_params(%{"time_range" => "bogus"})
        |> live()

      assert has_element?(lv, "button[phx-value-range='7d'][class*='active']")
      refute has_element?(lv, "button[phx-value-range='30d'][class*='active']")
    end

    test "set_range pushes range_changed so the client can persist it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "chart_data", _)

      lv
      |> element("button[phx-value-range='24h']")
      |> render_click()

      assert_push_event(lv, "range_changed", %{range: "24h"})
    end

    test "ignores an unknown set_range value without desyncing the buttons", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "chart_data", _)

      # A bogus range (a tampered DOM value) must leave the selection untouched.
      render_click(lv, "set_range", %{"range" => "bogus"})

      assert has_element?(lv, "button[phx-value-range='7d'][class*='active']")
    end
  end

  describe "handle_info {:result, measurement}" do
    test "pushes append_point event when a new result is broadcast", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      # Consume the initial chart_data push
      assert_push_event(lv, "chart_data", _)

      {:ok, m} =
        Measurements.create_measurement(
          valid_attrs(
            timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
            result_id: "broadcast-1"
          )
        )

      Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", {:result, m})

      # Pin values to avoid matching stray broadcasts from concurrent test modules
      dl = m.download_mbps
      ul = m.upload_mbps
      ts = DateTime.to_iso8601(m.timestamp)
      ping_low = m.ping_low
      ping_high = m.ping_high
      download_jitter = m.download_jitter
      upload_jitter = m.upload_jitter
      packet_loss = m.packet_loss
      download_elapsed = m.download_elapsed
      upload_elapsed = m.upload_elapsed

      assert_push_event(lv, "append_point", %{
        point: %{
          download_mbps: ^dl,
          upload_mbps: ^ul,
          timestamp: ^ts,
          ping_low: ^ping_low,
          ping_high: ^ping_high,
          download_jitter: ^download_jitter,
          upload_jitter: ^upload_jitter,
          packet_loss: ^packet_loss,
          download_elapsed: ^download_elapsed,
          upload_elapsed: ^upload_elapsed,
          failed: false
        }
      })
    end
  end

  describe "handle_event run_test" do
    test "enqueues a RunnerWorker job on button click", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      # Consume the initial chart_data push
      assert_push_event(lv, "chart_data", _)

      lv
      |> element("#run-test-btn")
      |> render_click()

      assert_enqueued(worker: Baudflow.TestRunners.RunnerWorker)
    end

    test "shows loading state after clicking Run Test Now", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "chart_data", _)

      lv
      |> element("#run-test-btn")
      |> render_click()

      assert render(lv) =~ "Running..."
    end

    test "enqueued job has source manual", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "chart_data", _)

      lv
      |> element("#run-test-btn")
      |> render_click()

      [job] = all_enqueued(worker: Baudflow.TestRunners.RunnerWorker)
      assert job.args["source"] == "manual"
    end

    test "enqueued job uses auto server by default", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "chart_data", _)

      lv
      |> element("#run-test-btn")
      |> render_click()

      [job] = all_enqueued(worker: Baudflow.TestRunners.RunnerWorker)
      # "auto" selection means server_id is nil in the job args
      assert job.args["server_id"] == nil
    end
  end

  describe "server selection" do
    test "renders server select dropdown", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#server-select")
    end

    test "dropdown has auto option by default", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#server-select option[value='auto']")
    end
  end

  describe "next scheduled test card" do
    test "renders the next run when an enabled schedule exists", %{conn: conn} do
      {:ok, _} = Baudflow.Scheduling.create(%{name: "Minutely", cron: "* * * * *"})

      {:ok, lv, html} = live(conn, ~p"/")

      assert html =~ "Next Scheduled Test"
      assert has_element?(lv, "#next-test-card")
    end

    test "hides the card when no enabled schedules exist", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      refute has_element?(lv, "#next-test-card")
    end
  end

  describe "SLA compliance card" do
    test "renders the compliance percent when a promised speed is configured", %{conn: conn} do
      Baudflow.Settings.update_all(%{"promised_download_mbps" => "200"})

      # an Ookla-shaped measurement at 500 Mbps (well above the 200 promise)
      Measurements.create_measurement(
        valid_attrs(
          download_bandwidth: round(500.0 / 0.000008),
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          result_id: "compliance-1"
        )
      )

      {:ok, lv, html} = live(conn, ~p"/")

      assert html =~ "SLA Compliance"
      assert html =~ "100.0%"
      assert has_element?(lv, "#compliance-card")
    end

    test "hides the compliance card when no promised speed is configured", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      refute has_element?(lv, "#compliance-card")
    end
  end

  describe "chart threshold config" do
    test "chart_data carries the global thresholds in absolute mode", %{conn: conn} do
      Baudflow.Settings.update_all(%{
        "threshold_mode" => "absolute",
        "threshold_download" => "100",
        "threshold_upload" => "40"
      })

      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "chart_data", %{thresholds: thresholds})
      assert thresholds.download == 100.0
      assert thresholds.upload == 40.0
      # A 0 / unset threshold is "none" → nil, so the chart draws no line.
      assert thresholds.ping == nil
    end

    test "chart_data thresholds are all nil when the mode is off", %{conn: conn} do
      Baudflow.Settings.update_all(%{"threshold_mode" => "off"})

      {:ok, lv, _html} = live(conn, ~p"/")

      assert_push_event(lv, "chart_data", %{thresholds: thresholds})
      assert thresholds.download == nil
      assert thresholds.upload == nil
      assert thresholds.ping == nil
    end
  end

  describe "failed latest measurement" do
    test "renders a muted hero without crashing when the newest test failed", %{conn: conn} do
      # an older successful test, then a newer failed one (newest → latest)
      Measurements.create_measurement(
        valid_attrs(timestamp: ~U[2024-01-01 00:00:00Z], result_id: "ok-1")
      )

      Measurements.record_failure(%{
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        test_type: "ookla"
      })

      assert {:ok, _lv, html} = live(conn, ~p"/")

      # The hero shows a failure state, not a crashed render or the empty-state.
      assert html =~ "Last Test Failed"
      refute html =~ "Run your first speedtest"
    end
  end

  # --- Helpers ---

  defp valid_attrs(overrides \\ []) do
    %{
      timestamp: Keyword.get(overrides, :timestamp, ~U[2024-01-01 00:00:00Z]),
      ping_latency: Keyword.get(overrides, :ping_latency, 12.5),
      ping_jitter: Keyword.get(overrides, :ping_jitter, 1.2),
      ping_low: Keyword.get(overrides, :ping_low, 8.0),
      ping_high: Keyword.get(overrides, :ping_high, 20.0),
      download_bandwidth: Keyword.get(overrides, :download_bandwidth, 10_000_000),
      upload_bandwidth: Keyword.get(overrides, :upload_bandwidth, 5_000_000),
      download_jitter: Keyword.get(overrides, :download_jitter, 3.5),
      upload_jitter: Keyword.get(overrides, :upload_jitter, 2.8),
      packet_loss: Keyword.get(overrides, :packet_loss, 0.0),
      download_elapsed: Keyword.get(overrides, :download_elapsed, 5000),
      upload_elapsed: Keyword.get(overrides, :upload_elapsed, 4000),
      result_id: Keyword.get(overrides, :result_id, "test-result-1"),
      source: Keyword.get(overrides, :source, "scheduled")
    }
  end

  defp create_recent_measurement(result_id) do
    {:ok, m} =
      Measurements.create_measurement(
        valid_attrs(
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          result_id: result_id
        )
      )

    m
  end
end
