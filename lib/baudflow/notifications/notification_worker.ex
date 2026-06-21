defmodule Baudflow.Notifications.NotificationWorker do
  @moduledoc """
  Oban worker that runs the four-layer notification pipeline on an event:

      event → policy (notify?) → template (render) → channel (fan out)

  The policy is the pure `Baudflow.Notifications.Policy` module; this worker
  reads `Settings` into the config it hands the policy, then — only when the
  policy says notify — loads the measurement, renders a message, and fans out to
  each enabled channel. ntfy today; webhook lands in #24; EEx templates in #26.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Baudflow.Measurements
  alias Baudflow.Notifications.{Event, Ntfy, Payload, Policy}
  alias Baudflow.Settings

  @impl true
  def perform(%Oban.Job{args: args}) do
    event = Event.from_args(args)

    # The policy only reads the event, so decide before paying for the
    # measurement fetch. Most events (healthy, sub-threshold breaches) skip here.
    if Policy.notify?(event, config()) do
      measurement = Measurements.get_measurement!(event.measurement_id)
      %Payload{event: event, measurement: measurement} |> render() |> fan_out()
    end

    :ok
  end

  # The streak threshold is the #21 "consecutive breaches before alert" knob.
  # Clamped to >= 1 so a 0/garbage value never silently disables breach alerts.
  defp config do
    %{breach_notify_streak: max(1, Settings.get_integer("breach_notify_streak", 1))}
  end

  # Hardcoded render — EEx templates land in #26.
  defp render(%Payload{event: %Event{kind: :breach}, measurement: m}) do
    """
    Speed threshold breached!

    #{failed_checks(m.benchmarks)}Server: #{m.server_name} (#{m.server_location})
    """
  end

  defp render(%Payload{event: %Event{kind: :recovered}, measurement: m}) do
    """
    Speed recovered.

    Thresholds are back in spec.
    Server: #{m.server_name} (#{m.server_location})
    """
  end

  # A failed test has no server/speed fields (nil speeds) — render the outage,
  # not "Server:  ()".
  defp render(%Payload{event: %Event{kind: :failed}, measurement: _m}) do
    """
    Speed test failed.

    The most recent test produced no result.
    """
  end

  # benchmarks is JSONB → string keys after the DB round-trip.
  defp failed_checks(benchmarks) when is_map(benchmarks) do
    benchmarks
    |> Enum.filter(fn
      {_, %{"passed" => p}} -> not p
      _ -> false
    end)
    |> Enum.map_join("", fn {metric, %{"value" => v, "threshold" => t, "unit" => u}} ->
      "#{String.capitalize(to_string(metric))}: #{fmt(v)} vs #{fmt(t)} #{u}\n"
    end)
  end

  defp failed_checks(_), do: ""

  defp fmt(n) when is_number(n), do: Float.round(n / 1, 1)
  defp fmt(_), do: "?"

  # Fan out to every enabled channel. ntfy today; webhook lands in #24.
  defp fan_out(message) do
    Ntfy.send(message)
  end
end
