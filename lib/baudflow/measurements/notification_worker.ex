defmodule Baudflow.Measurements.NotificationWorker do
  @moduledoc """
  Oban worker that checks for bandwidth degradation after each measurement.

  Compares the measurement's `download_mbps` against the 7-day rolling average
  (excluding manual entries). If the value falls below `avg * threshold`, sends
  an alert via ntfy using `Req` with hard timeouts.

  The HTTP call is isolated in `send_ntfy/3` so tests can stub it with
  `Req.Test` (configured via the `:baudflow, :ntfy_plug` app env) without
  hitting a real server.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias Baudflow.Measurements
  alias Baudflow.Settings

  @impl true
  def perform(%Oban.Job{args: %{"measurement_id" => id}}) do
    measurement = Measurements.get_measurement!(id)

    threshold = Settings.get_float("degradation_threshold", 0.5)

    avg_download = Measurements.rolling_average(7)

    if avg_download && measurement.download_mbps < avg_download * threshold do
      send_alert(measurement, avg_download)
    end

    # Also alert if absolute thresholds flag the measurement as unhealthy
    if measurement.healthy == false do
      send_threshold_alert(measurement)
    end

    :ok
  end

  defp send_alert(measurement, avg_download) do
    message = """
    Speed degradation detected!

    Current: #{Float.round(measurement.download_mbps, 1)} Mbps
    7-day avg: #{Float.round(avg_download, 1)} Mbps
    Server: #{measurement.server_name} (#{measurement.server_location})
    """

    ntfy_url = Application.get_env(:baudflow, :ntfy_url, "http://ntfy-svc.ntfy")
    ntfy_topic = Application.get_env(:baudflow, :ntfy_topic, "baudflow")

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

    ntfy_url = Application.get_env(:baudflow, :ntfy_url, "http://ntfy-svc.ntfy")
    ntfy_topic = Application.get_env(:baudflow, :ntfy_topic, "baudflow")

    send_ntfy(ntfy_url, ntfy_topic, message)
  end

  @doc """
  Sends a notification to ntfy via `Req`. Isolated as a public function so
  tests can assert it was reached (by configuring a `Req.Test` plug via the
  `:baudflow, :ntfy_plug` app env) without requiring a running ntfy server.

  Uses hard timeouts: `receive_timeout: 5_000`, `connect_options: [timeout: 2_000]` -
  a hung ntfy must not block the worker's queue slot indefinitely.

  Returns `:ok` on a successful post, `:error` otherwise. A failure never
  raises - the calling Oban job must not crash on an unreachable ntfy.
  """
  def send_ntfy(url, topic, message) do
    options =
      [
        url: "#{url}/#{topic}",
        method: :post,
        body: message,
        headers: [{"Title", "Baudflow Alert"}, {"Priority", "high"}],
        receive_timeout: 5_000,
        connect_options: [timeout: 2_000]
      ] ++ plug_option()

    case Req.post(options) do
      {:ok, %Req.Response{status: status}} when status < 400 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("ntfy post returned non-success status: #{status}")
        :error

      {:error, exception} ->
        Logger.warning("ntfy post failed: #{Exception.message(exception)}")
        :error
    end
  end

  defp plug_option do
    case Application.get_env(:baudflow, :ntfy_plug) do
      nil -> []
      plug -> [plug: plug]
    end
  end
end
