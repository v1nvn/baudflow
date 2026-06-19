defmodule Baudflow.Notifications.NotificationWorker do
  @moduledoc """
  Oban worker that runs the four-layer notification pipeline on an event:

      event → policy → template (render) → channel (fan out)

  Step-0 policy notifies on absolute-threshold breach and test failure. Recovery
  (#22) and streak-gated (#21) policies are batch-4 slots; webhook (#24) and
  EEx templates (#26) add a second channel and editable rendering later.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  require Logger

  alias Baudflow.Measurements
  alias Baudflow.Notifications.{Event, Ntfy, Payload}

  @notifiable_kinds [:breach, :failed]

  @impl true
  def perform(%Oban.Job{args: args}) do
    event = Event.from_args(args)

    if policy(event) do
      measurement = Measurements.get_measurement!(event.measurement_id)
      payload = %Payload{event: event, measurement: measurement}
      render(payload) |> fan_out()
    end

    :ok
  end

  defp policy(%Event{kind: kind}), do: kind in @notifiable_kinds

  # Hardcoded render — EEx templates land in #26.
  defp render(%Payload{event: %Event{kind: :breach}, measurement: m}) do
    """
    Speed threshold breached!

    #{failed_checks(m.benchmarks)}Server: #{m.server_name} (#{m.server_location})
    """
  end

  defp render(%Payload{event: %Event{kind: :failed}, measurement: m}) do
    """
    Speed test failed.

    Server: #{m.server_name} (#{m.server_location})
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
