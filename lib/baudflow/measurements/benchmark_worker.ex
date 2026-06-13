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

  require Logger

  alias Baudflow.Measurements
  alias Baudflow.Settings

  @impl true
  def perform(%Oban.Job{args: %{"measurement_id" => id}}) do
    measurement = Measurements.get_measurement!(id)

    enabled = Settings.get_boolean("threshold_enabled")

    {healthy, benchmarks} =
      if enabled do
        evaluate(measurement)
      else
        {nil, nil}
      end

    case Measurements.update_health(measurement, healthy, benchmarks) do
      {:ok, _measurement} ->
        if healthy == false do
          broadcast_unhealthy(measurement.id)
        end

        :ok

      {:error, changeset} ->
        Logger.warning(
          "Failed to update health for measurement #{measurement.id}: #{inspect(changeset.errors)}"
        )

        :ok
    end
  end

  defp evaluate(measurement) do
    download_threshold = Settings.get_float("threshold_download", 0.0)
    upload_threshold = Settings.get_float("threshold_upload", 0.0)
    ping_threshold = Settings.get_float("threshold_ping", 0.0)

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

  defp broadcast_unhealthy(measurement_id) do
    Phoenix.PubSub.broadcast(
      Baudflow.PubSub,
      "measurements",
      {:benchmarked, measurement_id, false}
    )
  end
end
