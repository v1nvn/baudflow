defmodule BaudFlow.Measurements.NotificationWorker do
  @moduledoc """
  Oban worker that checks for bandwidth degradation after each measurement.

  Compares the measurement's `download_mbps` against the 7-day rolling average
  (excluding manual entries). If the value falls below `avg * threshold`, sends
  an alert via ntfy using `:httpc` with hard timeouts.

  The actual HTTP call is isolated in `send_ntfy/1` so tests can override it
  via `Mox` or by asserting the function was reached without hitting a real server.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query

  alias BaudFlow.Measurements
  alias BaudFlow.Measurements.Measurement
  alias BaudFlow.Repo
  alias BaudFlow.Settings

  @impl true
  def perform(%Oban.Job{args: %{"measurement_id" => id}}) do
    measurement = Measurements.get_measurement!(id)

    threshold =
      Settings.get("degradation_threshold")
      |> String.to_float()

    avg_download = seven_day_avg()

    if avg_download && measurement.download_mbps < avg_download * threshold do
      send_alert(measurement, avg_download)
    end

    # Also alert if absolute thresholds flag the measurement as unhealthy
    if measurement.healthy == false do
      send_threshold_alert(measurement)
    end

    :ok
  end

  @doc """
  Computes the 7-day average download Mbps, excluding manual entries.
  Returns `nil` when there are no qualifying measurements.
  """
  def seven_day_avg do
    seven_days_ago = DateTime.add(DateTime.utc_now(), -7 * 24 * 3600, :second)

    Repo.one(
      from m in Measurement,
        where: m.timestamp > ^seven_days_ago and m.source != "manual",
        select: avg(m.download_mbps)
    )
  end

  defp send_alert(measurement, avg_download) do
    message = """
    Speed degradation detected!

    Current: #{Float.round(measurement.download_mbps, 1)} Mbps
    7-day avg: #{Float.round(avg_download, 1)} Mbps
    Server: #{measurement.server_name} (#{measurement.server_location})
    """

    ntfy_url = Application.get_env(:baud_flow, :ntfy_url, "http://ntfy-svc.ntfy")
    ntfy_topic = Application.get_env(:baud_flow, :ntfy_topic, "baudflow")

    send_ntfy(ntfy_url, ntfy_topic, message)
  end

  defp send_threshold_alert(measurement) do
    failed =
      measurement.benchmarks
      |> Enum.filter(fn {_, %{"passed" => p}} -> not p end)
      |> Enum.map_join("\n", fn {metric, %{"value" => v, "threshold" => t, "unit" => u}} ->
        "#{String.capitalize(to_string(metric))}: #{Float.round(v, 1)} vs #{Float.round(t, 1)} #{u}"
      end)

    message = """
    Absolute threshold exceeded!

    #{failed}
    Server: #{measurement.server_name} (#{measurement.server_location})
    """

    ntfy_url = Application.get_env(:baud_flow, :ntfy_url, "http://ntfy-svc.ntfy")
    ntfy_topic = Application.get_env(:baud_flow, :ntfy_topic, "baudflow")

    send_ntfy(ntfy_url, ntfy_topic, message)
  end

  @doc """
  Sends a notification to ntfy via `:httpc`. Isolated as a public function so
  tests can assert whether it was reached (by overriding with a test helper or
  checking side effects) without requiring a running ntfy server.

  Uses hard timeouts: `timeout: 5_000`, `connect_timeout: 2_000` - a hung ntfy
  must not block the worker's queue slot indefinitely.
  """
  def send_ntfy(url, topic, message) do
    # Ensure :inets is running (idempotent) so :httpc is available.
    Application.ensure_all_started(:inets)

    :httpc.request(
      :post,
      {~c"#{url}/#{topic}", [{~c"Title", ~c"Baudflow Alert"}, {~c"Priority", ~c"high"}],
       ~c"text/plain", ~c"#{message}"},
      [timeout: 5_000, connect_timeout: 2_000],
      []
    )
  end
end
