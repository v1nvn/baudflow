defmodule Baudflow.Health do
  @moduledoc """
  Pure health evaluation: a measurement vs its thresholds, producing a
  `{healthy, benchmarks}` verdict (and, via `evaluate/3`, a transition triple).

  The single place a health verdict is computed. Two entry points:

    * `verdict/3` - `{healthy, benchmarks}` for a measurement against resolved
      thresholds (+ a baseline in `:auto` mode). Used just-in-time by every
      reader (heatmap, /metrics, dashboard hero, result detail, history filter)
      so verdicts are never stored - change the mode/ratio and every view
      re-derives on the next read.
    * `evaluate/3` - adds a `transition` vs the schedule's prior breach streak,
      for the live `HealthWorker` (events/streak/escalation). Same derivation.

  Mode comes from `Scheduling.thresholds_for/1` (`:auto | :absolute | :off`).
  `:auto` judges each value against the caller-supplied rolling-median baseline
  (`baseline == :insufficient` while there isn't enough history to judge - no
  verdict yet). `:absolute` uses the fixed Mbps/ms thresholds. `:off` yields nil.
  """

  alias Baudflow.Measurements.Measurement
  alias Baudflow.Scheduling
  alias Baudflow.Scheduling.Schedule

  @type transition :: :healthy | :breach | :recovered | nil
  @type baseline ::
          :insufficient
          | %{download: float() | nil, upload: float() | nil, ping: float() | nil}
          | nil

  @doc """
  Verdict for a measurement against resolved `thresholds` (`Scheduling.thresholds_for/1`
  or `global_thresholds/0`), plus a `baseline` map in `:auto` mode (the rolling
  median from `Measurements.trailing_median/2`; `:insufficient` while
  uncalibrated - yields no verdict). Returns `{healthy, benchmarks}`.
  """
  @spec verdict(Measurement.t(), map(), baseline()) :: {boolean() | nil, map() | nil}
  def verdict(%Measurement{} = measurement, thresholds, baseline \\ nil) do
    evaluate_thresholds(measurement, thresholds, baseline)
  end

  @doc """
  Full `{healthy, benchmarks, transition}` for the live worker. `transition` is
  the state change vs the schedule's prior breach streak: `:breach` on the first
  breach, `:recovered` on return to healthy, `:healthy` while steady, `nil`
  while still breaching or when thresholds yield no verdict.
  """
  @spec evaluate(Measurement.t(), Schedule.t(), baseline()) ::
          {boolean() | nil, map() | nil, transition()}
  def evaluate(%Measurement{} = measurement, %Schedule{} = schedule, baseline \\ nil) do
    thresholds = Scheduling.thresholds_for(schedule)
    {healthy, benchmarks} = verdict(measurement, thresholds, baseline)
    transition = compute_transition(healthy, schedule.breach_streak)
    {healthy, benchmarks, transition}
  end

  defp evaluate_thresholds(_measurement, %{mode: :off}, _baseline), do: {nil, nil}

  defp evaluate_thresholds(measurement, %{mode: :absolute} = thresholds, _baseline) do
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
    |> checks_to_verdict()
  end

  defp evaluate_thresholds(measurement, %{mode: :auto, ratio: ratio}, baseline) do
    case baseline do
      :insufficient -> {nil, nil}
      %{} -> relative_checks(measurement, ratio, baseline) |> checks_to_verdict()
    end
  end

  defp relative_checks(measurement, ratio, baseline) do
    []
    |> maybe_relative_check(
      :download,
      baseline[:download],
      measurement.download_mbps,
      ratio,
      &Kernel.>=/2,
      "Mbps"
    )
    |> maybe_relative_check(
      :upload,
      baseline[:upload],
      measurement.upload_mbps,
      ratio,
      &Kernel.>=/2,
      "Mbps"
    )
    |> maybe_relative_check(
      :ping,
      baseline[:ping],
      measurement.ping_latency,
      ratio,
      &Kernel.<=/2,
      "ms"
    )
  end

  # No comparable metric → no verdict; otherwise healthy iff every check passed.
  defp checks_to_verdict([]), do: {nil, nil}

  defp checks_to_verdict(checks) do
    all_passed = Enum.all?(checks, fn {_, %{passed: p}} -> p end)
    {all_passed, Map.new(checks)}
  end

  # Absolute check: needs both a threshold and a measurement value. Skip when the
  # value is nil (a ping result has no bandwidth, so its download/upload checks
  # can't run - and `nil >= threshold` would raise) or when the threshold is unset.
  defp maybe_check(acc, _name, threshold, value, _compare, _unit)
       when is_nil(value) or not is_number(threshold) or threshold <= 0,
       do: acc

  defp maybe_check(acc, name, threshold, value, compare, unit) do
    acc ++
      [
        {name,
         %{passed: compare.(value, threshold), value: value, threshold: threshold, unit: unit}}
      ]
  end

  # Relative check against the rolling median. Needs a positive median and a
  # measurement value. Effective threshold: ratio×median for speed (lower-is-
  # better, breach below); median/ratio for ping (higher-is-worse, breach above).
  defp maybe_relative_check(acc, _name, median, value, _ratio, _compare, _unit)
       when is_nil(value) or not is_number(median) or median <= 0,
       do: acc

  defp maybe_relative_check(acc, name, median, value, ratio, compare, unit) do
    threshold = relative_threshold(name, median, ratio)

    acc ++
      [
        {name,
         %{passed: compare.(value, threshold), value: value, threshold: threshold, unit: unit}}
      ]
  end

  defp relative_threshold(:ping, median, ratio), do: median / ratio
  defp relative_threshold(_speed, median, ratio), do: ratio * median

  defp compute_transition(nil, _prior), do: nil
  defp compute_transition(false, 0), do: :breach
  defp compute_transition(true, prior) when prior > 0, do: :recovered
  defp compute_transition(true, _prior), do: :healthy
  defp compute_transition(false, _prior), do: nil
end
