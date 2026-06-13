defmodule BaudflowWeb.DashboardLive do
  use BaudflowWeb, :live_view

  alias Baudflow.Measurements
  alias Baudflow.Measurements.ServerDiscovery
  alias Baudflow.Measurements.SpeedtestWorker

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Baudflow.PubSub, "measurements")
    end

    time_range = "7d"
    measurements = fetch_measurements(time_range)
    averages = Measurements.window_averages()

    {:ok,
     socket
     |> assign(:measurements, measurements)
     |> assign(:latest_measurement, List.first(measurements))
     |> assign(:chart_points, chart_points())
     |> assign(:averages, averages)
     |> assign(:test_running, false)
     |> assign(:active_page, :dashboard)
     |> assign(:page_title, "Dashboard")
     |> assign(:time_range, time_range)
     |> assign(:selected_server_id, "auto")
     |> assign(:available_servers, [])
     |> assign(:servers_loaded, false)
     |> push_chart_data(measurements, averages)}
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
     |> push_event("speedtest_complete", %{})}
  end

  @impl true
  def handle_info({:speedtest_progress, type, data}, socket) do
    {:noreply,
     socket
     |> assign(:test_running, true)
     |> push_event("speedtest_progress", %{type: type, data: data})}
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
  def handle_event("set_range", %{"range" => range}, socket) do
    measurements = fetch_measurements(range)
    averages = Measurements.window_averages()

    {:noreply,
     socket
     |> assign(:time_range, range)
     |> assign(:measurements, measurements)
     |> assign(:latest_measurement, List.first(measurements))
     |> assign(:averages, averages)
     |> push_chart_data(measurements, averages)}
  end

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
    if SpeedtestWorker.binary_available?() do
      server_id =
        cond do
          socket.assigns.selected_server_id == "auto" -> nil
          socket.assigns.selected_server_id != "" -> socket.assigns.selected_server_id
          true -> nil
        end

      %{
        server_id: server_id,
        source: "manual"
      }
      |> SpeedtestWorker.new(unique: [period: 300])
      |> Oban.insert()

      # Auto-reset loading state after 2 minutes (speedtest timeout)
      Process.send_after(self(), :test_timeout, 120_000)

      {:noreply, assign(socket, :test_running, true)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "speedtest CLI not found - install it from speedtest.net")}
    end
  end

  defp fetch_measurements(time_range) do
    since = time_range_to_datetime(time_range)
    Measurements.list_since(since, limit: chart_points())
  end

  defp time_range_to_datetime("24h"), do: DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
  defp time_range_to_datetime("7d"), do: DateTime.add(DateTime.utc_now(), -7 * 24 * 3600, :second)

  defp time_range_to_datetime("30d"),
    do: DateTime.add(DateTime.utc_now(), -30 * 24 * 3600, :second)

  defp time_range_to_datetime(_), do: DateTime.add(DateTime.utc_now(), -7 * 24 * 3600, :second)

  defp chart_points do
    Baudflow.Settings.get_integer("dashboard_points", 500)
  end

  defp push_chart_data(socket, measurements, averages) do
    push_event(socket, "chart_data", %{
      results: serialize_for_chart(measurements),
      averages: averages
    })
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
      upload_elapsed: m.upload_elapsed
    }
  end
end
