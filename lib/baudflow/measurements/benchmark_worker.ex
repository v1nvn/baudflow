defmodule Baudflow.Measurements.BenchmarkWorker do
  @moduledoc """
  Oban worker that compares a measurement against configurable absolute thresholds
  and sets the `healthy` and `benchmarks` fields accordingly.

  Threshold settings (stored as strings in the settings table):
  - `threshold_enabled` - "true" or "false" (default "false")
  - `threshold_download` - minimum download Mbps (default "0", meaning disabled)
  - `threshold_upload` - minimum upload Mbps (default "0", meaning disabled)
  - `threshold_ping` - maximum ping ms (default "0", meaning disabled)
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Baudflow.Measurements
  alias Baudflow.Settings

  @impl true
  def perform(%Oban.Job{args: %{"measurement_id" => id}}) do
    measurement = Measurements.get_measurement!(id)
    settings = Settings.get_all()

    enabled = settings["threshold_enabled"] == "true"

    {healthy, benchmarks} =
      if enabled do
        evaluate(measurement, settings)
      else
        {nil, nil}
      end

    Measurements.update_health(measurement, healthy, benchmarks)

    if healthy == false do
      broadcast_unhealthy(measurement.id)
    end

    :ok
  end

  defp evaluate(measurement, settings) do
    download_threshold = parse_float(settings["threshold_download"])
    upload_threshold = parse_float(settings["threshold_upload"])
    ping_threshold = parse_float(settings["threshold_ping"])

    checks = []

    checks =
      if download_threshold > 0 do
        passed = measurement.download_mbps >= download_threshold

        checks ++
          [
            {:download,
             %{
               passed: passed,
               value: measurement.download_mbps,
               threshold: download_threshold,
               unit: "Mbps"
             }}
          ]
      else
        checks
      end

    checks =
      if upload_threshold > 0 do
        passed = measurement.upload_mbps >= upload_threshold

        checks ++
          [
            {:upload,
             %{
               passed: passed,
               value: measurement.upload_mbps,
               threshold: upload_threshold,
               unit: "Mbps"
             }}
          ]
      else
        checks
      end

    checks =
      if ping_threshold > 0 do
        passed = measurement.ping_latency <= ping_threshold

        checks ++
          [
            {:ping,
             %{
               passed: passed,
               value: measurement.ping_latency,
               threshold: ping_threshold,
               unit: "ms"
             }}
          ]
      else
        checks
      end

    if checks == [] do
      {nil, nil}
    else
      all_passed = Enum.all?(checks, fn {_, %{passed: p}} -> p end)
      benchmarks = Map.new(checks)
      {all_passed, benchmarks}
    end
  end

  defp parse_float(nil), do: 0.0
  defp parse_float(""), do: 0.0

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(val) when is_number(val), do: val / 1.0

  defp broadcast_unhealthy(measurement_id) do
    Phoenix.PubSub.broadcast(
      Baudflow.PubSub,
      "measurements",
      {:benchmarked, measurement_id, false}
    )
  end
end
