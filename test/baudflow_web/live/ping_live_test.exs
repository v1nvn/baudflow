defmodule BaudflowWeb.PingLiveTest do
  use BaudflowWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  use Oban.Testing, repo: Baudflow.Repo

  alias Baudflow.Measurements
  alias Baudflow.TestRunners.RunnerWorker

  describe "mount" do
    test "renders the empty state and Run Ping control with no data", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/ping")

      assert html =~ "No pings yet"
      assert has_element?(lv, "#run-ping-btn")
      assert has_element?(lv, "button[phx-click='set_range']")
    end

    test "pushes chart_data with existing ping measurements and renders the chart", %{conn: conn} do
      {:ok, m} =
        Measurements.create_measurement(
          ping_attrs(
            timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
            result_id: "ping-chart-1"
          )
        )

      {:ok, lv, _html} = live(conn, ~p"/ping")

      assert_push_event(lv, "chart_data", %{results: results, thresholds: _})
      assert length(results) == 1

      [point] = results
      assert point.timestamp == DateTime.to_iso8601(m.timestamp)
      assert point.ping_latency == m.ping_latency
      assert point.ping_jitter == m.ping_jitter

      assert has_element?(lv, "#ping-chart[phx-hook='PingChart']")
    end

    test "renders the latest ping latency in the hero", %{conn: conn} do
      Measurements.create_measurement(
        ping_attrs(
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          ping_latency: 17.4,
          result_id: "ping-hero-1"
        )
      )

      {:ok, _lv, html} = live(conn, ~p"/ping")
      assert html =~ "17.4"
    end
  end

  describe "running a ping" do
    test "?run=1 auto-enqueues a ping job and shows the live panel", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/ping?run=1")

      assert_enqueued(worker: Baudflow.TestRunners.RunnerWorker)

      [job] = all_enqueued(worker: Baudflow.TestRunners.RunnerWorker)
      assert job.args["test_type"] == "ping"
      assert job.args["source"] == "manual"

      # The auto-run flips the page into its running state — the live viz mounts.
      assert has_element?(lv, "#ping-viz[phx-hook='PingViz']")
    end

    test "clicking Run Ping enqueues a ping job", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/ping")

      # Consume the initial chart_data push
      assert_push_event(lv, "chart_data", _)

      lv
      |> element("#run-ping-btn")
      |> render_click()

      [job] = all_enqueued(worker: Baudflow.TestRunners.RunnerWorker)
      assert job.args["test_type"] == "ping"
    end

    # A manual ping is debounced only while one is queued/executing — a completed
    # run must NOT block an immediate re-run (the fast ping would otherwise sit
    # "running" for the whole unique window). See RunnerWorker.manual_unique/0.
    test "a completed manual ping doesn't dedupe an immediate re-run", %{conn: _conn} do
      {:ok, _job_a} =
        %{source: "manual", test_type: "ping"}
        |> RunnerWorker.new(unique: RunnerWorker.manual_unique())
        |> Oban.insert()

      # Simulate Oban having run it to completion.
      Baudflow.Repo.update_all(Oban.Job, set: [state: "completed"])

      {:ok, job_b} =
        %{source: "manual", test_type: "ping"}
        |> RunnerWorker.new(unique: RunnerWorker.manual_unique())
        |> Oban.insert()

      assert job_b.state == "available"
    end
  end

  describe "handle_info" do
    test "pushes ping_progress to the client", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/ping")
      assert_push_event(lv, "chart_data", _)

      Phoenix.PubSub.broadcast(
        Baudflow.PubSub,
        "measurements",
        {:ping_progress, sample_progress()}
      )

      assert_push_event(lv, "ping_progress", %{sample: 1, latency: 12.3, avg: 12.3})
    end

    test "a ping result appends a chart point and resolves the run", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/ping")
      assert_push_event(lv, "chart_data", _)

      {:ok, m} =
        Measurements.create_measurement(
          ping_attrs(
            timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
            ping_latency: 9.5,
            result_id: "ping-result-1"
          )
        )

      Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", {:result, m})

      latency = m.ping_latency
      ts = DateTime.to_iso8601(m.timestamp)

      assert_push_event(lv, "append_point", %{point: %{ping_latency: ^latency, timestamp: ^ts}})
      assert_push_event(lv, "ping_complete", %{})
    end

    test "an Ookla result is ignored — only a ping result appends a point", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/ping")
      assert_push_event(lv, "chart_data", _)

      # An Ookla result, then a ping result — broadcast in order. If the Ookla
      # result were handled, it would append first; the first append_point must
      # instead be the ping's, proving the `test_type != "ping"` guard dropped it.
      # NB: the Ookla fixture is a complete Ookla shape (download + upload) — a
      # half-formed one would crash a concurrent dashboard LiveView over the
      # shared "measurements" topic (Float.round on a nil upload).
      {:ok, ookla} =
        Measurements.create_measurement(
          ping_attrs(ping_latency: 99.9, result_id: "ookla-ignore-1")
          |> Map.put(:test_type, "ookla")
          |> Map.put(:download_bandwidth, 10_000_000)
          |> Map.put(:upload_bandwidth, 5_000_000)
        )

      {:ok, ping} =
        Measurements.create_measurement(
          ping_attrs(
            ping_latency: 9.5,
            timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
            result_id: "ping-after-ookla-1"
          )
        )

      Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", {:result, ookla})
      Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", {:result, ping})

      latency = ping.ping_latency
      assert_push_event(lv, "append_point", %{point: %{ping_latency: ^latency}})
    end

    test "ignores Ookla progress and health broadcasts without crashing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/ping")
      assert_push_event(lv, "chart_data", _)

      # Both ride the shared "measurements" topic but the ping page has no view
      # for either — it must no-op them rather than crash the LiveView.
      Phoenix.PubSub.broadcast(
        Baudflow.PubSub,
        "measurements",
        {:speedtest_progress, "download", %{}}
      )

      Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", {:health, 1, :breach})

      assert render(lv) =~ "Run Ping"
    end
  end

  describe "live panel" do
    test "stays open after the run completes, offering Run Again and Close", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/ping")
      assert_push_event(lv, "chart_data", _)

      lv
      |> element("#run-ping-btn")
      |> render_click()

      assert has_element?(lv, "#ping-viz")

      {:ok, m} =
        Measurements.create_measurement(ping_attrs(ping_latency: 9.5, result_id: "panel-stay-1"))

      Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", {:result, m})

      # The run is over but the panel persists (frozen result); the spinner is
      # replaced by Run Again / Close.
      assert has_element?(lv, "#ping-viz")
      assert has_element?(lv, "#run-again-btn")
      assert has_element?(lv, "#close-ping-panel")
    end

    test "Close dismisses the panel back to the hero", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/ping")
      assert_push_event(lv, "chart_data", _)

      lv
      |> element("#run-ping-btn")
      |> render_click()

      {:ok, m} =
        Measurements.create_measurement(ping_attrs(ping_latency: 9.5, result_id: "panel-close-1"))

      Phoenix.PubSub.broadcast(Baudflow.PubSub, "measurements", {:result, m})

      lv
      |> element("#close-ping-panel")
      |> render_click()

      refute has_element?(lv, "#ping-viz")
      # Hero is back, with its Run Ping button.
      assert has_element?(lv, "#run-ping-btn")
    end
  end

  describe "time range selector" do
    test "7d button is active by default", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/ping")

      assert has_element?(lv, "button[phx-value-range='7d'][class*='active']")
    end
  end

  # --- Helpers ---

  defp ping_attrs(overrides) do
    %{
      timestamp:
        Keyword.get(overrides, :timestamp, DateTime.utc_now() |> DateTime.truncate(:second)),
      ping_latency: Keyword.get(overrides, :ping_latency, 12.5),
      ping_jitter: Keyword.get(overrides, :ping_jitter, 1.2),
      ping_low: Keyword.get(overrides, :ping_low, 8.0),
      ping_high: Keyword.get(overrides, :ping_high, 20.0),
      packet_loss: Keyword.get(overrides, :packet_loss, 0.0),
      result_id: Keyword.get(overrides, :result_id, "ping-result-1"),
      test_type: "ping"
    }
  end

  defp sample_progress do
    %{
      sample: 1,
      total: 5,
      attempted: 1,
      received: 1,
      latency: 12.3,
      avg: 12.3,
      jitter: 0.0,
      loss: 0.0,
      host: "1.1.1.1",
      port: 443
    }
  end
end
