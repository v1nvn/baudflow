defmodule BaudflowWeb.PingLive do
  @moduledoc """
  The ping dashboard - ping's first-class home, paralleling the Ookla
  `DashboardLive`. Runs a manual TCP-connect ping, streams per-sample progress
  to the `PingViz` hook, and plots ping-typed history on `PingChart`.

  Deliberately ping-only: it ignores Ookla results (the converse of the main
  dashboard's `test_type != "ookla"` guard) so a speed test never perturbs the
  ping chart/hero.
  """

  use BaudflowWeb, :live_view

  alias Baudflow.Measurements
  alias Baudflow.Measurements.Measurement
  alias Baudflow.Scheduling
  alias Baudflow.TestRunners.RunnerWorker

  @time_ranges ~w(24h 7d 30d)
  @default_time_range "7d"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Baudflow.PubSub, "measurements")
    end

    time_range = persisted_time_range(get_connect_params(socket))

    {:ok,
     socket
     |> assign(:chart_points, chart_points())
     |> assign(:test_running, false)
     |> assign(:ping_panel_open, false)
     |> assign(:active_page, :ping)
     |> assign(:page_title, "Ping")
     |> load_range(time_range)}
  end

  # `?run=1` launches a manual ping on landing (from the dashboard's split
  # button). handle_params is the canonical place for param-driven actions - it
  # reliably receives the query string on full loads AND live navigation (mount's
  # params can miss it on a `navigate`). Enqueue once (connected + not already
  # running), then strip the param so a refresh can't re-trigger it.
  @impl true
  def handle_params(%{"run" => "1"}, _uri, socket) do
    cond do
      connected?(socket) and not socket.assigns.test_running ->
        {:noreply, socket |> start_ping() |> push_patch(to: ~p"/ping")}

      connected?(socket) ->
        {:noreply, push_patch(socket, to: ~p"/ping")}

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  # The ping page is ping-only - Ookla results never touch its chart/hero.
  def handle_info({:result, %{test_type: test_type}}, socket) when test_type != "ping" do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ping_progress, data}, socket) do
    {:noreply, push_event(socket, "ping_progress", data)}
  end

  # The ping page subscribes to the shared "measurements" topic, so it also
  # receives Ookla progress and health-eval broadcasts it has no view for. Swallow
  # both (handled only so they aren't logged as crashes) - the live speedtest viz
  # and health heatmap live elsewhere.
  @impl true
  def handle_info({:speedtest_progress, _type, _data}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:health, _id, _transition}, socket), do: {:noreply, socket}

  @impl true
  # On completion the run stops but the panel stays open showing the final
  # readout (frozen PingViz) until the user dismisses it or runs again.
  def handle_info({:result, measurement}, socket) do
    {:noreply,
     socket
     |> assign(:test_running, false)
     |> assign(:latest_measurement, measurement)
     |> assign(
       :measurements,
       [measurement | socket.assigns.measurements]
       |> Enum.take(socket.assigns.chart_points)
     )
     |> push_event("append_point", %{point: serialize_point(measurement)})
     |> push_event("ping_complete", %{})}
  end

  # `:test_failed` / `:test_timeout` are untyped on the shared "measurements"
  # topic - guard on `test_running` so a stray Ookla failure can't falsely end a
  # ping run (the dashboard has the same exposure; typed failures are future work).
  @impl true
  def handle_info({:test_failed, reason}, socket) do
    if socket.assigns.test_running do
      {:noreply,
       socket
       |> put_flash(:error, "Ping failed: #{reason}")
       |> assign(:test_running, false)
       |> push_event("ping_complete", %{})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:test_timeout, socket) do
    if socket.assigns.test_running do
      {:noreply,
       socket
       |> put_flash(:error, "Ping timed out")
       |> assign(:test_running, false)
       |> push_event("ping_complete", %{})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("run_ping", _params, socket) do
    {:noreply, start_ping(socket)}
  end

  # Dismiss the live panel back to the hero (the latest result is already in the
  # chart/history).
  @impl true
  def handle_event("close_ping_panel", _params, socket),
    do: {:noreply, assign(socket, :ping_panel_open, false)}

  @impl true
  def handle_event("set_range", %{"range" => range}, socket) when range in @time_ranges do
    {:noreply,
     socket
     |> load_range(range)
     |> push_event("range_changed", %{range: range})}
  end

  def handle_event("set_range", _params, socket), do: {:noreply, socket}

  # Open the panel, arm the safety net, and tell the PingViz hook to reset its
  # samples (so a re-run from the open panel animates from scratch).
  defp start_ping(socket) do
    enqueue_ping()

    socket
    |> assign(:test_running, true)
    |> assign(:ping_panel_open, true)
    |> push_event("ping_start", %{})
  end

  defp enqueue_ping do
    %{source: "manual", test_type: "ping"}
    |> RunnerWorker.new(unique: RunnerWorker.manual_unique())
    |> Oban.insert()

    # Safety net only - every outcome broadcasts {:result,_} or {:test_failed,_}
    # first. Fire after the ping SLA plus a margin so a hung job can't strand the
    # view in its running state.
    Process.send_after(self(), :test_timeout, RunnerWorker.timeout_ms("ping") + 10_000)

    :ok
  end

  defp load_range(socket, time_range) do
    measurements = fetch_measurements(time_range)
    latest = List.first(measurements)
    thresholds = %{ping: ping_threshold(time_range)}

    socket
    |> assign(:time_range, time_range)
    |> assign(:measurements, measurements)
    |> assign(:latest_measurement, latest)
    |> assign(:chart_config, %{thresholds: thresholds})
    |> push_chart_data(measurements, thresholds)
  end

  defp fetch_measurements(time_range) do
    since = time_range_to_datetime(time_range)
    Measurements.list_since(since, limit: chart_points(), test_type: "ping")
  end

  defp push_chart_data(socket, measurements, thresholds) do
    push_event(socket, "chart_data", %{
      results: serialize_for_chart(measurements),
      thresholds: thresholds
    })
  end

  # The ping threshold line for `PingChart`, mode-aware like the dashboard's
  # `chart_thresholds`: absolute draws the configured ms line, auto draws the
  # visible-window ping median, off draws nothing.
  defp ping_threshold(time_range) do
    case Scheduling.global_thresholds().mode do
      :absolute -> threshold_or_nil("threshold_ping")
      :auto -> Measurements.window_median(time_range_to_datetime(time_range), "ping").ping
      :off -> nil
    end
  end

  defp threshold_or_nil(key) do
    case Baudflow.Settings.get_float(key, 0.0) do
      v when is_number(v) and v > 0 -> v
      _ -> nil
    end
  end

  # The persisted range arrives via connect_params (see app.js). On the
  # disconnected render connect_params is empty, so the default is used.
  defp persisted_time_range(connect_params) do
    case connect_params["time_range"] do
      range when range in @time_ranges -> range
      _ -> @default_time_range
    end
  end

  defp time_range_to_datetime("24h"), do: DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
  defp time_range_to_datetime("7d"), do: DateTime.add(DateTime.utc_now(), -7 * 24 * 3600, :second)

  defp time_range_to_datetime("30d"),
    do: DateTime.add(DateTime.utc_now(), -30 * 24 * 3600, :second)

  defp time_range_to_datetime(_), do: DateTime.add(DateTime.utc_now(), -7 * 24 * 3600, :second)

  defp chart_points, do: Baudflow.Settings.get_integer("dashboard_points", 500)

  # A ping result with a real latency is "latest"; a failed ping (nil latency)
  # renders a muted state instead of crashing on a nil Float.round.
  defp has_ping_data?(%Measurement{ping_latency: value}) when is_number(value), do: true
  defp has_ping_data?(_), do: false

  defp serialize_for_chart(measurements), do: Enum.map(measurements, &serialize_point/1)

  defp serialize_point(m) do
    %{
      timestamp: DateTime.to_iso8601(m.timestamp),
      download_mbps: m.download_mbps,
      upload_mbps: m.upload_mbps,
      ping_latency: m.ping_latency,
      ping_jitter: m.ping_jitter,
      ping_low: m.ping_low,
      ping_high: m.ping_high,
      download_jitter: m.download_jitter,
      upload_jitter: m.upload_jitter,
      packet_loss: m.packet_loss,
      download_elapsed: m.download_elapsed,
      upload_elapsed: m.upload_elapsed,
      failed: m.failed
    }
  end
end
