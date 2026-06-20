defmodule Baudflow.Health do
  @moduledoc """
  Pure health evaluation: a measurement vs its schedule's thresholds, producing
  a `{healthy, benchmarks, transition}` triple. The single place a health
  transition is computed. Thresholds come through `Scheduling.thresholds_for/1`
  — the one threshold reader.
  """

  alias Baudflow.Measurements.Measurement
  alias Baudflow.Scheduling
  alias Baudflow.Scheduling.Schedule

  @type transition :: :healthy | :breach | :recovered | nil

  @doc """
  Evaluate a measurement against its schedule's thresholds.

  Returns `{healthy, benchmarks, transition}`. `transition` is the state change
  vs the schedule's prior breach streak: `:breach` on the first breach,
  `:recovered` on return to healthy, `:healthy` while steady, `nil` while still
  breaching (no change) or when thresholds are off.
  """
  @spec evaluate(Measurement.t(), Schedule.t()) :: {boolean() | nil, map() | nil, transition()}
  def evaluate(%Measurement{} = measurement, %Schedule{} = schedule) do
    thresholds = Scheduling.thresholds_for(schedule)
    {healthy, benchmarks} = evaluate_thresholds(measurement, thresholds)
    transition = compute_transition(healthy, schedule.breach_streak)
    {healthy, benchmarks, transition}
  end

  defp evaluate_thresholds(_measurement, %{enabled: false}), do: {nil, nil}

  defp evaluate_thresholds(measurement, %{enabled: true} = thresholds) do
    checks =
      []
      |> maybe_check(
        :download,
        thresholds.download,
        measurement.download_mbps,
        &Kernel.>=/2,
        "Mbps"
      )
      |> maybe_check(:upload, thresholds.upload, measurement.upload_mbps, &Kernel.>=/2, "Mbps")
      |> maybe_check(:ping, thresholds.ping, measurement.ping_latency, &Kernel.<=/2, "ms")

    if checks == [] do
      {nil, nil}
    else
      all_passed = Enum.all?(checks, fn {_, %{passed: p}} -> p end)
      {all_passed, Map.new(checks)}
    end
  end

  # A check needs both a threshold and a measurement value. Skip when the value
  # is nil (a ping result has no bandwidth, so its download/upload checks can't
  # run — and `nil >= threshold` would raise) or when the threshold is unset.
  defp maybe_check(acc, _name, threshold, value, _compare, _unit)
       when is_nil(value) or not is_number(threshold) or threshold <= 0,
       do: acc

  defp maybe_check(acc, name, threshold, value, compare, unit) do
    passed = compare.(value, threshold)
    acc ++ [{name, %{passed: passed, value: value, threshold: threshold, unit: unit}}]
  end

  defp compute_transition(nil, _prior), do: nil
  defp compute_transition(false, 0), do: :breach
  defp compute_transition(true, prior) when prior > 0, do: :recovered
  defp compute_transition(true, _prior), do: :healthy
  defp compute_transition(false, _prior), do: nil
end
