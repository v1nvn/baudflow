defmodule BaudflowWeb.DashboardLive do
  use BaudflowWeb, :live_view

  alias Baudflow.Measurements
  alias Baudflow.Measurements.Measurement
  alias Baudflow.Measurements.ServerDiscovery
  alias Baudflow.Scheduling
  alias Baudflow.TestRunners.RunnerWorker
  alias BaudflowWeb.HeatCalendar

  # The dashboard range is a per-browser preference (#5). Only a known value is
  # honored — a stale or tampered string falls back to the default rather than
  # leaving no button active.
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
     |> assign(:active_page, :dashboard)
     |> assign(:page_title, "Dashboard")
     |> assign(:selected_server_id, "auto")
     |> assign(:available_servers, [])
     |> assign(:servers_loaded, false)
     |> load_range(time_range)}
  end

  @impl true
  # The dashboard is a speed dashboard: ping (and other non-Ookla) results are
  # stored but don't append a speed point here. Separate ping charts come later.
  def handle_info({:result, %{test_type: test_type}}, socket) when test_type != "ookla" do
    {:noreply, socket}
  end

  @impl true
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
     |> push_event("speedtest_complete", %{})
     |> assign_heatmap()}
  end

  @impl true
  def handle_info({:speedtest_progress, type, data}, socket) do
    {:noreply,
     socket
     |> assign(:test_running, true)
     |> push_event("speedtest_progress", %{type: type, data: data})}
  end

  @impl true
  def handle_info({:health, id, _transition}, socket) do
    # HealthWorker evaluated the latest measurement post-result; refetch so the
    # health badge reflects it live (the v1 badge was stale until reload).
    measurement = Measurements.get_measurement!(id)

    socket =
      if(socket.assigns.latest_measurement && socket.assigns.latest_measurement.id == id,
        do: assign(socket, :latest_measurement, measurement),
        else: socket
      )

    # The heatmap reflects ookla tests only, so a ping's health eval can't change
    # a cell — skip the month recompute for non-ookla measurements.
    socket = if measurement.test_type == "ookla", do: assign_heatmap(socket), else: socket

    {:noreply, socket}
  end

  @impl true
  def handle_info({:test_failed, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Speedtest failed: #{reason}")
     |> assign(:test_running, false)
     |> push_event("speedtest_complete", %{})}
  end

  @impl true
  def handle_info(:test_timeout, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Speedtest timed out")
     |> assign(:test_running, false)
     |> push_event("speedtest_complete", %{})}
  end

  @impl true
  def handle_event("set_range", %{"range" => range}, socket) when range in @time_ranges do
    # Confirm the range back to the client so the PersistRange hook can store it
    # in localStorage (#5); the server is the single validator of a known range.
    {:noreply,
     socket
     |> load_range(range)
     |> push_event("range_changed", %{range: range})}
  end

  # A bogus range (a tampered DOM value) must leave the selection untouched
  # rather than load data under a label that matches no button.
  def handle_event("set_range", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("load_servers", _params, socket) do
    preferred = Baudflow.Settings.get_integer_list("preferred_servers")
    blocked = Baudflow.Settings.get_integer_list("blocked_servers")

    discovered = ServerDiscovery.list_available_servers()
    allowed = ServerDiscovery.filter_blocked(discovered, blocked)

    preferred_servers =
      preferred
      |> Enum.map(fn id ->
        case Enum.find(discovered, &(&1[:id] == id)) do
          nil -> %{id: id, name: "Server ##{id}", location: "", country: "", host: ""}
          server -> server
        end
      end)

    all_servers =
      preferred_servers ++
        Enum.reject(allowed, fn s -> s[:id] in preferred end)

    {:noreply,
     socket
     |> assign(:available_servers, all_servers)
     |> assign(:servers_loaded, true)}
  end

  @impl true
  def handle_event("select_server", %{"server_id" => server_id}, socket) do
    {:noreply, assign(socket, :selected_server_id, server_id)}
  end

  @impl true
  def handle_event("run_test", _params, socket) do
    if RunnerWorker.binary_available?() do
      server_id =
        cond do
          socket.assigns.selected_server_id == "auto" -> nil
          socket.assigns.selected_server_id != "" -> socket.assigns.selected_server_id
          true -> nil
        end

      %{
        server_id: server_id,
        source: "manual",
        test_type: "ookla"
      }
      |> RunnerWorker.new(unique: [period: 300])
      |> Oban.insert()

      # Safety net only — every outcome broadcasts {:test_failed,_} or
      # {:result,_} before this. Fire after the worker's worst-case runtime
      # (its own SLA) plus a margin so the net never preempts a real event.
      Process.send_after(self(), :test_timeout, RunnerWorker.timeout_ms() + 10_000)

      {:noreply, assign(socket, :test_running, true)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "speedtest CLI not found - install it from speedtest.net")}
    end
  end

  defp fetch_measurements(time_range) do
    since = time_range_to_datetime(time_range)
    Measurements.list_since(since, limit: chart_points(), test_type: "ookla")
  end

  # Time-range-dependent data + assigns shared by mount and set_range. Both fetch
  # the same window, so this lives in one place — the only difference is how the
  # range arrived (a persisted connect param vs. a click).
  defp load_range(socket, time_range) do
    measurements = fetch_measurements(time_range)
    averages = Measurements.window_averages()
    thresholds = chart_thresholds()

    socket
    |> assign(:time_range, time_range)
    |> assign(:measurements, measurements)
    |> assign(:latest_measurement, List.first(measurements))
    |> assign(:averages, averages)
    |> assign(:chart_config, %{thresholds: thresholds})
    |> assign(:compliance, compute_compliance(time_range))
    |> assign(:next_run, Scheduling.next_run())
    |> push_chart_data(measurements, averages, thresholds)
    |> assign_heatmap()
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

  defp chart_points do
    Baudflow.Settings.get_integer("dashboard_points", 500)
  end

  # SLA compliance over the visible window, driven by the global promised-speed
  # settings (0 = none → `Measurements.compliance/1` returns nil and the card
  # hides). The store never reads Settings; we pass the promises in.
  defp compute_compliance(time_range) do
    Measurements.compliance(
      since: time_range_to_datetime(time_range),
      promised_download: Baudflow.Settings.get_float("promised_download_mbps", 0.0),
      promised_upload: Baudflow.Settings.get_float("promised_upload_mbps", 0.0)
    )
  end

  # Global threshold overlay values for the aggregate speed chart. The dashboard
  # spans all Ookla schedules, so per-schedule thresholds don't map onto one view
  # — we overlay the global `Settings` thresholds (the values `thresholds_for/1`
  # falls back to), gated by `threshold_enabled`. A 0/unset value is "none" → nil,
  # so the chart draws no line for it.
  defp chart_thresholds do
    if Baudflow.Settings.get_boolean("threshold_enabled") do
      %{
        download: threshold_or_nil("threshold_download"),
        upload: threshold_or_nil("threshold_upload"),
        ping: threshold_or_nil("threshold_ping")
      }
    else
      %{download: nil, upload: nil, ping: nil}
    end
  end

  defp threshold_or_nil(key) do
    case Baudflow.Settings.get_float(key, 0.0) do
      v when is_number(v) and v > 0 -> v
      _ -> nil
    end
  end

  # A failed measurement is a valid "latest" (it's the most recent result) but
  # carries no download value — the hero renders a muted failure state instead
  # of crashing on a nil Float.round.
  defp has_speed_data?(%Measurement{download_mbps: value}) when is_number(value),
    do: true

  defp has_speed_data?(_), do: false

  # Best-effort relative hint for the next-test card (recomputed on each render).
  # The authoritative value is the `<.local_time>` exact time, which is always
  # correct; this just reads as a glanceable "in Nm".
  defp relative_to_now(%DateTime{} = at) do
    secs = max(0, DateTime.diff(at, DateTime.utc_now(), :second))

    cond do
      secs < 60 -> "in #{secs}s"
      secs < 3600 -> "in #{div(secs, 60)}m"
      true -> "in #{div(secs, 3600)}h #{rem(div(secs, 60), 60)}m"
    end
  end

  defp push_chart_data(socket, measurements, averages, thresholds) do
    push_event(socket, "chart_data", %{
      results: serialize_for_chart(measurements),
      averages: averages,
      thresholds: thresholds
    })
  end

  # The current-month health heatmap on the dashboard — independent of the
  # speed-chart time range (the calendar spans a month, not the visible window).
  # Recomputed on mount/range change and on each ookla result or health eval so
  # the latest day colors in live (a ping's health eval is skipped — it can't
  # change a cell). The full all-months grid lives at /heatmap.
  defp assign_heatmap(socket) do
    today = Date.utc_today()
    since = HeatCalendar.month_start(today)
    status_by_date = Measurements.daily_health(since: since, test_type: "ookla")
    tile = HeatCalendar.month_matrix(today.year, today.month, status_by_date, "heatmap-dashboard")

    socket
    |> assign(:heatmap_tile, tile)
    |> push_event("heatmap_tile:heatmap-dashboard", %{cells: tile.cells, weeks: tile.weeks})
  end

  defp serialize_for_chart(measurements) do
    Enum.map(measurements, &serialize_point/1)
  end

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
